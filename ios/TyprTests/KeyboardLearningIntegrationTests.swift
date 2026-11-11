import UIKit
import XCTest
@testable import Typr

@MainActor
final class KeyboardLearningIntegrationTests: XCTestCase {
    private final class Checker: TextChecking {
        var valid: Set<String>
        var answers: [String: [String]]
        init(valid: Set<String> = ["hello", "world", "the"], answers: [String: [String]] = [:]) {
            self.valid = valid
            self.answers = answers
        }
        func isWordValid(_ word: String) -> Bool { valid.contains(word) }
        func guesses(for word: String) -> [String] { answers[word] ?? [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    private func keyboard(session: KeyboardLearningSession? = nil,
                          checker: Checker? = nil) -> (FullKeyboardEngine, FixtureTextTarget) {
        let target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let ac = AutocorrectEngine(checker: checker ?? Checker(), learning: session, spatialDecoder: nil)
        let engine = FullKeyboardEngine(target: target, autocorrect: ac)
        engine.width = 393
        engine.clock = { 100 } // No accidental double-space conversion except when explicitly requested.
        engine.configureForField()
        return (engine, target)
    }

    private func tap(_ kind: KeyKind, _ engine: FullKeyboardEngine) {
        guard let key = engine.layout.key(kind) else { XCTFail("Missing synthetic key"); return }
        let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: 1, at: point)
        engine.touchEnded(id: 1, at: point)
    }

    private func type(_ text: String, _ engine: FullKeyboardEngine) {
        for letter in text { tap(letter == " " ? .space : .character(String(letter)), engine) }
    }

    func testValidLiteralSettlesOnlyWhenIntactAndNextLetterStarts() {
        let (engine, target) = keyboard()
        type("hello ", engine)
        let session = engine.autocorrect.learning
        XCTAssertEqual(target.text, "hello ")
        XCTAssertEqual(session.model.summary.acceptedLabels, 0)
        XCTAssertNil(session.model.lexicon.counts["hello"])
        type("w", engine)
        XCTAssertEqual(session.model.lexicon.counts["hello"], 1)
        XCTAssertEqual(session.model.summary.acceptedBySource["literalValid"], 5)
        engine.refreshSuggestions()
        XCTAssertEqual(session.model.lexicon.counts["hello"], 1)
    }

    func testNextBoundarySettlesAndReturnIsNotAnAutocorrectBoundary() {
        let (engine, target) = keyboard()
        let session = engine.autocorrect.learning
        type("hello ", engine)
        tap(.space, engine)
        XCTAssertEqual(session.model.lexicon.counts["hello"], 1)
        XCTAssertEqual(session.diagnostics[.boundaries], 1)
        type("world ", engine)
        tap(.returnKey, engine)
        XCTAssertEqual(target.text, "hello. world \n")
        XCTAssertEqual(session.model.lexicon.counts["world"], 1, "Return settles an intact previous word")
        // Return keeps its pre-learning behaviour: no decision, no pending word, no boundary count.
        type("the", engine)
        tap(.returnKey, engine)
        type("h", engine)
        XCTAssertNil(session.model.lexicon.counts["the"])
        XCTAssertEqual(session.diagnostics[.boundaries], 2)
    }

    func testAutomaticOutputNeverTeachesWithoutFeedback() {
        for (typed, checker, counter) in [
            ("teh", Checker(), KeyboardDiagnostics.Counter.autoRule),
            ("helo", Checker(answers: ["helo": ["hello"]]), .autoSpellingFallback)
        ] {
            let (engine, _) = keyboard(checker: checker)
            type(typed + " w", engine)
            let session = engine.autocorrect.learning
            XCTAssertEqual(session.diagnostics[counter], 1)
            XCTAssertEqual(session.model.summary.acceptedLabels, 0)
            XCTAssertTrue(session.model.lexicon.counts.isEmpty)
        }
    }

    func testUndoLearnsIdentityKeepsAndRejectsPairWithoutWordCount() {
        let (engine, target) = keyboard()
        type("teh ", engine)
        tap(.delete, engine)
        let session = engine.autocorrect.learning
        XCTAssertEqual(target.text, "teh")
        XCTAssertEqual(session.model.summary.acceptedBySource["undo"], 3)
        XCTAssertTrue(session.model.lexicon.isKept("teh"))
        XCTAssertTrue(session.model.lexicon.isRejected(typed: "teh", replacement: "the"))
        XCTAssertTrue(session.model.lexicon.counts.isEmpty)
        XCTAssertEqual(session.diagnostics[.undoRule], 1)
        tap(.space, engine)
        type("teh ", engine)
        XCTAssertEqual(target.text, "teh teh ")
        XCTAssertEqual(session.diagnostics[.autoRule], 1)
    }

    func testSpellingUndoHasSeparateCounter() {
        let (engine, _) = keyboard(checker: Checker(answers: ["helo": ["hello"]]))
        type("helo ", engine)
        tap(.delete, engine)
        XCTAssertEqual(engine.autocorrect.learning.diagnostics[.undoSpelling], 1)
        XCTAssertEqual(engine.autocorrect.learning.model.summary.acceptedBySource["undo"], 4)
    }

    func testKeepChipCapturesEvidenceBeforeInvalidation() {
        let (engine, target) = keyboard()
        type("helo", engine)
        guard let literal = engine.suggestions.first else { return XCTFail("No literal chip") }
        engine.acceptSuggestion(literal)
        let session = engine.autocorrect.learning
        XCTAssertEqual(target.text, "helo ")
        XCTAssertEqual(session.model.summary.acceptedBySource["keep"], 4)
        XCTAssertTrue(session.model.lexicon.isKept("helo"))
        XCTAssertEqual(session.model.lexicon.counts["helo"], 1)
        XCTAssertEqual(session.diagnostics[.keepChip], 1)
        XCTAssertNil(engine.autocorrect.touchInput.evidence(beforeInput: target.text))
    }

    func testManualAlternativeUsesOnlyUniqueAlignmentAndCompletionUsesNoTaps() {
        let (engine, _) = keyboard()
        type("helo", engine)
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary))
        let session = engine.autocorrect.learning
        // Repeated l's are ambiguous; h, e and o remain uniquely aligned.
        XCTAssertEqual(session.model.summary.acceptedBySource["manualPick"], 3)
        XCTAssertEqual(session.model.lexicon.counts["hello"], 1)
        XCTAssertEqual(session.diagnostics[.manualAlternativePick], 1)
        type("wor", engine)
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "world", replacement: "world", kind: .secondary,
                                                   isCompletion: true))
        XCTAssertEqual(session.model.summary.acceptedBySource["manualPick"], 3)
        XCTAssertEqual(session.model.lexicon.counts["world"], 1)
        XCTAssertEqual(session.diagnostics[.manualCompletionPick], 1)
    }

    func testManualAlignmentDropsDistantSubstitutionAndCountsRejection() {
        let (engine, _) = keyboard()
        type("pello", engine)
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary))
        let session = engine.autocorrect.learning
        XCTAssertEqual(session.model.summary.acceptedBySource["manualPick"], 4)
        XCTAssertEqual(session.model.summary.rejectedByReason["outlier"], 1)
        XCTAssertEqual(session.model.lexicon.counts["hello"], 1)
    }

    func testRejectedDeterministicPairIsNotRetriedWithoutKeep() {
        let (engine, _) = keyboard()
        engine.autocorrect.learning.rejectCorrection(typed: "teh", replacement: "the")
        XCTAssertFalse(engine.autocorrect.learning.model.lexicon.isKept("teh"))
        XCTAssertNil(engine.autocorrect.replacementOnSpace(beforeInput: "teh", field: .text,
                                                          autocorrectionType: .default))
        XCTAssertEqual(engine.autocorrect.learning.diagnostics[.refusedProtected], 1)
    }

    func testSwitchChangeDiscardsAnUnsettledLiteral() throws {
        let name = "KeyboardLearning-toggle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = KeyboardLearningSession(defaults: defaults)
        let (engine, _) = keyboard(session: session)
        type("hello ", engine)
        defaults.set(false, forKey: "keyboard.personalLearning")
        engine.autocorrect.syncLearning()
        defaults.set(true, forKey: "keyboard.personalLearning")
        engine.autocorrect.syncLearning()
        type("w", engine)
        XCTAssertEqual(session.model.summary.acceptedLabels, 0)
        XCTAssertTrue(session.model.lexicon.counts.isEmpty)
    }

    func testDeletedBackExternalSelectionFieldDismissalAndLayoutDiscardPending() {
        for invalidate in 0..<7 {
            let (engine, target) = keyboard()
            type("hello ", engine)
            switch invalidate {
            case 0: tap(.delete, engine) // Delete the separator, then retype it: no delayed trust.
                tap(.space, engine)
            case 1: target.insertText("x "); engine.textDidChange()
            case 2: target.adjustTextPosition(byCharacterOffset: -1); engine.discardTouchEvidence()
            case 3: engine.configureForField()
            case 4: engine.cancelAllTouches()
            case 5: engine.width = 440
            default: target.insertText("x ") // Even a host that omits its callback fails the suffix check.
            }
            type("w", engine)
            XCTAssertEqual(engine.autocorrect.learning.model.summary.acceptedLabels, 0, "case \(invalidate)")
            XCTAssertTrue(engine.autocorrect.learning.model.lexicon.counts.isEmpty, "case \(invalidate)")
        }
    }

    func testAccentSlideAndMissingEvidenceNeverSupplyLabels() {
        for gesture in 0..<2 {
            let (engine, _) = keyboard()
            guard let a = engine.layout.key(.character("a")),
                  let s = engine.layout.key(.character("s")) else { return XCTFail("Missing keys") }
            let start = CGPoint(x: a.frame.midX, y: a.frame.midY)
            engine.touchBegan(id: 1, at: start)
            if gesture == 0 {
                XCTAssertTrue(engine.openAccentMenuIfEligible(forTouch: 1))
                engine.touchEnded(id: 1, at: start)
            } else {
                let end = CGPoint(x: s.frame.midX, y: s.frame.midY)
                engine.touchMoved(id: 1, to: end)
                engine.touchEnded(id: 1, at: end)
            }
            type("he", engine)
            engine.acceptSuggestion(KeyboardSuggestion(displayText: "hello", replacement: "hello", kind: .secondary))
            XCTAssertEqual(engine.autocorrect.learning.model.summary.acceptedLabels, 0)
        }
    }

    func testLearningOffStillProtectsExplicitKeepsAndCountsDiagnostics() {
        let name = "KeyboardLearning-off-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return XCTFail("No defaults") }
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "keyboard.personalLearning")
        let session = KeyboardLearningSession(defaults: defaults)
        let (engine, _) = keyboard(session: session)
        type("hello w", engine)
        XCTAssertEqual(session.model.summary.acceptedLabels, 0)
        XCTAssertTrue(session.model.lexicon.counts.isEmpty)
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "w", replacement: "w", kind: .keepLiteral))
        type("teh", engine)
        engine.acceptSuggestion(KeyboardSuggestion(displayText: "teh", replacement: "teh", kind: .keepLiteral))
        XCTAssertTrue(session.model.lexicon.isKept("teh"))
        XCTAssertEqual(session.diagnostics[.keepChip], 2)
        XCTAssertEqual(session.diagnostics[.boundaries], 1)
        XCTAssertEqual(session.model.summary.acceptedLabels, 0)
        XCTAssertNil(engine.autocorrect.replacementOnSpace(beforeInput: "teh", field: .text,
                                                          autocorrectionType: .default))
    }

    func testMissingResourceFallsBackAndBoundaryCountersAreNotSuggestionCounters() {
        let (engine, target) = keyboard(checker: Checker(answers: ["helo": ["hello"]]))
        type("helo", engine)
        for _ in 0..<10 { engine.refreshSuggestions() }
        let session = engine.autocorrect.learning
        XCTAssertEqual(session.diagnostics[.boundaries], 0)
        XCTAssertEqual(session.diagnostics.boundaryMs.reduce(0, +), 0)
        tap(.space, engine)
        XCTAssertEqual(target.text, "hello ")
        XCTAssertEqual(session.diagnostics[.boundaries], 1)
        XCTAssertEqual(session.diagnostics[.evidenceComplete], 1)
        XCTAssertEqual(session.diagnostics[.autoSpellingFallback], 1)
        XCTAssertEqual(session.diagnostics[.refusedMissingResource], 1)
        XCTAssertEqual(session.diagnostics.boundaryMs.reduce(0, +), 1)
        XCTAssertEqual(session.diagnostics[.suggestionDecodes], 0, "No decoder was installed")
    }

    func testMissingEvidenceReasonsAndPlainBoundaryDecisionAreCountedOnce() {
        let (engine, _) = keyboard()
        for token in ["hello", "hi", "für"] {
            XCTAssertNil(engine.autocorrect.replacementOnSpace(beforeInput: token, field: .text,
                                                              autocorrectionType: .default))
        }
        let diagnostics = engine.autocorrect.learning.diagnostics
        XCTAssertEqual(diagnostics[.boundaries], 3)
        XCTAssertEqual(diagnostics[.evidenceMissing], 1)
        XCTAssertEqual(diagnostics[.evidenceComplete] + diagnostics[.evidenceMissing]
            + diagnostics[.evidenceLengthOutOfRange] + diagnostics[.evidenceUnsupported], diagnostics[.boundaries])
        XCTAssertEqual(diagnostics[.evidenceLengthOutOfRange], 1)
        XCTAssertEqual(diagnostics[.evidenceUnsupported], 1)
        XCTAssertEqual(diagnostics[.unchanged], 3)
        XCTAssertEqual(diagnostics.boundaryMs.reduce(0, +), 3)
    }

    func testSessionRemovesLegacyKeyAndPersistsOnlyAggregatesOnFlush() throws {
        let name = "KeyboardLearning-session-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        defaults.set(Data("obsolete".utf8), forKey: "keyboard.learnedWords")
        let store = KeyboardLearningStore(directory: directory, defaults: defaults)
        let session = KeyboardLearningSession(store: store, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "keyboard.learnedWords"))
        let (engine, _) = keyboard(session: session)
        type("hello", engine)
        engine.acceptSuggestion(try XCTUnwrap(engine.suggestions.first))
        XCTAssertNil(KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults).learningFile.bytes,
                     "No immediate save before the debounce")
        session.flush()
        let loaded = KeyboardLearningSession(store: KeyboardLearningStore(directory: directory, defaults: defaults),
                                             defaults: defaults)
        XCTAssertTrue(loaded.model.lexicon.isKept("hello"))
        XCTAssertEqual(loaded.model.lexicon.counts["hello"], 1)
        XCTAssertEqual(loaded.model.summary.acceptedLabels, 5)
        XCTAssertEqual(loaded.diagnostics[.keepChip], 1)
    }

    func testDashboardReadsSessionSavesAndIndependentResetsReachLiveKeyboard() throws {
        let name = "KeyboardLearning-dashboard-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = KeyboardLearningSession(store: KeyboardLearningStore(directory: directory, defaults: defaults),
                                              defaults: defaults)
        let (engine, _) = keyboard(session: session)
        type("hello", engine)
        engine.acceptSuggestion(try XCTUnwrap(engine.suggestions.first))
        session.flush()

        let dashboard = KeyboardDiagnosticsModel(directory: directory, defaults: defaults)
        XCTAssertEqual(dashboard.snapshot.model.keptWords, 1)
        XCTAssertEqual(dashboard.snapshot.model.acceptedBySource["keep"], 5)
        XCTAssertEqual(dashboard.snapshot.diagnostics[.keepChip], 1)
        XCTAssertEqual(dashboard.snapshot.diagnostics[.wordsCounted], 1)
        XCTAssertNotNil(dashboard.snapshot.learningFile.bytes)
        XCTAssertNotNil(dashboard.snapshot.diagnosticsFile.bytes)

        dashboard.resetStatistics()
        XCTAssertNil(dashboard.resetProblem)
        engine.autocorrect.syncLearning()
        XCTAssertEqual(session.diagnostics[.keepChip], 0)
        XCTAssertTrue(session.model.lexicon.isKept("hello"))
        session.flush()
        dashboard.refresh()
        XCTAssertEqual(dashboard.snapshot.diagnostics[.keepChip], 0)
        XCTAssertEqual(dashboard.snapshot.model.keptWords, 1)

        type("world ", engine)
        XCTAssertNotNil(engine.autocorrect.pendingFeedback)
        dashboard.resetLearning()
        XCTAssertNil(dashboard.resetProblem)
        engine.autocorrect.syncLearning()
        XCTAssertNil(engine.autocorrect.pendingFeedback)
        XCTAssertTrue(session.model.lexicon.kept.isEmpty)
        XCTAssertEqual(session.diagnostics[.boundaries], 1)
        session.flush()
        dashboard.refresh()
        XCTAssertEqual(dashboard.snapshot.model.keptWords, 0)
        XCTAssertEqual(dashboard.snapshot.diagnostics[.boundaries], 1)
    }

    func testPermissionRevocationCancelsPersistenceButKeepsRAMProtection() throws {
        let name = "KeyboardLearning-permission-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fullAccess = true
        let session = KeyboardLearningSession(store: KeyboardLearningStore(directory: directory, defaults: defaults),
            defaults: defaults, allowsPersistence: { fullAccess })
        session.keep("hello")
        fullAccess = false
        session.flush()
        XCTAssertFalse(session.isPersistent)
        XCTAssertTrue(session.model.lexicon.isKept("hello"))
        XCTAssertNil(KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults).learningFile.bytes)
        defaults.set(1, forKey: KeyboardLearningStore.learningResetKey)
        session.refresh()
        XCTAssertFalse(session.model.lexicon.isKept("hello"), "RAM sessions also honor resets")
    }

    func testDiagnosticsResetDiscardsPendingFeedbackButPreservesLearning() throws {
        let name = "KeyboardLearning-statistics-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = KeyboardLearningSession(defaults: defaults)
        let store = KeyboardLearningStore(directory: nil, defaults: defaults)
        let (engine, _) = keyboard(session: session)
        session.keep("world")
        type("hello ", engine)
        XCTAssertNotNil(engine.autocorrect.pendingFeedback)
        XCTAssertTrue(store.requestDiagnosticsReset())
        engine.autocorrect.syncLearning()
        XCTAssertNil(engine.autocorrect.pendingFeedback)
        XCTAssertTrue(session.model.lexicon.isKept("world"))
        type("w", engine)
        XCTAssertEqual(session.model.summary.acceptedLabels, 0)
        XCTAssertEqual(session.diagnostics[.boundaries], 0)
    }

    func testResetEpochIsCheckedBeforeSaveAndRefreshDiscardsPending() throws {
        let name = "KeyboardLearning-reset-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = KeyboardLearningStore(directory: nil, defaults: defaults)
        let session = KeyboardLearningSession(store: store, defaults: defaults)
        let (engine, _) = keyboard(session: session)
        type("hello ", engine)
        session.keep("world")
        XCTAssertTrue(store.requestLearningReset())
        session.flush()
        type("w", engine)
        XCTAssertFalse(session.model.lexicon.isKept("world"))
        XCTAssertTrue(session.model.lexicon.counts.isEmpty)
        XCTAssertEqual(session.model.summary.acceptedLabels, 0)
        XCTAssertEqual(session.diagnostics[.boundaries], 1, "Learning reset does not reset diagnostics")
        XCTAssertTrue(store.requestDiagnosticsReset())
        session.refresh()
        XCTAssertEqual(session.diagnostics[.boundaries], 0)
    }
}
