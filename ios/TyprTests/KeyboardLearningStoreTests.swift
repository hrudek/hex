import Foundation
import XCTest
@testable import Typr

@MainActor
final class KeyboardLearningStoreTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let directory: URL
        let defaults: UserDefaults
        let suite: String

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            suite = "KeyboardLearningStoreTests.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func store() -> KeyboardLearningStore { KeyboardLearningStore(directory: directory, defaults: defaults) }
        func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
        func clean() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testRoundTripSummaryAndFileMetadata() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let model = PersonalTypingModel()
        model.keep("hello"); model.recordWord("hello")
        model.rejectCorrection(typed: "hello", replacement: "help")
        let layout = KeyboardLayout(width: 393)
        let key = try XCTUnwrap(layout.key(.character("a")))
        model.learn([.init(point: CGPoint(x: key.frame.midX, y: key.frame.midY), letter: "a")], layout: layout, source: .keep)
        var diagnostics = KeyboardDiagnostics()
        diagnostics.increment(.boundaries)
        let store = fixture.store()
        XCTAssertTrue(store.save(model: model.state, diagnostics: &diagnostics))
        let (loaded, counters) = fixture.store().load()
        XCTAssertEqual(loaded, model.state)
        XCTAssertEqual(counters, diagnostics)
        let snapshot = KeyboardLearningStore.readSnapshot(directory: fixture.directory, defaults: fixture.defaults)
        XCTAssertTrue(snapshot.isPersistent)
        XCTAssertEqual(snapshot.model, model.summary)
        XCTAssertEqual(snapshot.diagnostics, diagnostics)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.learningFile.bytes), 0)
        XCTAssertNotNil(snapshot.learningFile.modifiedAt)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.diagnosticsFile.bytes), 0)
        XCTAssertNotNil(snapshot.diagnosticsFile.modifiedAt)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let values = try fixture.file("learning-v1.json").resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testOversizedFilesAreDiscardedBeforeDecode() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        try Data(repeating: 32, count: KeyboardLearningStore.maximumLearningBytes + 1).write(to: fixture.file("learning-v1.json"))
        try Data(repeating: 32, count: KeyboardLearningStore.maximumDiagnosticsBytes + 1).write(to: fixture.file("diagnostics-v1.json"))
        let (model, diagnostics) = fixture.store().load()
        XCTAssertNil(model)
        XCTAssertEqual(diagnostics[.storeCorruptDiscarded], 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted(),
                       ["diagnostics-v1.json", "learning-v1.json", "learning.lock"])
    }

    func testCorruptJSONAndInvalidStateDiscardWithoutQuarantine() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        try Data("not json".utf8).write(to: fixture.file("learning-v1.json"))
        try Data("{}".utf8).write(to: fixture.file("diagnostics-v1.json"))
        let store = fixture.store()
        var (state, diagnostics) = store.load()
        XCTAssertNil(state)
        XCTAssertEqual(diagnostics[.storeCorruptDiscarded], 2)
        XCTAssertTrue(store.save(model: .init(), diagnostics: &diagnostics))
        let data = try Data(contentsOf: fixture.file("learning-v1.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var value = try XCTUnwrap(object["value"] as? [String: Any]); value["schemaVersion"] = 99
        object["value"] = value
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.file("learning-v1.json"))
        (state, diagnostics) = store.load()
        XCTAssertNil(state)
        XCTAssertEqual(diagnostics[.storeCorruptDiscarded], 3)
    }

    func testLearningResetRefusesStaleSaveAndIgnoresRestoredOldFile() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let writer = fixture.store()
        let model = PersonalTypingModel(); model.keep("hello")
        var diagnostics = KeyboardDiagnostics(); diagnostics.increment(.boundaries)
        XCTAssertTrue(writer.save(model: model.state, diagnostics: &diagnostics))
        let old = try Data(contentsOf: fixture.file("learning-v1.json"))
        let before = writer.currentEpochs
        XCTAssertTrue(fixture.store().requestLearningReset())
        XCTAssertEqual(writer.currentEpochs.learning, before.learning + 1)
        XCTAssertEqual(writer.currentEpochs.diagnostics, before.diagnostics)
        XCTAssertFalse(writer.save(model: model.state, diagnostics: &diagnostics))
        XCTAssertTrue(writer.resetObserved)
        XCTAssertEqual(diagnostics[.storeWriteFailed], 0)
        try old.write(to: fixture.file("learning-v1.json"))
        let (loaded, retained) = writer.load()
        XCTAssertNil(loaded)
        XCTAssertEqual(retained[.boundaries], 1)
        XCTAssertEqual(retained[.storeCorruptDiscarded], 0)
        XCTAssertFalse(writer.resetObserved)
        model.reset()
        XCTAssertTrue(writer.save(model: model.state, diagnostics: &diagnostics))
        XCTAssertEqual(fixture.store().load().0?.kept.count, 0)
    }

    func testDiagnosticsResetKeepsLearningAndRejectsStaleDiagnostics() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let writer = fixture.store()
        let model = PersonalTypingModel(); model.keep("hello")
        var diagnostics = KeyboardDiagnostics(); diagnostics.increment(.boundaries)
        XCTAssertTrue(writer.save(model: model.state, diagnostics: &diagnostics))
        let old = try Data(contentsOf: fixture.file("diagnostics-v1.json"))
        XCTAssertTrue(fixture.store().requestDiagnosticsReset())
        XCTAssertFalse(writer.save(model: model.state, diagnostics: &diagnostics))
        XCTAssertTrue(writer.resetObserved)
        try old.write(to: fixture.file("diagnostics-v1.json"))
        let (loaded, reset) = writer.load()
        XCTAssertEqual(loaded, model.state)
        XCTAssertEqual(reset[.boundaries], 0)
        XCTAssertEqual(reset[.storeCorruptDiscarded], 0)
    }

    func testRAMOnlyModeAndResetEpochs() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let store = KeyboardLearningStore(directory: nil, defaults: fixture.defaults)
        XCTAssertFalse(store.isPersistent)
        let model = PersonalTypingModel(); model.keep("hello")
        var diagnostics = KeyboardDiagnostics(); diagnostics.increment(.boundaries)
        XCTAssertTrue(store.save(model: model.state, diagnostics: &diagnostics))
        XCTAssertEqual(store.load().0, model.state)
        XCTAssertEqual(store.load().1, diagnostics)
        let resetter = KeyboardLearningStore(directory: nil, defaults: fixture.defaults)
        XCTAssertTrue(resetter.requestLearningReset())
        XCTAssertFalse(store.save(model: model.state, diagnostics: &diagnostics))
        XCTAssertTrue(store.resetObserved)
        XCTAssertNil(store.load().0)
        XCTAssertEqual(store.load().1[.boundaries], 1)
        XCTAssertTrue(resetter.requestDiagnosticsReset())
        XCTAssertEqual(store.load().1[.boundaries], 0)
        let snapshot = KeyboardLearningStore.readSnapshot(directory: nil, defaults: fixture.defaults)
        XCTAssertFalse(snapshot.isPersistent)
        XCTAssertNil(snapshot.learningFile.bytes)
        XCTAssertNil(snapshot.diagnosticsFile.modifiedAt)
    }

    func testWriteByteCeilingDropsOldLexiconEntries() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let model = PersonalTypingModel(now: { Date(timeIntervalSince1970: 1) })
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        for index in 0..<2000 {
            let suffix = String(alphabet[index / 676]) + String(alphabet[(index / 26) % 26]) + String(alphabet[index % 26])
            let word = String(repeating: "界", count: 29) + suffix
            model.keep(word); model.recordWord(word)
        }
        let before = model.summary
        var diagnostics = KeyboardDiagnostics()
        XCTAssertTrue(fixture.store().save(model: model.state, diagnostics: &diagnostics))
        let data = try Data(contentsOf: fixture.file("learning-v1.json"))
        XCTAssertLessThanOrEqual(data.count, KeyboardLearningStore.maximumLearningBytes)
        let loaded = try XCTUnwrap(fixture.store().load().0)
        XCTAssertNotNil(loaded.validated())
        XCTAssertLessThan(loaded.kept.count + loaded.counts.count, before.keptWords + before.countedWords)
    }

    func testWriteFailureAndInvalidStateAreReported() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let file = fixture.file("not-a-directory")
        try Data().write(to: file)
        let store = KeyboardLearningStore(directory: file, defaults: fixture.defaults)
        var diagnostics = KeyboardDiagnostics()
        XCTAssertFalse(store.save(model: .init(), diagnostics: &diagnostics))
        XCTAssertFalse(store.isPersistent)
        XCTAssertFalse(store.resetObserved)
        XCTAssertEqual(diagnostics[.storeWriteFailed], 1)
        var invalid = PersonalTypingModel.State(); invalid.schemaVersion = 2
        XCTAssertFalse(fixture.store().save(model: invalid, diagnostics: &diagnostics))
        XCTAssertEqual(diagnostics[.storeWriteFailed], 2)
    }

    func testLearningSettingDefaultsOnAndSharesKey() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let settings = TyprSettings(defaults: fixture.defaults)
        XCTAssertTrue(settings.personalLearning)
        settings.personalLearning = false
        XCTAssertEqual(fixture.defaults.object(forKey: "keyboard.personalLearning") as? Bool, false)
        XCTAssertFalse(TyprSettings(defaults: fixture.defaults).personalLearning)
    }
}
