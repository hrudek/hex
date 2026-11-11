import Foundation
import XCTest
@testable import Typr

/// Older transaction tests inject explicit strip choices rather than waiting for real dictionary
/// output. Bind those fixture choices to the CURRENT field exactly as a freshly rendered chip is.
@MainActor
extension FullKeyboardEngine {
    func acceptOwnedFixtureSuggestion(_ suggestion: KeyboardSuggestion) {
        var owned = suggestion
        owned.ownership = suggestionOwnership
        acceptSuggestion(owned)
    }
}

@MainActor
final class KeyboardSuggestionWorkerTests: XCTestCase {
    private final class Checker: TextChecking {
        var calls = 0
        func isWordValid(_ word: String) -> Bool { calls += 1; return ["the", "hello"].contains(word) }
        func guesses(for word: String) -> [String] { calls += 1; return word == "helo" ? ["hello"] : [] }
        func completions(for prefix: String) -> [String] { calls += 1; return [] }
    }

    /// Explicit continuation gate, not sleeps: a job can stay blocked across edits/cancellation.
    private actor Gate {
        var requests: [KeyboardSuggestionWorker.Request] = []
        var continuation: CheckedContinuation<KeyboardSuggestionWorker.Result, Never>?
        func rank(_ request: KeyboardSuggestionWorker.Request) async -> KeyboardSuggestionWorker.Result {
            requests.append(request)
            return await withCheckedContinuation { continuation = $0 }
        }
        func count() -> Int { requests.count }
        func release(requestIndex: Int? = nil) {
            let request = requestIndex.map { requests[$0] } ?? requests.last
            guard let request, let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: .init(request: request, outcome: nil, seconds: 0))
        }
    }

    private func waitForJob(_ gate: Gate, count: Int = 1) async {
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while await gate.count() < count, ContinuousClock.now < limit { await Task.yield() }
        let actual = await gate.count()
        XCTAssertEqual(actual, count)
    }

    private func keyboard(worker: KeyboardSuggestionWorker? = nil,
                          session: KeyboardLearningSession? = nil) -> (FullKeyboardEngine, FixtureTextTarget, Checker) {
        let target = FixtureTextTarget()
        let checker = Checker()
        let engine = FullKeyboardEngine(target: target,
                                        autocorrect: AutocorrectEngine(checker: checker, learning: session, spatialDecoder: nil),
                                        suggestionWorker: worker)
        engine.width = 393
        engine.configureForField()
        return (engine, target, checker)
    }

    private func type(_ text: String, _ engine: FullKeyboardEngine) throws {
        for letter in text {
            let key = try XCTUnwrap(engine.layout.key(.character(String(letter))))
            let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
            engine.touchBegan(id: 1, at: point)
            engine.touchEnded(id: 1, at: point)
        }
    }

    func testInsertionNeverCallsCheckerAndReadyResultUsesSamePolicy() async throws {
        let (engine, target, checker) = keyboard()
        try type("teh", engine)
        XCTAssertEqual(checker.calls, 0, "No checker call on key insertion")
        XCTAssertEqual(target.text.lowercased(), "teh")
        await engine.waitForSuggestions()
        XCTAssertEqual(engine.suggestions.map(\.replacement), ["Teh", "The"])
        let choice = try XCTUnwrap(engine.suggestions.last)
        engine.acceptSuggestion(choice)
        XCTAssertEqual(target.text, "The ")
    }

    func testHeldChipKeepsTouchDownChoiceAndRejectsNewTokenOnRelease() async throws {
        let (engine, target, _) = keyboard()
        try type("teh", engine)
        var selection = KeyboardSuggestionSelection()
        let original = try XCTUnwrap(engine.suggestions.last)
        selection.begin(slot: 1, suggestions: engine.suggestions)
        await engine.waitForSuggestions()
        XCTAssertEqual(engine.suggestions.last?.replacement, "The")
        XCTAssertEqual(selection.finish(slot: 1), original, "Ranking during a hold must not change the chosen chip")
        selection.begin(slot: 1, suggestions: engine.suggestions)
        try type("x", engine)
        engine.acceptSuggestion(try XCTUnwrap(selection.finish(slot: 1)))
        XCTAssertEqual(target.text, "Tehx", "Held chip from an older token is refused on release")
        for slot in 0..<100 { selection.begin(slot: slot, suggestions: engine.suggestions) }
        XCTAssertLessThanOrEqual(selection.count, 3)
        selection.cancel(slot: 0)
        XCTAssertNil(selection.finish(slot: 0), "Cancelled touch must not pick the newer slot")
        XCTAssertNil(selection.finish(slot: 99))
        engine.cancelSuggestions()
    }

    func testOneRunningPlusOneLatestAndStaleCompletionCannotPublish() async throws {
        let gate = Gate()
        let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
        let (engine, target, _) = keyboard(worker: worker)
        try type("t", engine)
        await waitForJob(gate)
        let staleChip = try XCTUnwrap(engine.suggestions.first)
        try type("eh", engine)
        for _ in 0..<100 { engine.refreshSuggestions() }
        XCTAssertEqual(worker.queuedCount, 1)
        engine.acceptSuggestion(staleChip)
        XCTAssertEqual(target.text, "Teh", "Stale chip cannot edit or learn")
        XCTAssertTrue(engine.autocorrect.learning.protections.kept.isEmpty)
        await gate.release()
        await waitForJob(gate, count: 2)
        XCTAssertFalse(engine.suggestions.contains(where: \.willAutoReplace), "Old completion was dropped")
        await gate.release()
        await engine.waitForSuggestions()
        XCTAssertEqual(engine.suggestions.last?.replacement, "The")
        let total = await gate.count()
        XCTAssertEqual(total, 2, "Intermediate 101 requests were replaced, not enqueued")
    }

    func testConfigurationLearningAndEpochChangesDropInFlightResults() async throws {
        for mutation in 0..<5 {
            let gate = Gate()
            let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
            let (engine, target, _) = keyboard(worker: worker)
            try type("teh", engine)
            await waitForJob(gate)
            let staleChip = try XCTUnwrap(engine.suggestions.first)
            switch mutation {
            case 0: engine.autocorrect.englishEnabled = false
            case 1: engine.autocorrect.learning.keep("teh")
            case 2: engine.autocorrect.isEnabled = false
            case 3: engine.width = 430
            default:
                // Same text, different field lifetime must still fail ownership.
                engine.configureForField()
            }
            engine.acceptSuggestion(staleChip)
            XCTAssertEqual(target.text, "Teh")
            // Field/layout changes may have queued a new request; cancellation drops both.
            worker.cancel()
            await gate.release()
            await engine.waitForSuggestions()
            XCTAssertFalse(engine.suggestions.contains(where: \.willAutoReplace))
        }
    }

    func testOutOfOrderResultCannotFinishNewerRequest() async throws {
        let gate = Gate()
        let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
        let (engine, _, _) = keyboard(worker: worker)
        try type("t", engine)
        await waitForJob(gate)
        try type("eh", engine)
        await gate.release()
        await waitForJob(gate, count: 2)
        await gate.release(requestIndex: 0) // Deliver old result through newer callback.
        await engine.waitForSuggestions()
        XCTAssertFalse(engine.suggestions.contains(where: \.willAutoReplace))
        engine.refreshSuggestions()
        await waitForJob(gate, count: 3)
        await gate.release()
        await engine.waitForSuggestions()
        XCTAssertEqual(engine.suggestions.last?.replacement, "The")
    }

    func testLearningSwitchAndBothResetEpochsRejectOldJobAndChip() async throws {
        for mutation in 0..<3 {
            let name = "P1-epoch-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let session = KeyboardLearningSession(defaults: defaults)
            let store = KeyboardLearningStore(directory: nil, defaults: defaults)
            let gate = Gate()
            let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
            let (engine, target, _) = keyboard(worker: worker, session: session)
            try type("teh", engine)
            await waitForJob(gate)
            let chip = try XCTUnwrap(engine.suggestions.first)
            if mutation == 0 { defaults.set(false, forKey: "keyboard.personalLearning") }
            else if mutation == 1 { XCTAssertTrue(store.requestLearningReset()) }
            else { XCTAssertTrue(store.requestDiagnosticsReset()) }
            engine.autocorrect.syncLearning()
            engine.acceptSuggestion(chip)
            XCTAssertEqual(target.text, "Teh")
            XCTAssertTrue(session.protections.kept.isEmpty)
            await gate.release()
            await engine.waitForSuggestions()
            XCTAssertFalse(engine.suggestions.contains(where: \.willAutoReplace))
        }
    }

    func testResourceInstallationMidJobRejectsLoadingSnapshot() async throws {
        let source = SpatialWordDecoder(bundle: Bundle.main)
        let gate = Gate()
        let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
        let target = FixtureTextTarget()
        let ac = AutocorrectEngine(checker: Checker(), spatialDecoder: source)
        let engine = FullKeyboardEngine(target: target, autocorrect: ac, suggestionWorker: worker)
        engine.configureForField()
        try type("teh", engine)
        await waitForJob(gate)
        let chip = try XCTUnwrap(engine.suggestions.first)
        source.prepareResources()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while source.isResourceLoading, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(source.isResourceLoading)
        XCTAssertEqual(source.resourceRevision, 1)
        engine.acceptSuggestion(chip)
        XCTAssertEqual(target.text, "Teh")
        await gate.release()
        await engine.waitForSuggestions()
        XCTAssertFalse(engine.suggestions.contains(where: \.willAutoReplace))
    }

    func testCancelAndSuspensionNeverReadHiddenTargetOrPublishLate() async throws {
        let gate = Gate()
        let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
        let (engine, _, checker) = keyboard(worker: worker)
        try type("teh", engine)
        await waitForJob(gate)
        engine.suspendSuggestions()
        engine.refreshSuggestions()
        XCTAssertEqual(worker.queuedCount, 0)
        await gate.release()
        await engine.waitForSuggestions()
        XCTAssertTrue(engine.suggestions.isEmpty)
        XCTAssertEqual(checker.calls, 0)
        engine.configureForField()
        await waitForJob(gate, count: 2)
        await gate.release()
        await engine.waitForSuggestions()
        XCTAssertEqual(engine.suggestions.last?.replacement, "The")
    }

    func testBoundaryDoesNotWaitForWorkerAndRolloverKeepsOrder() async throws {
        let gate = Gate()
        let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
        let (engine, target, _) = keyboard(worker: worker)
        let t = try XCTUnwrap(engine.layout.key(.character("t"))).frame
        let e = try XCTUnwrap(engine.layout.key(.character("e"))).frame
        let h = try XCTUnwrap(engine.layout.key(.character("h"))).frame
        func point(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
        engine.touchBegan(id: 1, at: point(t))
        engine.touchBegan(id: 2, at: point(e)) // commits held t
        await waitForJob(gate)
        engine.touchBegan(id: 3, at: point(h)) // commits held e
        engine.touchEnded(id: 3, at: point(h))
        engine.touchEnded(id: 2, at: point(e))
        engine.touchEnded(id: 1, at: point(t))
        XCTAssertEqual(target.text, "Teh")
        XCTAssertEqual(engine.autocorrect.touchInput.evidence(beforeInput: target.text)?.text, "Teh")
        let start = ContinuousClock.now
        engine.typeSpaceFromTyprKey()
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        XCTAssertEqual(target.text, "The ", "Authoritative fallback does not await a blocked worker")
        await gate.release()
        await engine.waitForSuggestions()
        XCTAssertTrue(engine.suggestions.isEmpty)
        engine.deleteBackward()
        XCTAssertEqual(target.text, "Teh", "Immediate undo remains linked")
        engine.cancelSuggestions()
    }

    func testContextTokenAndUnicodeByteCapsDoNotQueueOversizedSnapshots() throws {
        let worker = KeyboardSuggestionWorker()
        let (engine, target, _) = keyboard(worker: worker)
        target.insertText(String(repeating: "word ", count: 100) + "teh")
        engine.textDidChange()
        XCTAssertLessThanOrEqual(engine.suggestionOwnership.context?.count ?? 0, 256)
        XCTAssertEqual(engine.suggestionOwnership.token, "teh")
        for _ in 0..<target.text.count { target.deleteBackward() }
        target.insertText(String(repeating: "a", count: 65))
        engine.textDidChange()
        XCTAssertTrue(engine.suggestions.isEmpty)
        XCTAssertEqual(worker.queuedCount, 0)
        for _ in 0..<65 { target.deleteBackward() }
        target.insertText("a" + String(repeating: "\u{0301}", count: 2_048))
        engine.textDidChange()
        XCTAssertNil(engine.suggestionOwnership.context, "A single grapheme must not defeat the UTF-8 byte cap")
        XCTAssertTrue(engine.suggestions.isEmpty)
        XCTAssertEqual(worker.queuedCount, 0)
        engine.cancelSuggestions()
    }

    func testContextAndFieldRevalidationAndUnownedChoicesAreRejected() async throws {
        let (engine, target, _) = keyboard()
        try type("teh", engine)
        await engine.waitForSuggestions()
        let chip = try XCTUnwrap(engine.suggestions.last)
        for _ in 0..<3 { target.deleteBackward() }
        target.insertText("other Teh") // host changed context without callback yet
        engine.acceptSuggestion(chip)
        XCTAssertEqual(target.text, "other Teh")
        for _ in 0..<9 { target.deleteBackward() }
        target.insertText("Teh")
        target.autocorrectionType = .no
        engine.acceptSuggestion(chip)
        XCTAssertEqual(target.text, "Teh")
        target.autocorrectionType = .default
        target.keyboardType = .URL
        engine.acceptSuggestion(chip)
        XCTAssertEqual(target.text, "Teh", "Unnotified field trait change must also refuse")
        target.keyboardType = .default
        engine.acceptSuggestion(.init(displayText: "the", replacement: "the", kind: .secondary))
        XCTAssertEqual(target.text, "Teh")
    }
}
