import XCTest
@testable import Typr

@MainActor
final class CleanupTestObserver: CleanupObserving {
    var events: [CleanupObservation] = []
    func record(_ observation: CleanupObservation) { events.append(observation) }
}

@MainActor
private final class MutableCleanupAvailability: TyprTranscriptCleaning {
    var unavailableReason: String?
    let session = CleanupTestSession()
    func makeSession() -> any CleanupSession { session }
}

private struct SecretCleanupError: Error, LocalizedError, CustomStringConvertible {
    let description = "SECRET-TRANSCRIPT-MARKER"
    var errorDescription: String? { description }
}

@MainActor
final class CleanupDesktopAnalogyTests: XCTestCase {
    private let raw = "Die Katze sitzt auf der Mathe"
    private func drain() async { for _ in 0..<30 { await Task.yield() } }

    func testDesktopNumbersOnlyPortAndGermanExtension() {
        for text in [
            "One, two, three, four, five, six, seven, eight, nine, ten.", "1355", "Twenty-one point five.",
            "one hundred and forty two", "one and", "-1,355.2", "(12), 34.", "1-2", "one--two",
            "eins zwei drei", "null zwölf zwanzig dreißig vierzig fünfzig sechzig siebzig achtzig neunzig",
            "hundert und tausend komma fünf", "eine million zwei milliarden", "minus fünf punkt zwei"
        ] { XCTAssertTrue(CleanupNumbers.only(text), text) }
        for text in [
            "", "And.", "Point one, the dataset has 1355 evaluation windows.", "Call me at five.",
            "eins nein zwei", "123abc", "12:30", "and point minus negative und punkt komma", "---", "...",
            "one,two", "1;2", "einundzwanzig", "١٢", "one—two"
        ] { XCTAssertFalse(CleanupNumbers.only(text), text) }
    }

    func testNumbersSkipBeforeLanguageAdmissionAndKeepPrewarmContract() async {
        let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver()
        let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(allowed: false),
            background: bg, isEnabled: { true }, observer: observer)
        let coordinator = CleanupCoordinator(), job = CleanupJob(session: session, background: bg)
        coordinator.prewarm(job); await drain(); job.begin()
        let value = await coordinator.clean("eins zwei drei", style: .polished, job: job, dependencies: deps)
        XCTAssertEqual(value, "eins zwei drei")
        XCTAssertEqual(session.prepareCount, 1)
        XCTAssertEqual(session.cleanCount, 0)
        XCTAssertEqual(observer.events.map(\.outcome), [.skipped(.numbersOnly)])
        job.finish()
    }

    func testTypedErrorsAndSecretDescriptionNeverReachObservation() async {
        let failures: [(any Error, CleanupFailureReason)] = [
            (CleanupModelError.contextWindow, .contextWindow), (CleanupModelError.refused, .refused),
            (CleanupModelError.rateLimited, .rateLimited), (CleanupModelError.generationFailed, .generationFailed),
            (CleanupModelError.unavailable, .unavailable), (SecretCleanupError(), .generationFailed)
        ]
        for (error, reason) in failures {
            let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver(), sleeper = CleanupTestSleeper()
            session.failure = error
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: sleeper.sleep, observer: observer)
            let job = CleanupJob(session: session, background: bg); job.begin()
            let coordinator = CleanupCoordinator()
            let value = await coordinator.clean(raw, style: .polished, job: job, dependencies: deps)
            XCTAssertEqual(value, raw)
            let expected: CleanupOutcome = reason == .unavailable ? .skipped(.unavailable) : .failed(reason)
            XCTAssertEqual(observer.events.map(\.outcome), [expected])
            XCTAssertFalse(String(describing: observer.events).contains("SECRET-TRANSCRIPT-MARKER"))
            job.finish(); sleeper.fire(); await drain()
        }
    }

    func testRawNotesAnchorsBeforeEmptyClassificationAndTrimming() async {
        let cases: [(String, String, DictationStyle, CleanupOutcome, String)] = [
            (raw, "   \t", .polished, .failed(.emptyOutput), raw),
            ("one line\nsecond line", "   ", .notes, .failed(.guardRejected(.notesLineAnchors)), "one line\nsecond line"),
            ("one line\nsecond line", "\n", .notes, .failed(.emptyOutput), "one line\nsecond line"),
            (raw, "\nDie Katze sitzt auf der Matte\n", .notes, .failed(.guardRejected(.notesLineAnchors)), raw),
            (raw, "  Die Katze sitzt auf der Matte  ", .notes, .completed, "Die Katze sitzt auf der Matte"),
            (raw, "Anna bekommt 950 Euro", .polished, .failed(.guardRejected(.newValue)), raw)
        ]
        for (input, output, style, outcome, expected) in cases {
            let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver(), sleeper = CleanupTestSleeper()
            session.result = output
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: sleeper.sleep, observer: observer)
            let job = CleanupJob(session: session, background: bg); job.begin()
            let coordinator = CleanupCoordinator()
            let value = await coordinator.clean(input, style: style, job: job, dependencies: deps)
            XCTAssertEqual(value, expected)
            XCTAssertEqual(observer.events.map(\.outcome), [outcome])
            job.finish(); sleeper.fire(); await drain()
        }
    }

    func testWinningResolutionObservesOnceWithMonotonicLatencyAndNeverLateSuccess() async {
        for outcome in [CleanupOutcome.failed(.deadline), .failed(.expired), .cancelled, .completed] {
            let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver(), sleeper = CleanupTestSleeper()
            session.suspend = true
            var now = ContinuousClock.now
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, sleep: sleeper.sleep, observer: observer, clock: { now })
            let job = CleanupJob(session: session, background: bg); job.begin()
            let coordinator = CleanupCoordinator()
            let task = Task { await coordinator.clean(raw, style: .polished, job: job, dependencies: deps) }
            await drain()
            now = now.advanced(by: .milliseconds(1250))
            switch outcome {
            case .failed(.deadline): sleeper.fire()
            case .failed(.expired): bg.expiration?()
            case .cancelled: task.cancel()
            default: session.resume()
            }
            _ = await task.value
            XCTAssertEqual(observer.events, [CleanupObservation(outcome: outcome, latencyMilliseconds: 1250)])
            session.resume(); sleeper.fire(); await drain()
            job.finish(); bg.expiration?(); coordinator.cancel(job.id)
            XCTAssertEqual(observer.events.count, 1)
        }
    }

    func testAllAdmissionSkipsAreInfoOutcomesNotFailures() async {
        for reason in [CleanupSkipReason.off, .verbatim, .unavailable, .busy] {
            let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver()
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(),
                background: bg, isEnabled: { true }, observer: observer)
            let coordinator = CleanupCoordinator()
            let value = await coordinator.clean(raw, style: .polished, job: nil, dependencies: deps, skipReason: reason)
            XCTAssertEqual(value, raw)
            XCTAssertEqual(observer.events.map(\.outcome), [.skipped(reason)])
            XCTAssertEqual(session.cleanCount, 0)
        }
        for reason in [CleanupSkipReason.language, .budget, .noBackgroundLease] {
            let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver()
            bg.invalid = reason == .noBackgroundLease
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), language: CleanupTestLanguage(allowed: reason != .language),
                background: bg, isEnabled: { true }, observer: observer)
            let coordinator = CleanupCoordinator(), job = CleanupJob(session: session, background: bg); job.begin()
            let input = reason == .budget ? String(repeating: "word ", count: CleanupCoordinator.maximumWords + 1) : raw
            let value = await coordinator.clean(input, style: .polished, job: job, dependencies: deps)
            XCTAssertEqual(value, input)
            XCTAssertEqual(observer.events.map(\.outcome), [.skipped(reason)])
            XCTAssertEqual(session.cleanCount, 0)
            job.finish()
        }
    }

    func testCleanupRechecksFreshAvailabilityEvenWhileUICacheSaysAvailable() async {
        let cleaner = MutableCleanupAvailability(), bg = CleanupTestBackground(), observer = CleanupTestObserver()
        let cache = CleanupAvailabilityCache { cleaner.unavailableReason }
        XCTAssertNil(cache.reason)
        let coordinator = CleanupCoordinator(), job = CleanupJob(session: cleaner.makeSession(), background: bg)
        coordinator.prewarm(job); await drain(); job.begin()
        cleaner.unavailableReason = "no longer available"
        XCTAssertNil(cache.reason, "the UI is allowed to cache for ten seconds")
        let deps = TranscriptCleanupDependencies(cleaner: cleaner, language: CleanupTestLanguage(), background: bg,
            isEnabled: { true }, observer: observer)
        let value = await coordinator.clean(raw, style: .polished, job: job, dependencies: deps)
        XCTAssertEqual(value, raw)
        XCTAssertEqual(cleaner.session.cleanCount, 0)
        XCTAssertEqual(observer.events.map(\.outcome), [.skipped(.unavailable)])
        job.finish()
    }

    func testUIAvailabilityCacheHasTenSecondTTLAndExplicitInvalidation() {
        var now = ContinuousClock.now, reads = 0
        var reason: String? = "not ready"
        let cache = CleanupAvailabilityCache(now: { now }) { reads += 1; return reason }
        XCTAssertEqual(cache.reason, "not ready")
        reason = nil
        now = now.advanced(by: .seconds(9))
        XCTAssertEqual(cache.reason, "not ready")
        XCTAssertEqual(reads, 1)
        now = now.advanced(by: .seconds(1))
        XCTAssertNil(cache.reason)
        XCTAssertEqual(reads, 2)
        XCTAssertNil(cache.reason)
        XCTAssertEqual(reads, 2, "available (nil reason) must also be cached")
        cache.invalidate()
        XCTAssertNil(cache.reason)
        XCTAssertEqual(reads, 3)
    }

    func testDesktopPromptProtocolAndTranscriptTagsWithoutListsRule() throws {
        XCTAssertTrue(CleanupPrompt.instructions.contains("Return only the text that should be pasted. Do not add an explanation, label, alternative, or Markdown fence."))
        XCTAssertTrue(CleanupPrompt.instructions.contains("Numbers: keep every number the speaker said unless the speaker explicitly corrected it. Never drop, merge, reorder, round, or reinterpret a number, and never add thousands separators or other formatting to a number that the transcript already writes in digits."))
        XCTAssertTrue(CleanupPrompt.instructions.contains("text field"))
        XCTAssertFalse(CleanupPrompt.instructions.contains("Lists:"))
        // As on the desktop, the transcript sits unchanged between <transcript> tags.
        let input = "Say \"hello\" ähm\nnew line"
        let notes = try CleanupPrompt.transcript(input, style: .notes)
        XCTAssertTrue(notes.contains("<transcript>\n\(input)\n</transcript>"))
        XCTAssertTrue(notes.contains("new paragraph"))
        XCTAssertFalse(try CleanupPrompt.transcript(input, style: .polished).contains("bullet"))
    }
}
