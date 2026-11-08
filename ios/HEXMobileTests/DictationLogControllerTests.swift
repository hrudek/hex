import XCTest
@testable import HEX

@MainActor
private final class LogAudio: AudioManaging {
    var isKeepaliveRunning = false
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?
    var duration: TimeInterval = 1.5
    func requestPermission() async -> Bool { true }
    func startKeepalive(allowBluetooth: Bool) throws { isKeepaliveRunning = true }
    func stopKeepalive() { isKeepaliveRunning = false }
    func deactivateSession() { isKeepaliveRunning = false }
    func beginCapture(at url: URL, maxDuration: TimeInterval, allowBluetooth: Bool) throws -> any ActiveAudioCapture {
        LogCapture(url: url, duration: duration)
    }
}

@MainActor
private final class LogCapture: ActiveAudioCapture {
    let url: URL
    var isRecording = true
    let currentTime: TimeInterval
    init(url: URL, duration: TimeInterval) {
        self.url = url
        currentTime = duration
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    func normalizedPowerLevel() -> Float { 0.5 }
    func averagePowerDB() -> Float { -24 }
    func stop() { isRecording = false }
}

private actor LogControlledTranscriber: LocalTranscribing {
    nonisolated let displayName = "Controlled Speech"
    let languageName = "German"
    var gate: CheckedContinuation<String, Error>?
    var suspendNext = false
    var shouldFail = false
    var output = "Die Katze sitzt auf der Mathe"
    func arm() { suspendNext = true }
    func fail() { shouldFail = true }
    func setOutput(_ text: String) { output = text }
    func resume() { gate?.resume(returning: output); gate = nil }
    func isWaiting() -> Bool { gate != nil }
    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {}
    func transcribe(_ url: URL) async throws -> String {
        if shouldFail { throw ParakeetTranscriber.TranscriberError.notPrepared }
        if suspendNext {
            suspendNext = false
            return try await withCheckedThrowingContinuation { gate = $0 }
        }
        return output
    }
}

private struct LogSecretFailure: Error, LocalizedError {
    let payload = "SECRET-ERROR-PAYLOAD"
    var errorDescription: String? { payload }
}

@MainActor
private final class LogUpstreamCleaner: TranscriptCleaning {
    var isAvailable = true
    var result: String?
    func clean(_ text: String) async -> String? { result }
}

@MainActor
private final class LogControllerFixture {
    let env = LogTestEnvironment()
    let audio = LogAudio()
    let asr = LogControlledTranscriber()
    let model = CleanupTestSession()
    let background = CleanupTestBackground()
    let sleeper = CleanupTestSleeper()
    let controller: DictationController
    let bridge: KeyboardBridge

    init(injectLog: Bool = true) {
        bridge = KeyboardBridge(defaults: env.defaults)
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: model), language: CleanupTestLanguage(),
            background: background, isEnabled: { true }, sleep: sleeper.sleep)
        let activeASR = asr
        controller = DictationController(audio: audio, keyboardBridge: bridge, transcriber: activeASR,
            transcriberFactory: { activeASR }, autoPrepareOnInit: false,
            cleanupSettings: AppleIntelligenceCleanupSettings(defaults: env.defaults),
            customVocabularySettings: CustomVocabularySettings(defaults: env.defaults),
            cleanup: deps, dictationLog: injectLog ? env.store : nil)
    }

    func settle() async throws {
        // Same bounded settling pattern as the existing controller tests; model/ASR waits
        // themselves are continuation-driven, not simulated four-second wall-clock waits.
        for _ in 0..<8 { try await Task.sleep(for: .milliseconds(25)) }
    }
    func start() async throws {
        controller.prepareModel(); try await settle()
        controller.startRecording(keyboardJobID: "a"); try await settle()
    }
    func dispose() async throws {
        controller.cancelCurrentJob()
        await asr.resume()
        model.resume()
        sleeper.fire()
        try await settle()
        await env.dispose()
    }
}

@MainActor
final class DictationLogControllerTests: XCTestCase {
    func testCleanupProducesOneFinishedEntryWithTextsOutcomesAndTimings() async throws {
        let f = LogControllerFixture()
        try await f.start()
        f.controller.finishRecording(); try await f.settle()
        let entry = try XCTUnwrap(f.env.store.entries.first)
        XCTAssertEqual(f.env.store.entries.count, 1)
        XCTAssertEqual(entry.status, .finished)
        XCTAssertEqual(entry.recognized?.text, "Die Katze sitzt auf der Mathe")
        XCTAssertNil(entry.aiInput)
        XCTAssertEqual(entry.aiAnswer?.text, "Die Katze sitzt auf der Matte")
        XCTAssertEqual(entry.finalText?.text, "Die Katze sitzt auf der Matte.")
        XCTAssertEqual(f.bridge.snapshot().transcript, entry.finalText?.text)
        XCTAssertEqual(entry.cleanupOutcome, "completed")
        XCTAssertEqual(entry.cleanupChanged, true)
        XCTAssertEqual(entry.context.cleanupPath, .hexPlus)
        XCTAssertEqual(entry.context.speechEngine, "Controlled Speech")
        XCTAssertEqual(entry.context.speechLanguage, "German")
        XCTAssertEqual(entry.context.loudestAverageDBFS, -24)
        XCTAssertEqual(entry.context.recordingDuration, 1.5)
        XCTAssertTrue(entry.context.keyboardJob)
        XCTAssertFalse(entry.context.copyToPasteboard)
        XCTAssertTrue(entry.outputLabel.contains("provided to keyboard"))
        XCTAssertNotNil(entry.asrMilliseconds)
        XCTAssertNotNil(entry.modelMilliseconds)
        XCTAssertNotNil(entry.cleanupMilliseconds)
        XCTAssertNotNil(entry.stopToFinalMilliseconds)
        XCTAssertEqual(entry.promptRevision, "2026-11-08a")
        XCTAssertEqual(entry.guardRevision, "2026-11-08a")
        try await f.dispose()
    }

    func testASRFailureIsCategorizedWithoutErrorDescription() async throws {
        let f = LogControllerFixture()
        await f.asr.fail()
        try await f.start()
        f.controller.finishRecording(); try await f.settle()
        XCTAssertEqual(f.env.store.entries.first?.status, .asrFailed)
        XCTAssertEqual(f.env.store.entries.first?.asrFailure, .modelNotReady)
        XCTAssertNil(f.env.store.entries.first?.finalText)
        XCTAssertNil(f.env.store.entries.first?.asrErrorType)
        XCTAssertEqual(DictationLogASRFailure.classify(ParakeetTranscriber.TranscriberError.emptyTranscript), .noSpeech)
        XCTAssertEqual(DictationLogASRFailure.classify(CancellationError()), .cancelled)
        XCTAssertEqual(DictationLogASRFailure.classify(CocoaError(.fileReadUnknown)), .other)
        try await f.dispose()
    }

    func testCancelAndReplacementTerminateBeforeUncooperativeASRReturns() async throws {
        for replace in [false, true] {
            let f = LogControllerFixture()
            await f.asr.arm()
            try await f.start()
            f.controller.finishRecording(); try await f.settle()
            let waiting = await f.asr.isWaiting()
            XCTAssertTrue(waiting)
            let id = try XCTUnwrap(f.env.store.entries.first?.id)
            if replace { f.controller.startRecording(keyboardJobID: "b") }
            else { f.controller.cancelCurrentJob() }
            // No settling or ASR resumption needed to see cancellation.
            XCTAssertEqual(f.env.store.entries.first?.status, .cancelled)
            XCTAssertNil(f.env.store.entries.first?.finalText)
            await f.asr.resume(); try await f.settle()
            let cancelled = try XCTUnwrap(f.env.store.entries.first { $0.id == id })
            XCTAssertEqual(cancelled.status, .cancelled)
            XCTAssertNil(cancelled.recognized)
            XCTAssertNil(cancelled.finalText)
            if replace {
                f.controller.finishRecording(); try await f.settle()
                XCTAssertEqual(f.env.store.entries.count, 2)
                XCTAssertEqual(f.env.store.entries.first?.status, .finished)
            }
            try await f.dispose()
        }
    }

    func testWarmSessionEndDuringAcceptedCleanupStillFinishes() async throws {
        let f = LogControllerFixture()
        f.model.suspend = true
        f.controller.prepareModel(); try await f.settle()
        f.controller.selectWarmDuration(.fifteenMinutes); try await f.settle()
        f.controller.startRecording(keyboardJobID: "warm"); try await f.settle()
        f.controller.finishRecording(); try await f.settle()
        XCTAssertEqual(f.env.store.entries.first?.status, .transcribing)
        f.controller.endWarmSession()
        f.model.resume(); try await f.settle()
        XCTAssertEqual(f.env.store.entries.first?.status, .finished)
        XCTAssertEqual(f.env.store.entries.first?.finalText?.text, f.controller.transcript)
        try await f.dispose()
    }

    func testFinishedDeadlineAndExpiryEntriesGainOnlyTheirOwnLateAnswer() async throws {
        for expire in [false, true] {
            let f = LogControllerFixture()
            f.model.suspend = true
            try await f.start()
            f.controller.finishRecording(); try await f.settle()
            XCTAssertNotNil(f.model.gate)
            if expire { f.background.expiration?() } else { f.sleeper.fire() }
            try await f.settle()
            let first = try XCTUnwrap(f.env.store.entries.first)
            XCTAssertEqual(first.status, .finished)
            XCTAssertEqual(first.finalText?.text, "Die Katze sitzt auf der Mathe.")
            XCTAssertEqual(first.cleanupOutcome, expire ? "failed(expired)" : "failed(deadline)")
            // A second dictation skips busy while A still owns the model reservation.
            f.controller.startRecording(keyboardJobID: "b"); try await f.settle()
            f.controller.finishRecording(); try await f.settle()
            let b = f.env.store.entries.first
            XCTAssertEqual(b?.cleanupOutcome, "skipped(busy)")
            let delivered = f.bridge.snapshot().resultID
            f.model.resume(); try await f.settle()
            let late = try XCTUnwrap(f.env.store.entries.first { $0.id == first.id })
            XCTAssertEqual(late.status, .finished)
            XCTAssertEqual(late.finalText, first.finalText)
            XCTAssertEqual(late.cleanupOutcome, first.cleanupOutcome)
            XCTAssertEqual(late.aiAnswer?.text, f.model.result)
            XCTAssertEqual(late.answerUse, "late")
            XCTAssertNotNil(late.modelMilliseconds)
            XCTAssertEqual(f.env.store.entries.first, b)
            XCTAssertEqual(f.bridge.snapshot().resultID, delivered)
            try await f.dispose()
        }
    }

    func testClearOffAndOffOnDuringASROrRecordingNeverRevivePermission() async throws {
        for duringASR in [false, true] {
            for mode in 0..<3 {
                let f = LogControllerFixture()
                if duringASR { await f.asr.arm() }
                try await f.start()
                if duringASR { f.controller.finishRecording(); try await f.settle() }
                if mode == 0 { f.env.store.clear() }
                else {
                    f.env.store.setEnabled(false)
                    if mode == 2 { f.env.store.setEnabled(true) }
                }
                if duringASR { await f.asr.resume() } else { f.controller.finishRecording() }
                try await f.settle()
                XCTAssertFalse(f.controller.transcript.isEmpty)
                XCTAssertTrue(f.env.store.entries.isEmpty)
                await f.env.storage.flush()
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.env.storage.url.path))
                try await f.dispose()
            }
        }
    }

    func testNoInjectedLogAndShortOrCancelledCaptureProduceNoEntries() async throws {
        let noLog = LogControllerFixture(injectLog: false)
        try await noLog.start()
        noLog.controller.finishRecording(); try await noLog.settle()
        XCTAssertFalse(noLog.controller.transcript.isEmpty)
        XCTAssertTrue(noLog.env.store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: noLog.env.storage.url.path))
        try await noLog.dispose()
        for short in [false, true] {
            let f = LogControllerFixture()
            if short { f.audio.duration = 0.1 }
            try await f.start()
            if short { f.controller.finishRecording() } else { f.controller.cancelCurrentJob() }
            try await f.settle()
            XCTAssertTrue(f.env.store.entries.isEmpty)
            try await f.dispose()
        }
    }

    func testUnwritableStorageDoesNotAffectDelivery() async throws {
        let f = LogControllerFixture()
        try FileManager.default.createDirectory(at: f.env.directory, withIntermediateDirectories: true)
        // A regular file where the log's parent directory belongs fails even as an admin.
        try FileManager.default.removeItem(at: f.env.directory)
        try Data("not a directory".utf8).write(to: f.env.directory)
        try await f.start()
        f.controller.finishRecording(); try await f.settle()
        await f.env.storage.flush(); try await f.settle()
        XCTAssertEqual(f.controller.phase, .ready)
        XCTAssertEqual(f.controller.transcript, "Die Katze sitzt auf der Matte.")
        XCTAssertEqual(f.env.store.entries.first?.status, .finished)
        XCTAssertNotNil(f.env.store.storageProblem)
        try await f.dispose()
    }

    func testExplicitExportsIncludeEvidenceAndNoWholeVocabularyOrErrorPayload() async throws {
        let env = LogTestEnvironment()
        let recording = env.begin()
        recording.recognized("spoken secret", spelled: "spoken Secret", asrMilliseconds: 12)
        recording.modelAnswer("unused answer", use: .rejected(.emptyOutput), modelMilliseconds: 20)
        recording.finish(text: "Spoken Secret.", beforeSpelling: "Spoken Secret.")
        let entry = try XCTUnwrap(env.store.entries.first)
        let export = entry.plainText
        for evidence in ["spoken secret", "spoken Secret", "unused answer", "Spoken Secret.",
                         "rejected(empty-output); not used", "12 ms", "20 ms", "does not prove insertion"] {
            XCTAssertTrue(export.contains(evidence), evidence)
        }
        XCTAssertFalse(export.contains("vocabularyTerms"))
        XCTAssertFalse(export.contains("errorDescription"))
        let failedRecording = env.begin()
        failedRecording.failASR(LogSecretFailure(), milliseconds: 4)
        let failed = try XCTUnwrap(env.store.entries.first)
        XCTAssertEqual(failed.asrFailure, .other)
        XCTAssertTrue(failed.asrErrorType?.hasSuffix("LogSecretFailure") == true)
        XCTAssertFalse(failed.plainText.contains("SECRET-ERROR-PAYLOAD"))
        await env.dispose()
    }

    func testVocabularyEvidenceAndUpstreamPathOnlyClaimKnownOutcomes() async throws {
        let env = LogTestEnvironment(), asr = LogControlledTranscriber(), audio = LogAudio()
        let vocabulary = CustomVocabularySettings(defaults: env.defaults)
        vocabulary.isEnabled = true
        vocabulary.terms = ["iPhone"]
        await asr.setOutput("my iphone works")
        let upstream = LogUpstreamCleaner()
        let cleanupSettings = AppleIntelligenceCleanupSettings(defaults: env.defaults)
        cleanupSettings.isEnabled = true
        let controller = DictationController(audio: audio, keyboardBridge: KeyboardBridge(defaults: env.defaults),
            transcriber: asr, transcriberFactory: { asr }, autoPrepareOnInit: false, cleaner: upstream,
            cleanupSettings: cleanupSettings, customVocabularySettings: vocabulary, dictationLog: env.store)
        func settle() async throws { for _ in 0..<8 { try await Task.sleep(for: .milliseconds(25)) } }
        controller.prepareModel(); try await settle()
        for result in [String?.none, "my iPhone works", "my iPhone works well"] {
            upstream.result = result
            controller.startRecording(); try await settle()
            controller.finishRecording(); try await settle()
            let entry = try XCTUnwrap(env.store.entries.first)
            XCTAssertEqual(entry.context.cleanupPath, .upstream)
            XCTAssertEqual(entry.recognized?.text, "my iphone works")
            XCTAssertEqual(entry.aiInput?.text, "my iPhone works")
            XCTAssertEqual(entry.context.vocabularyCount, 1)
            XCTAssertTrue(entry.firstSpellingChanged)
            XCTAssertEqual(entry.upstreamOutcome, result.map { $0 == "my iPhone works" ? "unchanged" : "changed" } ?? "no result")
            XCTAssertNil(entry.aiAnswer) // Upstream API does not expose raw model answers.
            XCTAssertNil(entry.cleanupOutcome)
        }
        controller.cancelCurrentJob()
        await env.dispose()
    }
}
