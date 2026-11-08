import XCTest
@testable import HEX

@MainActor
final class CleanupDiagnosticsTests: XCTestCase {
    private func drain() async { for _ in 0..<30 { await Task.yield() } }

    private func withDefaults(_ body: (UserDefaults) async -> Void) async {
        let name = "cleanup.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        await body(defaults)
        defaults.removePersistentDomain(forName: name)
    }

    func testSummariesKeepNoTextAndSkipOff() async {
        await withDefaults { defaults in
            let diagnostics = CleanupDiagnostics(defaults: defaults)
            XCTAssertNil(diagnostics.lastSummary())
            diagnostics.recordChange(true)
            diagnostics.record(CleanupObservation(outcome: .completed, latencyMilliseconds: 1800))
            XCTAssertEqual(diagnostics.lastSummary(), "Last dictation (just now): cleaned up by Apple Intelligence (1.8 s)")
            diagnostics.recordChange(false)
            diagnostics.record(CleanupObservation(outcome: .completed, latencyMilliseconds: 1200))
            XCTAssertEqual(diagnostics.lastSummary(), "Last dictation (just now): Apple Intelligence changed nothing (1.2 s)")
            diagnostics.record(CleanupObservation(outcome: .skipped(.off), latencyMilliseconds: 0))
            XCTAssertEqual(diagnostics.lastSummary(), "Last dictation (just now): Apple Intelligence changed nothing (1.2 s)")
            diagnostics.record(CleanupObservation(outcome: .skipped(.language), latencyMilliseconds: 0))
            XCTAssertTrue(diagnostics.lastSummary()!.contains("language not clearly recognised"))
            let later = Date().addingTimeInterval(3 * 60)
            XCTAssertTrue(diagnostics.lastSummary(now: later)!.hasPrefix("Last dictation (3 min ago): "))
            let stored = defaults.dictionary(forKey: CleanupDiagnostics.key)!
            XCTAssertEqual(Set(stored.keys), ["summary", "at", "deadline"])
        }
    }

    func testDeadlineSummaryLearnsTheModelsRealDuration() async {
        await withDefaults { defaults in
            let diagnostics = CleanupDiagnostics(defaults: defaults)
            diagnostics.recordLate(latencyMilliseconds: 9000)
            XCTAssertNil(diagnostics.lastSummary())
            diagnostics.record(CleanupObservation(outcome: .failed(.deadline), latencyMilliseconds: 4000))
            diagnostics.recordLate(latencyMilliseconds: 6200)
            diagnostics.recordLate(latencyMilliseconds: 7000)
            XCTAssertEqual(diagnostics.lastSummary(),
                "Last dictation (just now): Apple Intelligence took longer than 4 s; plain transcript used (it finished after 6.2 s)")
        }
    }

    func testCoordinatorReportsChangeAndLateCompletion() async {
        await withDefaults { defaults in
            let diagnostics = CleanupDiagnostics(defaults: defaults)
            let session = CleanupTestSession()
            let bg = CleanupTestBackground(), sleeper = CleanupTestSleeper()
            var deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: sleeper.sleep)
            deps.observer = diagnostics
            let coordinator = CleanupCoordinator()
            let raw = "Die Katze sitzt auf der Mathe"

            let a = CleanupJob(session: session, background: bg); a.begin()
            let cleaned = await coordinator.clean(raw, style: .polished, job: a, dependencies: deps)
            XCTAssertEqual(cleaned, session.result)
            XCTAssertTrue(diagnostics.lastSummary()!.contains("cleaned up by Apple Intelligence"))
            a.finish(); sleeper.fire(); await drain()

            session.result = raw
            let b = CleanupJob(session: session, background: bg); b.begin()
            _ = await coordinator.clean(raw, style: .polished, job: b, dependencies: deps)
            XCTAssertTrue(diagnostics.lastSummary()!.contains("changed nothing"))
            b.finish(); sleeper.fire(); await drain()

            session.suspend = true
            let c = CleanupJob(session: session, background: bg); c.begin()
            let task = Task { await coordinator.clean(raw, style: .polished, job: c, dependencies: deps) }
            await drain()
            sleeper.fire()
            let value = await task.value
            XCTAssertEqual(value, raw)
            XCTAssertTrue(diagnostics.lastSummary()!.contains("took longer than 4 s"))
            session.resume(); await drain()
            XCTAssertTrue(diagnostics.lastSummary()!.contains("(it finished after"))
            XCTAssertNil(coordinator.reservedBy)
            c.finish(); await drain()
        }
    }
}
