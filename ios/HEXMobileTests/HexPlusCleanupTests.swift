import XCTest
@testable import HEX

@MainActor
final class CleanupTestSession: CleanupSession {
    var prepareCount = 0
    var cleanCount = 0
    var cancelled = false
    var result = "Die Katze sitzt auf der Matte"
    var shouldThrow = false
    var failure: (any Error)?
    var suspend = false
    var gate: CheckedContinuation<String, Never>?
    var suspendPrewarm = false
    var prewarmGate: CheckedContinuation<Void, Never>?
    func prewarm() async {
        prepareCount += 1
        if suspendPrewarm { await withCheckedContinuation { prewarmGate = $0 } }
        cancelled = Task.isCancelled
    }
    func clean(_ text: String, style: DictationStyle) async throws -> String {
        cleanCount += 1
        if let failure { throw failure }
        if shouldThrow { throw CocoaError(.coderInvalidValue) }
        if suspend {
            let value = await withCheckedContinuation { gate = $0 }
            cancelled = Task.isCancelled
            return value
        }
        return result
    }
    func resume() { gate?.resume(returning: result); gate = nil }
}

@MainActor
struct CleanupTestCleaner: HexPlusTranscriptCleaning {
    var unavailableReason: String?
    let session: CleanupTestSession
    func makeSession() -> any CleanupSession { session }
}

@MainActor
struct CleanupTestLanguage: LanguageDetecting {
    var allowed = true
    func supports(_ text: String) -> Bool { allowed }
}

@MainActor
final class CleanupTestBackground: BackgroundTaskStarting {
    var expiration: (@MainActor () -> Void)?
    var invalid = false
    var expireInBegin = false
    var begins = 0
    var ends: [Int] = []
    func begin(expiration: @escaping @MainActor () -> Void) -> Int? {
        begins += 1
        self.expiration = expiration
        if expireInBegin { expiration() }
        return invalid ? nil : begins
    }
    func end(_ token: Int) { ends.append(token) }
}

@MainActor
final class CleanupTestSleeper {
    var gates: [CheckedContinuation<Void, Error>] = []
    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { gates.append($0) }
    }
    func fire() { let pending = gates; gates = []; for gate in pending { gate.resume() } }
}

@MainActor
final class HexPlusCleanupTests: XCTestCase {
    private let raw = "Die Katze sitzt auf der Mathe"

    private func drain() async { for _ in 0..<30 { await Task.yield() } }

    func testSettingsUseIsolatedDefaultsAndDefaultOn() {
        let name = "cleanup.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = HexPlusSettings(defaults: defaults)
        XCTAssertTrue(settings.aiCleanup)
        settings.aiCleanup = false
        XCTAssertFalse(HexPlusSettings(defaults: defaults).aiCleanup)
        XCTAssertEqual(defaults.object(forKey: "typr.aiCleanup") as? Bool, false)
    }

    func testSuccessThrowAndGuardFallback() async {
        for mode in 0..<3 {
            let session = CleanupTestSession()
            session.shouldThrow = mode == 1
            if mode == 2 { session.result = "Please transfer 950 Euro" }
            let bg = CleanupTestBackground(), clock = CleanupTestSleeper()
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: clock.sleep)
            let job = CleanupJob(session: session, background: bg)
            job.begin()
            let coordinator = CleanupCoordinator()
            let value = await coordinator.clean(raw, style: .polished, job: job, dependencies: deps)
            XCTAssertEqual(value, mode == 0 ? session.result : raw)
            XCTAssertNil(coordinator.reservedBy)
            job.finish(); job.finish()
            XCTAssertEqual(bg.ends, [1])
            clock.fire()
            await drain()
        }
    }

    func testDeadlineRetainsReservationUntilIgnoringModelCompletes() async {
        let session = CleanupTestSession(); session.suspend = true
        let bg = CleanupTestBackground(), clock = CleanupTestSleeper()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
            background: bg, isEnabled: { true }, sleep: clock.sleep)
        let coordinator = CleanupCoordinator()
        let a = CleanupJob(session: session, background: bg); a.begin()
        let task = Task { await coordinator.clean(raw, style: .polished, job: a, dependencies: deps) }
        await drain()
        clock.fire()
        let value = await task.value
        XCTAssertEqual(value, raw)
        XCTAssertEqual(coordinator.reservedBy, a.id)
        let b = CleanupJob(session: session, background: bg); b.begin()
        let skipped = await coordinator.clean(raw, style: .polished, job: b, dependencies: deps)
        XCTAssertEqual(skipped, raw)
        coordinator.cancel(b.id); coordinator.release(b.id)
        XCTAssertEqual(coordinator.reservedBy, a.id)
        session.resume(); await drain()
        XCTAssertTrue(session.cancelled)
        XCTAssertNil(coordinator.reservedBy)
        session.suspend = false
        let c = CleanupJob(session: session, background: bg); c.begin()
        let cleaned = await coordinator.clean(raw, style: .polished, job: c, dependencies: deps)
        XCTAssertEqual(cleaned, session.result)
        a.finish(); b.finish(); c.finish(); clock.fire(); await drain()
    }

    func testCancellationAndExpiryResolveExactlyOnce() async {
        for expire in [false, true] {
            let session = CleanupTestSession(); session.suspend = true
            let bg = CleanupTestBackground(), clock = CleanupTestSleeper()
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: clock.sleep)
            let job = CleanupJob(session: session, background: bg); job.begin()
            let coordinator = CleanupCoordinator()
            let task = Task { await coordinator.clean(raw, style: .polished, job: job, dependencies: deps) }
            await drain()
            if expire { bg.expiration?() } else { task.cancel() }
            let value = await task.value
            XCTAssertEqual(value, raw)
            session.resume(); await drain()
            XCTAssertTrue(session.cancelled)
            job.finish(); bg.expiration?(); job.finish()
            XCTAssertEqual(bg.ends, [1])
            clock.fire(); await drain()
        }
    }

    func testInvalidAndEarlyExpiredLeaseNeverStartModel() async {
        for mode in 0..<2 {
            let bg = CleanupTestBackground(); bg.invalid = mode == 0; bg.expireInBegin = mode == 1
            let session = CleanupTestSession()
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true })
            let job = CleanupJob(session: session, background: bg); job.begin()
            let coordinator = CleanupCoordinator()
            let value = await coordinator.clean(raw, style: .polished, job: job, dependencies: deps)
            XCTAssertEqual(value, raw)
            XCTAssertEqual(session.cleanCount, 0)
            job.finish(); job.finish()
            XCTAssertEqual(bg.ends, mode == 0 ? [] : [1])
        }
    }

    func testAdmissionAndPrewarmedThenBusySkip() async {
        let coordinator = CleanupCoordinator(), bg = CleanupTestBackground(), session = CleanupTestSession()
        let job = CleanupJob(session: session, background: bg)
        coordinator.prewarm(job)
        XCTAssertEqual(coordinator.reservedBy, job.id)
        XCTAssertFalse(coordinator.admit(UUID()))
        await drain()
        XCTAssertEqual(session.prepareCount, 1)
        let foreign = UUID()
        XCTAssertTrue(coordinator.admit(foreign))
        job.begin()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(), background: bg, isEnabled: { true })
        let value = await coordinator.clean(raw, style: .polished, job: job, dependencies: deps)
        XCTAssertEqual(value, raw)
        XCTAssertEqual(session.cleanCount, 0)
        coordinator.release(job.id)
        XCTAssertEqual(coordinator.reservedBy, foreign)
        coordinator.release(foreign); job.finish()
    }

    func testLateDeadlineCannotResolveFollowingJobAndResultRaceIsSingleResolution() async {
        let session = CleanupTestSession(), bg = CleanupTestBackground(), clock = CleanupTestSleeper()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
            background: bg, isEnabled: { true }, sleep: clock.sleep)
        let coordinator = CleanupCoordinator()
        let a = CleanupJob(session: session, background: bg); a.begin()
        session.suspend = true
        let firstTask = Task { await coordinator.clean(raw, style: .polished, job: a, dependencies: deps) }
        await drain()
        XCTAssertEqual(clock.gates.count, 1)
        session.resume()
        let first = await firstTask.value
        XCTAssertEqual(first, session.result)
        await drain()
        session.suspend = true
        let b = CleanupJob(session: session, background: bg); b.begin()
        let task = Task { await coordinator.clean(raw, style: .polished, job: b, dependencies: deps) }
        await drain()
        // Wake only A's cancelled sleeper; it must not cancel or resolve B.
        if !clock.gates.isEmpty { clock.gates.removeFirst().resume() }
        await drain()
        XCTAssertEqual(coordinator.reservedBy, b.id)
        XCTAssertNotNil(session.gate)
        // Result and deadline become runnable together. Either value is valid, never a double resume.
        session.resume(); clock.fire()
        let second = await task.value
        XCTAssertTrue(second == raw || second == session.result)
        await drain()
        XCTAssertNil(coordinator.reservedBy)
        a.finish(); b.finish()
        XCTAssertEqual(bg.ends, [1, 2])
    }

    func testPrewarmCancellationKeepsSlotUntilActualCompletion() async {
        let session = CleanupTestSession(), bg = CleanupTestBackground()
        session.suspendPrewarm = true
        let coordinator = CleanupCoordinator()
        let job = CleanupJob(session: session, background: bg)
        coordinator.prewarm(job)
        await drain()
        coordinator.cancel(job.id)
        XCTAssertEqual(coordinator.reservedBy, job.id)
        XCTAssertFalse(coordinator.admit(UUID()))
        session.prewarmGate?.resume(); session.prewarmGate = nil
        await drain()
        XCTAssertTrue(session.cancelled)
        XCTAssertNil(coordinator.reservedBy)
    }

    func testInputAndLanguageAdmissionSkipModel() async {
        let session = CleanupTestSession(), bg = CleanupTestBackground()
        for text in [String(repeating: "a", count: 1501), String(repeating: "word ", count: 251), raw] {
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(allowed: false),
                background: bg, isEnabled: { true })
            let job = CleanupJob(session: session, background: bg); job.begin()
            let coordinator = CleanupCoordinator()
            let value = await coordinator.clean(text, style: .polished, job: job, dependencies: deps)
            XCTAssertEqual(value, text)
            XCTAssertNil(coordinator.reservedBy)
            job.finish()
        }
        XCTAssertEqual(session.cleanCount, 0)
    }

    func testAlreadyCancelledBeforeRegistrationDoesNotStartModel() async {
        let session = CleanupTestSession(), bg = CleanupTestBackground()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(), background: bg, isEnabled: { true })
        let job = CleanupJob(session: session, background: bg); job.begin()
        let coordinator = CleanupCoordinator()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await coordinator.clean(raw, style: .polished, job: job, dependencies: deps)
        }
        let value = await task.value
        XCTAssertEqual(value, raw)
        XCTAssertEqual(session.cleanCount, 0)
        XCTAssertNil(coordinator.reservedBy)
        job.finish()
    }
}
