import XCTest
@testable import HEX

/// Isolated defaults + app-container stand-in. Never opens the owner's production log.
@MainActor
final class LogTestEnvironment {
    let suite = "dictation-log.tests.\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let settings: HexPlusSettings
    let storage: DictationLogStorage
    let store: DictationLogStore

    init(enabled: Bool = true) {
        defaults = UserDefaults(suiteName: suite)!
        settings = HexPlusSettings(defaults: defaults)
        settings.dictationLog = enabled
        storage = DictationLogStorage(url: directory.appendingPathComponent("dictation-log.json"))
        store = DictationLogStore(storage: storage, settings: settings)
    }

    func begin(context: DictationLogContext = DictationLogContext(),
               clock: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) -> DictationLogRecording {
        store.begin(token: store.token(), context: context, clock: clock)!
    }

    func dispose() async {
        await storage.flush()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class DictationLogStoreTests: XCTestCase {
    func testDefaultOnAndTextCapsAtCharacterBoundaries() {
        let suite = "dictation-log.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HexPlusSettings(defaults: defaults)
        XCTAssertTrue(settings.dictationLog)
        settings.dictationLog = false
        XCTAssertFalse(HexPlusSettings(defaults: defaults).dictationLog)
        for source in [String(repeating: "ä", count: 4_000), String(repeating: "👩🏽‍💻", count: 1_000),
                       String(repeating: "e\u{301}", count: 3_000), String(repeating: "x", count: 4_000)] {
            let field = DictationLogText(source)
            XCTAssertEqual(field.originalUTF8Bytes, source.utf8.count)
            XCTAssertLessThanOrEqual(field.text.utf8.count, 4_000)
            XCTAssertEqual(field.truncated, source.utf8.count > 4_000)
            if field.truncated {
                XCTAssertTrue(field.text.hasSuffix("…"))
                XCTAssertTrue(source.hasPrefix(String(field.text.dropLast())))
            } else { XCTAssertEqual(field.text, source) }
        }
        let wordField = DictationLogText(String(repeating: "hello ", count: 1_000))
        XCTAssertEqual(wordField.wordCount, 1_000) // Computed before the cap.
    }

    func testNewestTwentyEvictionAndRoundTripWithInterruptedRecovery() async throws {
        let env = LogTestEnvironment()
        let evicted = env.begin()
        for index in 0..<22 {
            var context = DictationLogContext()
            context.createdAt = Date(timeIntervalSince1970: Double(index + 1))
            let recording = env.begin(context: context)
            recording.recognized("raw \(index)", spelled: "raw \(index)", asrMilliseconds: 12)
            if index != 21 { recording.finish(text: "final \(index)", beforeSpelling: "final \(index)") }
        }
        evicted.modelAnswer("must not return", use: .late, modelMilliseconds: 999)
        XCTAssertEqual(env.store.entries.count, 20)
        XCTAssertFalse(env.store.entries.contains { $0.id == evicted.entryID })
        await env.storage.flush()
        let values = try env.storage.url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let reloaded = DictationLogStore(storage: env.storage, settings: env.settings)
        XCTAssertEqual(reloaded.entries.count, 20)
        XCTAssertEqual(reloaded.entries.first?.status, .interrupted)
        XCTAssertEqual(reloaded.entries.first?.recognized?.text, "raw 21")
        XCTAssertEqual(reloaded.entries.last?.finalText?.text, "final 2")
        XCTAssertTrue(reloaded.entries.allSatisfy { $0.status != .transcribing })
        await env.dispose()
    }

    func testClearOffAndOffOnInvalidateCaptureTokensAndPendingWrites() async throws {
        for mode in 0..<3 {
            let env = LogTestEnvironment()
            let token = env.store.token() // Permission was frozen while recording.
            let recording = env.begin()
            for _ in 0..<10 { recording.recognized("private speech", spelled: "private speech", asrMilliseconds: 5) }
            if mode == 0 { env.store.clear() }
            else {
                env.store.setEnabled(false)
                if mode == 2 { env.store.setEnabled(true) }
            }
            XCTAssertNil(env.store.begin(token: token, context: DictationLogContext()))
            recording.finish(text: "must not reappear", beforeSpelling: "must not reappear")
            recording.modelAnswer("secret", use: .late, modelMilliseconds: 8)
            // Even a stale request submitted directly to the writer cannot replace the delete.
            env.storage.submit(Data("stale snapshot".utf8), epoch: token.epoch) { _, _ in }
            await env.storage.flush()
            XCTAssertTrue(env.store.entries.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: env.storage.url.path))
            let reloaded = DictationLogStore(storage: env.storage, settings: env.settings)
            XCTAssertTrue(reloaded.entries.isEmpty)
            await env.dispose()
        }
    }

    func testDisabledInitDeletesBeforeLoadAndRejectsNewRecordings() async throws {
        let env = LogTestEnvironment()
        env.begin().finish(text: "saved", beforeSpelling: "saved")
        await env.storage.flush()
        env.settings.dictationLog = false
        let off = DictationLogStore(storage: env.storage, settings: env.settings)
        XCTAssertFalse(off.isEnabled)
        XCTAssertTrue(off.entries.isEmpty)
        XCTAssertNil(off.begin(token: off.token(), context: DictationLogContext()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.storage.url.path))
        await env.dispose()
    }

    func testInvalidOversizedAndUnknownSchemasAreDeleted() async throws {
        for data in [Data("not JSON".utf8), Data(repeating: 32, count: 1_000_001),
                     Data(#"{"schemaVersion":999,"entries":[]}"#.utf8)] {
            let env = LogTestEnvironment()
            try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
            try data.write(to: env.storage.url)
            let reloaded = DictationLogStore(storage: env.storage, settings: env.settings)
            XCTAssertTrue(reloaded.entries.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: env.storage.url.path))
            await env.dispose()
        }
    }

    func testLoadRecapsFieldsAndUnknownEntrySchemaIsDeleted() async throws {
        let env = LogTestEnvironment()
        var entry = DictationLogEntry(context: DictationLogContext())
        entry.recognized = DictationLogText("abc")
        // Inject an uncapped text into the encoded representation (not through production init).
        let document = DictationLogDocument(entries: [entry])
        let encoded = try JSONEncoder().encode(document)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        var field = try XCTUnwrap(entries[0]["recognized"] as? [String: Any])
        field["text"] = String(repeating: "ü", count: 5_000)
        entries[0]["recognized"] = field
        object["entries"] = entries
        try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: env.storage.url)
        let loaded = DictationLogStore(storage: env.storage, settings: env.settings)
        XCTAssertLessThanOrEqual(try XCTUnwrap(loaded.entries.first?.recognized).text.utf8.count, 4_000)
        await env.storage.flush()
        entries[0]["schemaVersion"] = 999
        object["entries"] = entries
        try JSONSerialization.data(withJSONObject: object).write(to: env.storage.url)
        let unknown = DictationLogStore(storage: env.storage, settings: env.settings)
        XCTAssertTrue(unknown.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.storage.url.path))
        await env.dispose()
    }

    func testEncodedSizeCapWithEscapeHeavyTextIsAlwaysLoadable() async throws {
        let env = LogTestEnvironment()
        let source = String(repeating: "\u{1}", count: 3_900) + "\"\\👩🏽‍💻"
        for _ in 0..<25 {
            let recording = env.begin()
            recording.recognized(source, spelled: "changed " + source, asrMilliseconds: 1)
            recording.modelAnswer(source, use: .accepted, modelMilliseconds: 1)
            recording.finish(text: source, beforeSpelling: source)
        }
        await env.storage.flush()
        let data = try Data(contentsOf: env.storage.url)
        XCTAssertLessThanOrEqual(data.count, DictationLogStorage.maximumBytes)
        let document = try JSONDecoder().decode(DictationLogDocument.self, from: data)
        XCTAssertEqual(document.entries.count, env.store.entries.count)
        XCTAssertFalse(document.entries.isEmpty)
        XCTAssertLessThan(document.entries.count, 20) // JSON escaping, not the raw-field cap, evicted entries.
        let loaded = DictationLogStore(storage: env.storage, settings: env.settings)
        XCTAssertEqual(loaded.entries, env.store.entries)
        await env.dispose()
    }

    func testStorageProblemCanBeRecoveredWithoutAnOldCompletionReplacingIt() async throws {
        let env = LogTestEnvironment()
        try Data("parent is a file".utf8).write(to: env.directory)
        env.begin().finish(text: "still delivered", beforeSpelling: "still delivered")
        await env.storage.flush()
        try await Task.sleep(for: .milliseconds(25)) // Drain the main-actor completion, not disk.
        XCTAssertNotNil(env.store.storageProblem)
        try FileManager.default.removeItem(at: env.directory)
        env.store.clear()
        await env.storage.flush()
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertNil(env.store.storageProblem)
        XCTAssertTrue(env.store.entries.isEmpty)
        await env.dispose()
    }

    func testTerminalRulesLateLabelsAndExactlyOneStatus() async throws {
        let env = LogTestEnvironment()
        for failure in [CleanupFailureReason.deadline, .expired] {
            let recording = env.begin()
            recording.recognized("plain words here", spelled: "plain words here", asrMilliseconds: 1)
            recording.cleanupResolved(.init(outcome: .failed(failure), latencyMilliseconds: 4_000), changed: nil)
            recording.finish(text: "Plain words here.", beforeSpelling: "Plain words here.")
            let finished = try XCTUnwrap(env.store.entries.first)
            recording.finishIfOpen(.cancelled)
            recording.modelAnswer("late answer", use: .late, modelMilliseconds: 6_000)
            let late = try XCTUnwrap(env.store.entries.first)
            XCTAssertEqual(late.status, .finished)
            XCTAssertEqual(late.finalText, finished.finalText)
            XCTAssertEqual(late.cleanupOutcome, finished.cleanupOutcome)
            XCTAssertEqual(late.stopToFinalMilliseconds, finished.stopToFinalMilliseconds)
            XCTAssertEqual(late.modelMilliseconds, 6_000)
            XCTAssertEqual(late.aiAnswer?.text, "late answer")
            XCTAssertEqual(late.answerLabel, failure == .deadline
                ? "arrived after the 4 s deadline; not used"
                : "arrived after iOS ended the background time; not used")
            recording.modelAnswer("not late", use: .accepted, modelMilliseconds: 7_000)
            XCTAssertEqual(env.store.entries.first, late)
        }
        let failed = env.begin()
        failed.failASR(ParakeetTranscriber.TranscriberError.emptyTranscript, milliseconds: 3)
        failed.modelAnswer("late", use: .late, modelMilliseconds: 7)
        XCTAssertEqual(env.store.entries.first?.status, .asrFailed)
        XCTAssertEqual(env.store.entries.first?.asrFailure, .noSpeech)
        XCTAssertEqual(env.store.entries.first?.aiAnswer?.text, "late")
        XCTAssertNil(env.store.entries.first?.finalText)
        XCTAssertEqual(env.store.entries.first?.answerLabel, "arrived after cleanup had resolved; not used")
        for status in [DictationLogStatus.cancelled, .interrupted] {
            let recording = env.begin()
            recording.finishIfOpen(status)
            let terminal = env.store.entries.first
            recording.recognized("ignored", spelled: "ignored", asrMilliseconds: 1)
            recording.modelAnswer("ignored", use: .late, modelMilliseconds: 1)
            recording.cleanupResolved(.init(outcome: .completed, latencyMilliseconds: 1), changed: true)
            recording.finish(text: "ignored", beforeSpelling: "ignored")
            XCTAssertEqual(env.store.entries.first, terminal)
        }
        await env.dispose()
    }
}
