import XCTest
import UIKit
@testable import Typr

@MainActor
private final class CleanupAudio: AudioManaging {
    var isKeepaliveRunning = false
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var onUnexpectedCaptureEnd: ((URL, Bool) -> Void)?
    func requestPermission() async -> Bool { true }
    func startKeepalive(allowBluetooth: Bool) throws { isKeepaliveRunning = true }
    func stopKeepalive() { isKeepaliveRunning = false }
    func deactivateSession() { isKeepaliveRunning = false }
    func beginCapture(at url: URL, maxDuration: TimeInterval, allowBluetooth: Bool) throws -> any ActiveAudioCapture {
        CleanupCapture(url: url)
    }
}

@MainActor
private final class CleanupCapture: ActiveAudioCapture {
    let url: URL
    var isRecording = true
    var currentTime: TimeInterval { 1.5 }
    init(url: URL) {
        self.url = url
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    func normalizedPowerLevel() -> Float { 0.5 }
    func stop() { isRecording = false }
}

private actor CleanupASR: LocalTranscribing {
    nonisolated let displayName = "Test ASR"
    let languageName = "German"
    var gate: CheckedContinuation<String, Error>?
    var suspend = false
    var shouldThrow = false
    func arm() { suspend = true }
    func fail() { shouldThrow = true }
    func resume() { gate?.resume(returning: "Die Katze sitzt auf der Mathe"); gate = nil }
    func prepare(progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void) async throws {}
    func transcribe(_ url: URL) async throws -> String {
        if shouldThrow { throw CocoaError(.fileReadUnknown) }
        if suspend { return try await withCheckedThrowingContinuation { gate = $0 } }
        return "Die Katze sitzt auf der Mathe"
    }
}

@MainActor
final class AICleanupControllerTests: XCTestCase {
    private func settle() async throws {
        for _ in 0..<8 { try await Task.sleep(for: .milliseconds(25)) }
    }

    func testControllerDeliveryFallbackAndFrozenSwitch() async throws {
        // mode: on, off, verbatim, nil, error, on->off, off->on, ASR failure.
        for mode in 0..<8 {
            let suite = "cleanup.controller.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let bridge = KeyboardBridge(defaults: defaults)
            let model = CleanupTestSession(), bg = CleanupTestBackground(), clock = CleanupTestSleeper(), observer = CleanupTestObserver()
            model.shouldThrow = mode == 4
            var enabled = mode != 1 && mode != 6
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: model), language: CleanupTestLanguage(),
                background: bg, isEnabled: { enabled }, sleep: clock.sleep, observer: observer)
            let asr = CleanupASR()
            if mode == 7 { await asr.fail() }
            let controller = DictationController(audio: CleanupAudio(), keyboardBridge: bridge, transcriber: asr,
                transcriberFactory: { asr }, autoPrepareOnInit: false, cleanup: mode == 3 ? nil : deps)
            controller.prepareModel(); try await settle()
            let style: DictationStyle = mode == 2 ? .verbatim : .polished
            controller.startRecording(keyboardJobID: "job", styleOverride: style, copyToPasteboard: true)
            try await settle()
            if mode == 5 { enabled = false }
            if mode == 6 { enabled = true }
            controller.finishRecording(); try await settle()
            if mode == 7 {
                if case .failed = controller.phase {} else { XCTFail("ASR failure must retain existing failure path") }
                XCTAssertEqual(bg.ends, [1])
            } else {
                let cleaned = mode == 0 || mode == 5
                let expected = cleaned ? "Die Katze sitzt auf der Matte." : (mode == 2 ? "Die Katze sitzt auf der Mathe" : "Die Katze sitzt auf der Mathe.")
                XCTAssertEqual(controller.transcript, expected)
                XCTAssertEqual(bridge.snapshot().transcript, expected)
                XCTAssertEqual(UIPasteboard.general.string, expected)
                XCTAssertTrue(controller.copied)
                XCTAssertEqual(controller.phase, .ready)
                let attempted = mode == 0 || mode == 4 || mode == 5
                XCTAssertEqual(model.cleanCount, attempted ? 1 : 0)
                XCTAssertEqual(model.prepareCount, attempted ? 1 : 0)
                let expectedOutcome: CleanupOutcome = cleaned ? .completed : (mode == 4 ? .failed(.generationFailed) : .skipped(mode == 2 ? .verbatim : .off))
                XCTAssertEqual(observer.events.map(\.outcome), mode == 3 ? [] : [expectedOutcome])
            }
            controller.cancelCurrentJob(); clock.fire(); try await settle()
        }
    }

    func testCancellationDropsLateModelAndBusyNextJobFallsBack() async throws {
        let suite = "cleanup.controller.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = KeyboardBridge(defaults: defaults), model = CleanupTestSession()
        model.suspend = true
        let bg = CleanupTestBackground(), clock = CleanupTestSleeper(), asr = CleanupASR(), observer = CleanupTestObserver()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: model), language: CleanupTestLanguage(),
            background: bg, isEnabled: { true }, sleep: clock.sleep, observer: observer)
        let controller = DictationController(audio: CleanupAudio(), keyboardBridge: bridge, transcriber: asr,
            transcriberFactory: { asr }, autoPrepareOnInit: false, cleanup: deps)
        controller.prepareModel(); try await settle()
        controller.startRecording(keyboardJobID: "a"); try await settle()
        controller.finishRecording(); try await settle()
        XCTAssertEqual(controller.phase, .transcribing)
        controller.cancelCurrentJob(); try await settle()
        XCTAssertTrue(controller.transcript.isEmpty)
        XCTAssertEqual(bg.ends, [1])
        controller.startRecording(keyboardJobID: "b"); try await settle()
        controller.finishRecording(); try await settle()
        XCTAssertEqual(controller.transcript, "Die Katze sitzt auf der Mathe.")
        let resultID = bridge.snapshot().resultID
        model.resume(); try await settle()
        XCTAssertEqual(controller.transcript, "Die Katze sitzt auf der Mathe.")
        XCTAssertEqual(bridge.snapshot().resultID, resultID)
        XCTAssertEqual(model.cleanCount, 1)
        XCTAssertEqual(observer.events.map(\.outcome), [.cancelled, .skipped(.busy)])
        controller.cancelCurrentJob(); clock.fire(); try await settle()
    }

    func testExpiryDuringASRAndWarmSessionEndDuringCleanup() async throws {
        for expire in [false, true] {
            let suite = "cleanup.controller.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let bridge = KeyboardBridge(defaults: defaults), model = CleanupTestSession()
            model.suspend = !expire
            let bg = CleanupTestBackground(), clock = CleanupTestSleeper(), asr = CleanupASR()
            if expire { await asr.arm() }
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: model), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: clock.sleep)
            let controller = DictationController(audio: CleanupAudio(), keyboardBridge: bridge, transcriber: asr,
                transcriberFactory: { asr }, autoPrepareOnInit: false, cleanup: deps)
            controller.prepareModel(); try await settle()
            controller.selectWarmDuration(.fifteenMinutes); try await settle()
            controller.startRecording(keyboardJobID: "warm"); try await settle()
            controller.finishRecording(); try await settle()
            if expire { bg.expiration?(); await asr.resume() }
            else { controller.endWarmSession(); model.resume() }
            try await settle()
            XCTAssertEqual(controller.phase, .ready)
            XCTAssertEqual(controller.transcript, expire ? "Die Katze sitzt auf der Mathe." : "Die Katze sitzt auf der Matte.")
            XCTAssertEqual(bg.ends, [1])
            XCTAssertEqual(model.cleanCount, expire ? 0 : 1)
            controller.cancelCurrentJob(); clock.fire(); try await settle()
        }
    }
}
