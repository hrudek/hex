import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import HEX

@MainActor
final class DictationKeyboardFeedbackTests: XCTestCase {
    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "keyboard.feedback.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: HexPlusSettings
        let bridge: DictationFeedbackBridge
        let store: DictationLogStore
        init() {
            defaults = UserDefaults(suiteName: suite)!
            settings = HexPlusSettings(defaults: defaults)
            settings.dictationLog = true; settings.dictationFeedbackStrip = true
            bridge = DictationFeedbackBridge(defaults: defaults, directory: root.appendingPathComponent("queue"))
            store = DictationLogStore(storage: DictationLogStorage(url: root.appendingPathComponent("archive/legacy.json")),
                settings: settings, feedbackBridge: bridge)
        }
        func ready() async throws { try await LogTestEnvironment.waitUntilLoaded(store) }
        func offer() -> DictationFeedbackOffer {
            var context = DictationLogContext(); context.keyboardJob = true
            let recording = store.begin(token: store.token(), context: context)!
            recording.finish(text: "Synthetic result.", beforeSpelling: "Synthetic result.")
            return store.makeKeyboardFeedbackOffer(recording: recording, jobID: UUID().uuidString,
                resultID: UUID().uuidString, expiresAt: Date().addingTimeInterval(600))!
        }
        func enqueue(_ event: DictationFeedbackEvent) async -> Bool {
            await withCheckedContinuation { c in bridge.enqueue(event) { c.resume(returning: $0) } }
        }
        func pending() async -> [DictationFeedbackEvent] {
            await withCheckedContinuation { c in bridge.pending { events, _ in c.resume(returning: events) } }
        }
        func drain() async throws {
            for _ in 0..<30 {
                store.drainKeyboardFeedback(force: true)
                await store.storage.flush(); await bridge.flush()
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        func diskEntry(_ id: UUID) throws -> DictationLogEntry {
            try JSONDecoder().decode(DictationLogEntry.self, from: Data(contentsOf: store.storage.root
                .appendingPathComponent("entries/\(id.uuidString).json")))
        }
        func dispose() async {
            await store.storage.flush(); await bridge.flush()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
    private func event(_ offer: DictationFeedbackOffer, rating: String = "bad", issues: [String]? = nil,
                       id: UUID = UUID(), date: Date = Date()) -> DictationFeedbackEvent {
        .init(eventID: id, offer: offer, rating: rating, issues: issues, createdAt: date)
    }

    func testDefaultOnAndFreshInsertedExactMatchingOnly() {
        let suite = "feedback.defaults.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(HexPlusSettings(defaults: defaults).dictationFeedbackStrip)
        let offer = DictationFeedbackOffer(resultID: UUID().uuidString, jobID: UUID().uuidString,
            entryID: UUID(), archiveID: UUID(), generation: UUID(), expiresAt: Date().addingTimeInterval(600))
        let permission = DictationFeedbackPermission(archiveID: offer.archiveID, generation: offer.generation, enabled: true)
        XCTAssertNotNil(DictationFeedbackPresentation.inserted(offer: offer, resultID: offer.resultID,
            ownedJobs: [offer.jobID], permission: permission, now: Date()))
        XCTAssertNil(DictationFeedbackPresentation.inserted(offer: nil, resultID: offer.resultID,
            ownedJobs: [offer.jobID], permission: permission, now: Date()))
        XCTAssertNil(DictationFeedbackPresentation.inserted(offer: offer, resultID: "previous-result",
            ownedJobs: [offer.jobID], permission: permission, now: Date()))
        XCTAssertNil(DictationFeedbackPresentation.inserted(offer: offer, resultID: offer.resultID,
            ownedJobs: [], permission: permission, now: Date()))
        XCTAssertNil(DictationFeedbackPresentation.inserted(offer: offer, resultID: offer.resultID,
            ownedJobs: [offer.jobID], permission: nil, now: Date()))
        XCTAssertNil(DictationFeedbackPresentation.inserted(offer: offer, resultID: offer.resultID,
            ownedJobs: [offer.jobID], permission: permission, now: offer.expiresAt.addingTimeInterval(1)))
    }
    func testQueueRoundTripCategoryWholeSetAndReferenceOwnership() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer()
        let first = event(offer, issues: ["misheard"])
        let second = event(offer, issues: ["misheard", "too_slow"], date: first.createdAt.addingTimeInterval(0.001))
        let queuedFirst = await f.enqueue(first), queuedSecond = await f.enqueue(second)
        XCTAssertTrue(queuedFirst && queuedSecond)
        f.store.saveFeedback(for: offer.entryID, expectedText: "Human reference.", note: "Synthetic note.")
        try await f.drain()
        XCTAssertEqual(try f.diskEntry(offer.entryID).issues, ["misheard", "too_slow"])
        XCTAssertEqual(try f.diskEntry(offer.entryID).expectedText?.text, "Human reference.")
        XCTAssertEqual(try f.diskEntry(offer.entryID).feedbackNote?.text, "Synthetic note.")
        let pending = await f.pending(); XCTAssertTrue(pending.isEmpty)
        await f.dispose()
    }
    /// The inline "What I said" editor saves only the reference and keeps the separate note.
    func testInlineReferenceSaveKeepsNote() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer()
        f.store.saveFeedback(for: offer.entryID, expectedText: "First.", note: "Keep me.")
        f.store.saveFeedback(for: offer.entryID, expectedText: "What I actually said.", note: nil)
        XCTAssertEqual(f.store.entry(offer.entryID)?.expectedText?.text, "What I actually said.")
        XCTAssertEqual(f.store.entry(offer.entryID)?.feedbackNote?.text, "Keep me.")
        f.store.saveFeedback(for: offer.entryID, expectedText: "", note: nil)
        XCTAssertNil(f.store.entry(offer.entryID)?.expectedText)
        XCTAssertEqual(f.store.entry(offer.entryID)?.feedbackNote?.text, "Keep me.")
        await f.store.storage.flush()
        XCTAssertEqual(try f.diskEntry(offer.entryID).feedbackNote?.text, "Keep me.")
        await f.dispose()
    }
    func testSameTimestampTotalOrderAndAppEditsResolveByDefinedOrder() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer(), time = Date()
        let lower = event(offer, rating: "good", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: time)
        let upper = event(offer, issues: ["other"], id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: time)
        let a = await f.enqueue(upper), b = await f.enqueue(lower); XCTAssertTrue(a && b)
        try await f.drain()
        XCTAssertEqual(try f.diskEntry(offer.entryID).ratingOrder, upper.order)
        f.store.rate(offer.entryID, rating: "good", order: .init(modifiedAt: time.addingTimeInterval(1), origin: "app", eventID: UUID().uuidString))
        let duplicate = await f.enqueue(upper); XCTAssertTrue(duplicate)
        try await f.drain()
        XCTAssertEqual(try f.diskEntry(offer.entryID).rating, "good")
        await f.dispose()
    }
    func testCrashAfterDurableWriteBeforeQueueRemovalIsIdempotent() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer(), queued = event(offer)
        let success = await f.enqueue(queued); XCTAssertTrue(success)
        f.store.rate(offer.entryID, rating: queued.rating, order: queued.order)
        await f.store.storage.flush()
        let revision = try f.diskEntry(offer.entryID).revision
        let reloaded = DictationLogStore(storage: DictationLogStorage(url: f.store.storage.url), settings: f.settings, feedbackBridge: f.bridge)
        try await LogTestEnvironment.waitUntilLoaded(reloaded)
        for _ in 0..<30 {
            reloaded.drainKeyboardFeedback(force: true)
            await reloaded.storage.flush(); await f.bridge.flush(); try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(try f.diskEntry(offer.entryID).revision, revision)
        let pending = await f.pending(); XCTAssertTrue(pending.isEmpty)
        await f.dispose()
    }
    func testSourceWriteFailureKeepsEventUntilDurableRetry() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer()
        await f.store.storage.flush()
        let directory = f.store.storage.root.appendingPathComponent("entries")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let queued = await f.enqueue(event(offer, issues: ["misheard"])); XCTAssertTrue(queued)
        try await f.drain()
        let pending = await f.pending(); XCTAssertEqual(pending.count, 1)
        XCTAssertNil(try f.diskEntry(offer.entryID).rating)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        f.store.retry(); try await f.drain()
        XCTAssertEqual(try f.diskEntry(offer.entryID).rating, "bad")
        let remaining = await f.pending(); XCTAssertTrue(remaining.isEmpty)
        await f.dispose()
    }
    func testOffClearDeleteAndToggleCannotAttachOldOffers() async throws {
        let f = Fixture(); try await f.ready(); let old = f.offer()
        f.store.setEnabled(false)
        let offQueued = await f.enqueue(event(old)); XCTAssertFalse(offQueued)
        f.store.setEnabled(true)
        let onQueued = await f.enqueue(event(old)); XCTAssertFalse(onQueued)
        let current = f.offer(); f.store.delete(current.entryID)
        let deletedQueued = await f.enqueue(event(current)); XCTAssertTrue(deletedQueued)
        try await f.drain()
        XCTAssertFalse(f.store.metadata.contains { $0.id == current.entryID })
        f.store.clear(); await f.store.storage.flush(); try await Task.sleep(for: .milliseconds(20))
        let clearQueued = await f.enqueue(event(current)); XCTAssertFalse(clearQueued)
        f.settings.dictationFeedbackStrip = false; f.store.feedbackSettingsChanged()
        let disabledQueued = await f.enqueue(event(old))
        XCTAssertFalse(disabledQueued)
        await f.dispose()
    }
    func testLoadingOfferDoesNotRevokePreviousSessionQueue() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer()
        await f.store.storage.flush()
        let queued = await f.enqueue(event(offer)); XCTAssertTrue(queued)
        let permission = f.bridge.permission
        let reloaded = DictationLogStore(storage: DictationLogStorage(url: f.store.storage.url), settings: f.settings, feedbackBridge: f.bridge)
        XCTAssertTrue(reloaded.isLoading)
        var context = DictationLogContext(); context.keyboardJob = true
        let recording = reloaded.begin(token: reloaded.token(), context: context)!
        recording.finish(text: "Synthetic cold result.", beforeSpelling: "Synthetic cold result.")
        XCTAssertNil(reloaded.makeKeyboardFeedbackOffer(recording: recording, jobID: UUID().uuidString,
            resultID: UUID().uuidString, expiresAt: Date().addingTimeInterval(600)))
        XCTAssertEqual(f.bridge.permission, permission)
        try await LogTestEnvironment.waitUntilLoaded(reloaded)
        for _ in 0..<30 {
            reloaded.drainKeyboardFeedback(force: true)
            await reloaded.storage.flush(); await f.bridge.flush(); try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(try f.diskEntry(offer.entryID).rating, "bad")
        XCTAssertEqual(f.bridge.permission, permission)
        await f.dispose()
    }

    func testUnloadedOldEntryCanReceiveItsExactQueuedFeedback() async throws {
        let f = Fixture(); try await f.ready()
        var offer: DictationFeedbackOffer? = f.offer()
        let original = offer!
        for _ in 0..<60 {
            let rec = f.store.begin(token: f.store.token(), context: .init())!
            rec.finish(text: "Other synthetic result.", beforeSpelling: "Other synthetic result.")
        }
        await f.store.storage.flush(); try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(f.store.entry(original.entryID))
        let queued = await f.enqueue(event(original, issues: ["too_slow"])); XCTAssertTrue(queued)
        offer = nil
        try await f.drain()
        XCTAssertEqual(try f.diskEntry(original.entryID).rating, "bad")
        XCTAssertEqual(try f.diskEntry(original.entryID).issues, ["too_slow"])
        await f.dispose()
    }

    #if canImport(UIKit)
    private func visibleButtons(_ root: UIView) -> [UIButton] {
        guard !root.isHidden, root.alpha > 0 else { return [] }
        return (root as? UIButton).map { [$0] } ?? root.subviews.flatMap(visibleButtons)
    }

    private func pumpMainRunLoop() {
        // FullKeyboardView observes the model with `receive(on: RunLoop.main)`.
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testFullFeedbackProblemActionsInitiallyVisibleInBothAppearances() {
        for dark in [false, true] {
            let strip = KeyboardStripView(frame: CGRect(x: 0, y: 0, width: 393, height: 33))
            strip.palette = FullKeyboardPalette(isDark: dark)
            strip.updateFeedback(.snapshotFixture(problem: true), onRating: nil, onDismiss: {})
            strip.update(suggestions: [], showsUndo: true, statusText: nil)
            strip.layoutIfNeeded()
            let buttons = visibleButtons(strip)
            for label in ["Undo dictation", "Good", "Problem", HexPlusFeedbackBar.openAccessibilityLabel,
                          "Dismiss dictation feedback"] {
                guard let button = buttons.first(where: { $0.accessibilityLabel == label }) else {
                    XCTFail("\(label) not visible (dark: \(dark))"); continue
                }
                let rect = button.convert(button.bounds, to: strip)
                XCTAssertGreaterThanOrEqual(rect.minX, 0, label)
                XCTAssertLessThanOrEqual(rect.maxX, strip.bounds.maxX, label)
                XCTAssertGreaterThanOrEqual(rect.width, 44, label)
                XCTAssertGreaterThan(rect.height, 0, label)
            }
            // Categories moved into the app: the keyboard no longer lists them.
            XCTAssertFalse(buttons.contains { $0.accessibilityLabel == "Misheard" })
        }
    }

    /// On a device the full keyboard is mounted first and the feedback arrives with the inserted
    /// result. The bar must appear and be laid out then, not only when present at construction.
    func testFullKeyboardShowsFeedbackThatArrivesAfterMount() {
        let model = KeyboardViewModel()
        model.configureFixture(snapshot: .offline, now: 10_000)
        let view = FullKeyboardView(model: model, target: FixtureTextTarget(text: "Host text"))
        view.frame = CGRect(x: 0, y: 0, width: 393, height: KeyboardLayout.height(for: .portrait))
        view.layoutIfNeeded()
        pumpMainRunLoop()
        XCTAssertFalse(visibleButtons(view).contains { $0.accessibilityLabel == "Good" })

        view.didInsertDictation("dictated", keepUndoFor: 180)
        model.feedback = .snapshotFixture()
        pumpMainRunLoop()
        view.layoutIfNeeded()
        for label in ["Good", "Problem", "Dismiss dictation feedback"] {
            guard let button = visibleButtons(view).first(where: { $0.accessibilityLabel == label }) else {
                XCTFail("\(label) not visible after a late feedback offer"); continue
            }
            let rect = button.convert(button.bounds, to: view)
            XCTAssertTrue(view.bounds.contains(rect), label)
            XCTAssertGreaterThanOrEqual(rect.width, 44, label)
        }

        model.feedback?.rating = "bad"
        pumpMainRunLoop()
        view.layoutIfNeeded()
        var opened: URL?
        model.onOpenURL = { opened = $0 }
        let open = visibleButtons(view).first { $0.accessibilityLabel == HexPlusFeedbackBar.openAccessibilityLabel }
        XCTAssertNotNil(open)
        open?.sendActions(for: .touchUpInside)
        let entryID = DictationFeedbackPresentation.snapshotFixture().offer.entryID
        XCTAssertEqual(opened, HexPlusFeedbackLink.url(entryID: entryID))
        XCTAssertNil(model.feedback)
    }

    func testFeedbackLinkRoundTripAndRouting() {
        let id = UUID()
        let url = HexPlusFeedbackLink.url(entryID: id)
        XCTAssertEqual(HexPlusFeedbackLink.entryID(from: url), id)
        XCTAssertNil(KeyboardLaunchRequest(url: url), "must never start a dictation session")
        XCTAssertNil(HexPlusFeedbackLink.entryID(from: KeyboardLaunchRequest.setup.url))
        XCTAssertNil(HexPlusFeedbackLink.entryID(from: URL(string: "hex-dictation://hexplus/feedback?entry=nope")!))
        let router = HexPlusFeedbackRouter()
        XCTAssertFalse(router.handle(KeyboardLaunchRequest.setup.url))
        XCTAssertNil(router.requestedEntry)
        XCTAssertTrue(router.handle(url))
        XCTAssertEqual(router.consume(), id)
        XCTAssertNil(router.requestedEntry)
    }

    func testFullKeyboardFeedbackKeepsUndoDoesNotEditHostAndTypingDismisses() {
        let target = FixtureTextTarget(text: "Original host text")
        let model = KeyboardViewModel()
        model.configureFixture(snapshot: .offline, now: 10_000)
        model.feedback = .snapshotFixture()
        var received: String?
        model.onFeedbackRating = { rating, _ in received = rating }
        let view = FullKeyboardView(model: model, target: target)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: KeyboardLayout.height(for: .portrait))
        view.didInsertDictation("dictated", keepUndoFor: 180)
        view.layoutIfNeeded()
        let visible = visibleButtons(view)
        XCTAssertTrue(visible.contains { $0.accessibilityLabel == "Undo dictation" })
        let good = visible.first { $0.accessibilityLabel == "Good" }
        XCTAssertNotNil(good)
        good?.sendActions(for: .touchUpInside)
        XCTAssertEqual(received, "good")
        XCTAssertEqual(target.text, "Original host text")
        let key = view.engine.layout.key(.character("x"))!
        let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
        view.engine.touchBegan(id: 99, at: point); view.engine.touchEnded(id: 99, at: point)
        XCTAssertNil(model.feedback)
        XCTAssertTrue(target.text.contains("x"))
    }
    #endif

    func testTwoWritersCapAndMalformedExpiredEvents() async throws {
        let f = Fixture(); try await f.ready(); let offer = f.offer()
        let other = DictationFeedbackBridge(defaults: f.defaults, directory: f.root.appendingPathComponent("queue"))
        let events = (0..<101).map { _ in event(offer) }
        let count = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for (i, event) in events.enumerated() {
                let bridge = i.isMultiple(of: 2) ? f.bridge : other
                group.addTask { await withCheckedContinuation { c in bridge.enqueue(event) { c.resume(returning: $0) } } }
            }
            var count = 0; for await result in group { if result { count += 1 } }; return count
        }
        XCTAssertGreaterThan(count, 0); XCTAssertLessThanOrEqual(count, 100)
        // A contending writer may honestly report Not queued; explicit retries fill the remaining slots.
        for event in events { _ = await f.enqueue(event) }
        let pending = await f.pending(); XCTAssertEqual(pending.count, 100)
        let badFile = f.root.appendingPathComponent("queue/\(UUID().uuidString).json")
        try Data(repeating: 32, count: DictationFeedbackBridge.maximumEventBytes + 1).write(to: badFile)
        _ = await f.pending()
        XCTAssertFalse(FileManager.default.fileExists(atPath: badFile.path))
        let stale = event(offer, date: Date().addingTimeInterval(-31 * 24 * 60 * 60))
        let expired = await f.enqueue(stale); XCTAssertFalse(expired)
        await other.flush(); await f.dispose()
    }
}
