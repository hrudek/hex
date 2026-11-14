import Foundation
import XCTest
@testable import Typr

final class KeyboardDiagnosticsPresentationTests: XCTestCase {
    private typealias Presentation = KeyboardDiagnosticsPresentation

    func testAutomaticAndUndoTotalsKeepAllMethodsSeparateFromUnchanged() {
        var diagnostics = KeyboardDiagnostics()
        XCTAssertEqual(Presentation.automaticTotal(diagnostics), 0)
        XCTAssertEqual(Presentation.undoTotal(diagnostics), 0)
        diagnostics.increment(.autoSpatialSameLength, by: 10)
        diagnostics.increment(.autoSpatialEdit, by: 5)
        diagnostics.increment(.autoSpellingFallback, by: 4)
        diagnostics.increment(.autoRule, by: 3)
        diagnostics.increment(.unchanged, by: 90)
        diagnostics.increment(.undoSpatial, by: 2)
        diagnostics.increment(.undoSpelling)
        diagnostics.increment(.undoRule)
        XCTAssertEqual(Presentation.automaticTotal(diagnostics), 22)
        XCTAssertEqual(Presentation.undoTotal(diagnostics), 4)
    }

    func testRecordedHistogramEdgesFeedTheSameOrderedPresentationBucketsForBothSeries() {
        var diagnostics = KeyboardDiagnostics()
        for seconds in [0.0, 0.001, 0.002, 0.005, 0.010, 0.020, 0.050] {
            diagnostics.recordLatency(seconds, kind: .boundary)
            diagnostics.recordLatency(seconds, kind: .suggestion)
        }
        for counts in [diagnostics.boundaryMs, diagnostics.suggestionMs] {
            let latency = Presentation.latency(buckets: counts, referenceCount: 7)
            XCTAssertEqual(latency.buckets.map(\.count), Array(repeating: 1, count: 7))
            XCTAssertEqual(latency.buckets.map(\.upperMilliseconds), [1, 2, 5, 10, 20, 50, nil])
        }
    }

    func testTouchOffsetsAndSigmaMapFromPitchUnitsToLayoutPoints() throws {
        for orientation in [KeyboardOrientation.portrait, .landscape] {
            for strip in [false, true] {
                for globe in [false, true] {
                    let original = KeyboardLayout(width: orientation == .portrait ? 393 : 847,
                        orientation: orientation, showsGlobe: globe, showsStrip: strip)
                    let signature = KeyboardLayoutSignature(original)
                    let layout = KeyboardTouchGeometry.layout(for: signature)
                    XCTAssertEqual(KeyboardLayoutSignature(layout), signature)
                    XCTAssertEqual(layout.width, CGFloat(signature.widthBucket))
                    let key = try XCTUnwrap(layout.key(.character("g")))
                    let summary = PersonalTypingModel.KeySummary(letter: "g", n: 40,
                        offsetX: 0.2, offsetY: -0.1, sigmaX: 0.25, sigmaY: 0.3)
                    let center = KeyboardTouchGeometry.center(for: summary, key: key, layout: layout)
                    let pitchX = key.frame.width + layout.metrics.gap
                    let pitchY = key.frame.height + layout.metrics.rowGap
                    XCTAssertEqual(center.x, key.frame.midX + 0.2 * pitchX, accuracy: 0.000001)
                    XCTAssertEqual(center.y, key.frame.midY - 0.1 * pitchY, accuracy: 0.000001)
                    let ellipse = KeyboardTouchGeometry.ellipse(for: summary, key: key, layout: layout)
                    XCTAssertEqual(ellipse.midX, center.x, accuracy: 0.000001)
                    XCTAssertEqual(ellipse.midY, center.y, accuracy: 0.000001)
                    XCTAssertEqual(ellipse.width, 2 * 0.25 * pitchX, accuracy: 0.000001)
                    XCTAssertEqual(ellipse.height, 2 * 0.3 * pitchY, accuracy: 0.000001)
                    XCTAssertTrue(summary.isCalibrated)
                    XCTAssertFalse(PersonalTypingModel.KeySummary(letter: "g", n: 19,
                        offsetX: 0, offsetY: 0, sigmaX: 0.35, sigmaY: 0.35).isCalibrated)
                }
            }
        }
    }

    @MainActor
    func testLearningResetThroughAppAdapterPreservesStatistics() throws {
        try withStore { directory, defaults in
            let writer = KeyboardLearningStore(directory: directory, defaults: defaults)
            let learning = PersonalTypingModel()
            learning.keep("hello")
            learning.recordWord("hello")
            var diagnostics = KeyboardDiagnostics()
            diagnostics.increment(.boundaries, by: 10)
            XCTAssertTrue(writer.save(model: learning.state, diagnostics: &diagnostics))
            let model = KeyboardDiagnosticsModel(directory: directory, defaults: defaults)
            XCTAssertEqual(model.snapshot.model.keptWords, 1)
            model.resetLearning()
            XCTAssertNil(model.resetProblem)
            XCTAssertEqual(defaults.integer(forKey: KeyboardLearningStore.learningResetKey), 1)
            XCTAssertEqual(defaults.integer(forKey: KeyboardLearningStore.diagnosticsResetKey), 0)
            XCTAssertEqual(model.snapshot.model.keptWords, 0)
            XCTAssertEqual(model.snapshot.model.wordCountTotal, 0)
            XCTAssertEqual(model.snapshot.diagnostics[.boundaries], 10)
            XCTAssertNil(model.snapshot.learningFile.bytes)
        }
    }

    @MainActor
    func testStatisticsResetThroughAppAdapterPreservesLearningAndReloadsSettings() throws {
        try withStore { directory, defaults in
            let writer = KeyboardLearningStore(directory: directory, defaults: defaults)
            let learning = PersonalTypingModel()
            learning.keep("world")
            var diagnostics = KeyboardDiagnostics()
            diagnostics.increment(.boundaries, by: 20)
            XCTAssertTrue(writer.save(model: learning.state, diagnostics: &diagnostics))
            let model = KeyboardDiagnosticsModel(directory: directory, defaults: defaults)
            XCTAssertTrue(model.learningEnabled)
            TyprSettings(defaults: defaults).personalLearning = false
            model.resetStatistics()
            XCTAssertNil(model.resetProblem)
            XCTAssertFalse(model.learningEnabled)
            XCTAssertEqual(defaults.integer(forKey: KeyboardLearningStore.diagnosticsResetKey), 1)
            XCTAssertEqual(defaults.integer(forKey: KeyboardLearningStore.learningResetKey), 0)
            XCTAssertEqual(model.snapshot.model.keptWords, 1)
            XCTAssertEqual(model.snapshot.diagnostics[.boundaries], 0)
            XCTAssertNil(model.snapshot.diagnosticsFile.bytes)
        }
    }

    @MainActor
    func testResetFailureHasAnActionableMessage() {
        let model = KeyboardDiagnosticsModel(directory: nil, defaults: nil)
        model.resetLearning()
        XCTAssertNotNil(model.resetProblem)
        model.resetStatistics()
        XCTAssertNotNil(model.resetProblem)
    }

    @MainActor
    func testSnapshotFixtureIsExplicitAndCannotRefreshOrResetRealStorage() {
        XCTAssertNotNil(KeyboardDiagnosticsFixture.scene(arguments: ["Typr", "--snap-state", "settings-keyboard-diagnostics"]))
        for args in [[], ["--snap-state"], ["settings-keyboard-diagnostics"], ["--snap-state", "settings-keyboard"]] {
            XCTAssertNil(KeyboardDiagnosticsFixture.scene(arguments: args))
        }
        let fixture = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        let second = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        XCTAssertEqual(fixture.model, second.model)
        XCTAssertEqual(fixture.diagnostics, second.diagnostics)
        let model = KeyboardDiagnosticsModel(fixture: fixture)
        model.startObserving()
        model.refresh()
        model.resetLearning()
        model.resetStatistics()
        model.stopObserving()
        XCTAssertEqual(model.snapshot.model, fixture.model)
        XCTAssertEqual(model.snapshot.diagnostics, fixture.diagnostics)
        XCTAssertEqual(model.snapshot.model.layouts.count, 2)
        XCTAssertEqual(model.snapshot.diagnostics[.boundaries], 1000)
    }

    @MainActor
    func testReadoutMapsEveryCounterSourceAndReasonWithoutMergingPopulations() throws {
        let readout = readout()
        let stats = try XCTUnwrap(readout.statistics)
        XCTAssertEqual(Presentation.mappedCounters, Set(KeyboardDiagnostics.Counter.allCases))
        XCTAssertEqual(Presentation.mappedCounters.count, 33)
        XCTAssertEqual(stats.acceptedBySource.map(\.id), TouchLabelSource.allCases.map(\.rawValue))
        XCTAssertEqual(stats.rejectedByReason.map(\.id), TouchLabelRejection.allCases.map(\.rawValue))
        XCTAssertEqual(stats.acceptedTotal, 1164)
        XCTAssertEqual(stats.rejectedTotal, 32)
        XCTAssertEqual(stats.refusalGroups.map(\.title), ["Guards", "Not certain enough to replace", "Word data"])
        XCTAssertEqual(stats.refusalGroups[0].rows.map(\.id), [.refusedLiteralValid, .refusedProtected])
        XCTAssertEqual(stats.refusalGroups[1].rows.map(\.id),
                       [.refusedAmbiguous, .refusedIncompleteSearch, .refusedBelowMargin, .refusedValidation])
        XCTAssertEqual(stats.refusalGroups[2].rows.map(\.id), [.refusedMissingResource, .resourceLoading])
        XCTAssertEqual(Presentation.counterLabel(.evidenceLengthOutOfRange), "Word length outside 3–32 letters")
        XCTAssertEqual(Presentation.belowMarginHelp,
                       "No candidate was clearly better, or the candidate would only have completed the word. Can come from tap positions or the spelling check.")
        XCTAssertEqual(stats.choices.map(\.count), [16, 28, 42, 11])
        XCTAssertEqual(stats.reattributedTaps, 12)
        XCTAssertEqual(stats.storageEvents.map(\.id), Presentation.storageCounters)
        let learning = try XCTUnwrap(readout.learning)
        XCTAssertEqual(learning.keptWords, 2)
        XCTAssertEqual(learning.countedWords, 2)
        XCTAssertEqual(learning.wordCountTotal, 20)
        XCTAssertEqual(learning.rejectedCorrections, 1)
        XCTAssertEqual(learning.storedPairs, 2)
        XCTAssertGreaterThan(learning.pairByteBound, 128)
        XCTAssertEqual(learning.layouts.count, 2)
    }

    func testNewCounterAndExampleLabelsMatchApprovedCopy() {
        let expected: [KeyboardDiagnostics.Counter: String] = [
            .boundaries: "Words checked", .evidenceComplete: "Tap data available",
            .evidenceMissing: "No tap data, or taps discarded",
            .evidenceLengthOutOfRange: "Word length outside 3–32 letters",
            .evidenceUnsupported: "Characters not supported (a–z only)",
            .autoSpatialSameLength: "Same length", .autoSpatialEdit: "Letter missing, extra or swapped",
            .autoSpellingFallback: "Replaced by spelling check", .autoRule: "Replaced by a rule or text replacement",
            .unchanged: "Left unchanged", .refusedLiteralValid: "Typed word is valid",
            .refusedProtected: "Protected word, rejected correction, capitals or identifier",
            .refusedAmbiguous: "Alternatives too close to call", .refusedIncompleteSearch: "Search limit reached",
            .refusedMissingResource: "Word data unavailable", .resourceLoading: "Word data still loading",
            .refusedValidation: "Dictionary did not confirm the replacement", .refusedBelowMargin: "Not enough evidence to replace",
            .undoSpatial: "Tap positions", .undoSpelling: "Spelling check", .undoRule: "Rules and text replacements",
            .keepChip: "Kept as typed", .manualAlternativePick: "Picked an alternative", .manualCompletionPick: "Picked a completion",
            .personalCompletionPick: "Of these from your personal words", .suggestionDecodes: "Recorded suggestion searches",
            .wordsCounted: "Words counted for learning", .wordsKept: "Words you kept", .correctionsRejected: "Corrections rejected",
            .storeCorruptDiscarded: "Invalid saved data ignored", .storeWriteFailed: "Save failures or repairs",
            .storeLoadDeferred: "Delayed learning loads", .reattributedTaps: "Letter taps moved to a neighbouring key"]
        XCTAssertEqual(Set(expected.keys), Set(KeyboardDiagnostics.Counter.allCases))
        for (counter, label) in expected { XCTAssertEqual(Presentation.counterLabel(counter), label) }
        XCTAssertEqual(TouchLabelSource.allCases.map { Presentation.exampleSourceLabel($0) },
            ["Word left as typed", "Kept as typed", "Undone replacement", "Picked alternative"])
        XCTAssertEqual(TouchLabelRejection.allCases.map { Presentation.exampleRejectionLabel($0) },
            ["Tap too far from the assumed key", "Position could not be used", "Key not recognised",
             "Keyboard layout could not be used", "Taps could not be matched to letters", "Learning was switched off"])
    }

    @MainActor
    func testReadoutAvailabilityDoesNotPresentDefaultsAsObservedZeroes() throws {
        let empty = readout(.empty)
        XCTAssertNil(empty.statistics); XCTAssertNil(empty.learning)
        XCTAssertNil(empty.scope.statisticsSince); XCTAssertNil(empty.scope.savedAt)
        XCTAssertEqual(empty.scope.savedTimeSource, .none)
        XCTAssertNil(empty.scope.notice)
        let zero = try XCTUnwrap(readout(.zero).statistics)
        XCTAssertEqual(zero.decisions.population, 0)
        XCTAssertTrue(zero.decisions.isConsistent)
        XCTAssertFalse(zero.decisions.canShowParts)
        XCTAssertEqual(zero.automatic.status, .empty)
        XCTAssertEqual(zero.undo.status, .empty)
        XCTAssertNil(readout(.statisticsOnly).learning)
        XCTAssertNotNil(readout(.statisticsOnly).statistics)
        XCTAssertEqual(readout(.statisticsOnly).scope.savedTimeSource, .statisticsOnly)
        XCTAssertNil(readout(.learningOnly).statistics)
        XCTAssertNil(readout(.learningOnly).scope.statisticsSince)
        XCTAssertNotNil(readout(.learningOnly).learning)
        XCTAssertEqual(readout(.learningOnly).scope.savedTimeSource, .learningOnly)
        let unreadable = readout(.unreadable)
        XCTAssertNil(unreadable.statistics); XCTAssertNil(unreadable.learning)
        XCTAssertNil(unreadable.scope.statisticsSince)
        XCTAssertEqual(unreadable.scope.notice, .unreadable)
        XCTAssertNotNil(unreadable.scope.learningFile.bytes)
        XCTAssertNotNil(unreadable.scope.savedAt)
    }

    @MainActor
    func testPartialMetadataIsIndependentAndOldestTimeControlsHeaderAndStaleness() {
        let now = KeyboardDiagnosticsFixture.now
        let base = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        func present(_ learning: KeyboardLearningSnapshot.FileInfo,
                     _ statistics: KeyboardLearningSnapshot.FileInfo, persistent: Bool = true) -> Presentation.Readout {
            Presentation.make(snapshot: .init(model: base.model, diagnostics: base.diagnostics,
                learningFile: learning, diagnosticsFile: statistics, isPersistent: persistent),
                learningEnabled: true, now: now, locale: Locale(identifier: "en_US"))
        }
        let missing = KeyboardLearningSnapshot.FileInfo(bytes: nil, modifiedAt: nil)
        let bytesOnly = KeyboardLearningSnapshot.FileInfo(bytes: 0, modifiedAt: nil)
        let timeOnly = KeyboardLearningSnapshot.FileInfo(bytes: nil, modifiedAt: now)
        let partial = present(bytesOnly, timeOnly)
        XCTAssertNotNil(partial.learning); XCTAssertNotNil(partial.statistics)
        XCTAssertEqual(partial.scope.savedAt, now)
        XCTAssertEqual(partial.scope.savedTimeSource, .statisticsOnly)
        XCTAssertEqual(partial.scope.statisticsFile.sizeText(), "No file size available")
        XCTAssertNotEqual(partial.scope.learningFile.sizeText(), "No file size available")
        XCTAssertNil(present(bytesOnly, missing).scope.savedAt)
        XCTAssertEqual(present(timeOnly, bytesOnly).scope.savedTimeSource, .learningOnly)
        for age in [86_400.0, 86_401.0] {
            let old = KeyboardLearningSnapshot.FileInfo(bytes: nil, modifiedAt: now.addingTimeInterval(-age))
            for swapped in [false, true] {
                let value = present(swapped ? timeOnly : old, swapped ? old : timeOnly)
                XCTAssertEqual(value.scope.savedAt, old.modifiedAt)
                XCTAssertEqual(value.scope.notice, age > 86_400 ? .stale : nil)
                XCTAssertEqual(value.scope.savedTimeSource, .both)
                XCTAssertEqual(present(old, old, persistent: false).scope.notice, .unreadable)
            }
        }
        XCTAssertNil(present(missing, missing).scope.notice)
        XCTAssertNil(present(.init(bytes: nil, modifiedAt: now.addingTimeInterval(60)), missing).scope.notice)
        XCTAssertEqual(readout(.stale).scope.notice?.text,
            "At least one saved file is more than 24 hours old. Anything typed since then that wasn't saved isn't shown here.")
    }

    @MainActor
    func testCorruptionIsHistoricalNotAnAvailabilityOrPartitionFailure() throws {
        let value = readout(.invalid)
        XCTAssertNil(value.scope.notice)
        XCTAssertNotNil(value.scope.statisticsSince)
        let stats = try XCTUnwrap(value.statistics)
        XCTAssertTrue(stats.decisions.canShowParts)
        XCTAssertTrue(stats.evidence.canShowParts)
        XCTAssertEqual(stats.storageEvents.first?.count, 2)
        XCTAssertEqual(stats.historicalStorageText(locale: Locale(identifier: "en_US")),
            "Typr ignored saved data it couldn't use (2 times in the available statistics). Data from before that may be missing.")
        XCTAssertNil(readout().statistics?.historicalStorageText())
    }

    @MainActor
    func testComparisonsKeepRawCountsAndGateInvalidPartitionsAndSubsets() throws {
        let stats = try XCTUnwrap(readout().statistics)
        XCTAssertTrue(stats.decisions.canShowParts)
        XCTAssertEqual(stats.decisions.sum, 1000)
        XCTAssertEqual(stats.automatic, .init(250, of: 1000))
        XCTAssertEqual(stats.undo, .init(9, of: 250))
        XCTAssertEqual(stats.methods.map(\.comparison.denominator), [135, 35, 80])
        XCTAssertEqual(stats.methods.map(\.comparison.numerator), [6, 2, 1])
        XCTAssertTrue(stats.personalCompletionIsSubset)
        let broken = try XCTUnwrap(readout(.inconsistent).statistics)
        XCTAssertFalse(broken.decisions.canShowParts)
        XCTAssertFalse(broken.evidence.canShowParts)
        XCTAssertGreaterThan(broken.decisions.sum, Int(Int32.max))
        XCTAssertEqual(broken.decisions.rows[0].count, Int(Int32.max))
        XCTAssertEqual(broken.automatic.status, .incomparable)
        XCTAssertEqual(broken.undo.status, .incomparable)
        XCTAssertTrue(broken.methods.allSatisfy { $0.comparison.status == .incomparable })
        XCTAssertFalse(broken.personalCompletionIsSubset)
        XCTAssertNil(stats.decisions.inconsistencyText())
        XCTAssertEqual(broken.evidence.inconsistencyText(locale: Locale(identifier: "en_US")),
            "These counts add up to 2,147,484,527, not 1,000. Some counters may be incomplete.")
        XCTAssertEqual(Presentation.Comparison(0, of: 0).status, .empty)
        XCTAssertEqual(Presentation.Comparison(1, of: 0).status, .incomparable)
        XCTAssertEqual(Presentation.Comparison(3, of: 2).status, .incomparable)
        XCTAssertEqual(Presentation.Comparison(0, of: 2).status, .comparable)
        XCTAssertEqual(Presentation.Comparison(0, of: 0, allowed: false).status, .incomparable)
    }

    func testLatencyUsesOwnHistogramAndFirstCumulativeHalfRankForEvenAndOddN() {
        let locale = Locale(identifier: "en_US")
        let empty = Presentation.latency(buckets: Array(repeating: 0, count: 7), referenceCount: 12)
        XCTAssertEqual(empty.n, 0); XCTAssertNil(empty.halfBucket); XCTAssertNil(empty.highestBucket)
        XCTAssertTrue(empty.differsFromReference)
        XCTAssertEqual(empty.halfText(), "No measurements recorded in the available statistics.")
        for bucket in 0..<7 {
            for count in [1, 2, 3, 4] {
                var buckets = Array(repeating: 0, count: 7)
                buckets[bucket] = count
                let value = Presentation.latency(buckets: buckets, referenceCount: count)
                XCTAssertEqual(value.buckets.map(\.id), Array(0..<7))
                XCTAssertEqual(value.n, count)
                XCTAssertFalse(value.differsFromReference)
                XCTAssertEqual(value.halfBucket?.id, bucket)
                XCTAssertEqual(value.highestBucket?.id, bucket)
                let expected = bucket == 6 ? "At least half took 50 ms or more."
                    : "At least half took under \([1, 2, 5, 10, 20, 50][bucket]) ms."
                XCTAssertEqual(value.halfText(locale: locale), expected)
            }
        }
        for buckets in [[1, 0, 0, 0, 0, 0, 1], [1, 1, 0, 0, 0, 0, 2], [1, 1, 0, 0, 0, 0, 3]] {
            let value = Presentation.latency(buckets: buckets, referenceCount: 99)
            let half = value.halfBucket!.id
            let rank = (value.n + 1) / 2
            XCTAssertGreaterThanOrEqual(buckets.prefix(half + 1).reduce(0, +), rank)
            XCTAssertLessThan(buckets.prefix(half).reduce(0, +), rank)
            XCTAssertEqual(value.highestBucket?.id, 6)
        }
        XCTAssertEqual(Presentation.latency(buckets: [1, 0, 0, 0, 0, 0, 1], referenceCount: 0).halfBucket?.id, 0)
        let saturated = Presentation.latency(buckets: Array(repeating: Int(Int32.max), count: 7), referenceCount: Int(Int32.max))
        XCTAssertEqual(saturated.n, 7 * Int(Int32.max))
        XCTAssertEqual(saturated.halfBucket?.id, 3)
        XCTAssertTrue(saturated.differsFromReference)
        XCTAssertEqual(saturated.buckets.map(\.label), ["Under 1 ms", "1 up to 2 ms", "2 up to 5 ms", "5 up to 10 ms", "10 up to 20 ms", "20 up to 50 ms", "50 ms or more"])
        XCTAssertEqual(saturated.buckets.map(\.tick), ["<1", "1–<2", "2–<5", "5–<10", "10–<20", "20–<50", "≥50"])
    }

    @MainActor
    func testBothLatencyDiscrepanciesRemainVisibleEvenWithoutWordChecks() throws {
        let normal = try XCTUnwrap(readout().statistics)
        XCTAssertEqual(normal.wordCheckTime.n, 1000)
        XCTAssertEqual(normal.suggestionTime.n, 3200)
        XCTAssertFalse(normal.wordCheckTime.differsFromReference)
        XCTAssertFalse(normal.suggestionTime.differsFromReference)
        let broken = try XCTUnwrap(readout(.inconsistent).statistics)
        XCTAssertEqual(broken.wordCheckTime.n, 7 * Int(Int32.max))
        XCTAssertEqual(broken.wordCheckTime.referenceCount, 1000)
        XCTAssertEqual(broken.suggestionTime.n, 1)
        XCTAssertEqual(broken.suggestionTime.referenceCount, 3200)
        XCTAssertTrue(broken.wordCheckTime.differsFromReference)
        XCTAssertTrue(broken.suggestionTime.differsFromReference)
        XCTAssertNil(normal.suggestionTime.discrepancyText())
        XCTAssertEqual(broken.suggestionTime.discrepancyText(locale: Locale(identifier: "en_US")),
            "The histogram contains 1 measurements; the event counter records 3,200. Both saved counts are shown.")
        let base = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        var d = KeyboardDiagnostics(now: KeyboardDiagnosticsFixture.now)
        d.recordLatency(0.001, kind: .boundary)
        d.increment(.wordsKept)
        let value = Presentation.make(snapshot: .init(model: base.model, diagnostics: d,
            learningFile: base.learningFile, diagnosticsFile: base.diagnosticsFile, isPersistent: true),
            learningEnabled: true, now: KeyboardDiagnosticsFixture.now)
        XCTAssertEqual(value.statistics?.decisions.population, 0)
        XCTAssertEqual(value.statistics?.wordCheckTime.n, 1)
        XCTAssertEqual(value.statistics?.learningEvents.first { $0.id == .wordsKept }?.count, 1)
    }

    @MainActor
    func testSharedHelpMatchesFinalCopyWithoutDependingOnSectionOrder() {
        XCTAssertEqual(DiagnosticsCopy.requirement,
            "Typr saves these counts only when the full keyboard is used with Full Access. This page can't tell which applies.")
        XCTAssertEqual(DiagnosticsCopy.undoHelp,
            "This counts immediate undos after automatic replacements, not accuracy. Fixing a word by hand isn't counted, and no undo doesn't show that a replacement was wanted.")
        XCTAssertEqual(DiagnosticsCopy.savedNowHelp,
            "What the saved model holds. It can cover a different period than the learning events. Older entries can be dropped.")
    }

    @MainActor
    func testLearningOffPreservesProtectionEventsAndUsesApprovedExplanation() throws {
        let off = readout(.learningOff)
        XCTAssertFalse(off.learningEnabled)
        XCTAssertEqual(off.learningExplanation,
            "Typr doesn't learn new taps, word counts or word contexts, and doesn't use them for suggestions or tap positions. Saved data stays. Kept words and rejected corrections still prevent unwanted replacements, and undoing a replacement still saves a rejected correction.")
        XCTAssertEqual(readout().learningExplanation,
            "Typr adapts to your taps, word counts and word contexts. Without Full Access, learning lasts only for the keyboard session and can't be shown here.")
        XCTAssertEqual(Presentation.learningEventsHelp,
            "Counts of learning events in the available statistics. Repeating the same word counts again. These are events, not the number of different words. Kept words and rejected corrections can increase while learning is off.")
        let events = try XCTUnwrap(off.statistics).learningEvents
        XCTAssertEqual(events.map(\.count), [750, 16, 9])
        XCTAssertEqual(off.learning?.keptWords, 2)
        XCTAssertEqual(off.learning?.rejectedCorrections, 1)
    }

    @MainActor
    func testLayoutSelectionUsesNewestThenIDAndRetainsValidSelection() throws {
        let learning = try XCTUnwrap(readout().learning)
        XCTAssertEqual(learning.selectedLayout(id: nil)?.summary.signature.orientation, "portrait")
        let last = try XCTUnwrap(learning.layouts.last)
        XCTAssertEqual(learning.selectedLayout(id: last.id)?.id, last.id)
        XCTAssertEqual(learning.selectedLayout(id: "removed")?.id, learning.layouts.first?.id)
        let fixture = KeyboardDiagnosticsFixture.context(for: .init(page: .learning, state: .removedLayout))
        let removed = try XCTUnwrap(fixture.removedLayoutID)
        let current = Presentation.make(snapshot: fixture.snapshot, learningEnabled: true, now: fixture.now)
        XCTAssertEqual(current.learning?.layouts.count, 1)
        XCTAssertNotEqual(current.learning?.selectedLayout(id: removed)?.id, removed)
        XCTAssertEqual(readout(.singleLayout).learning?.layouts.count, 1)
        let base = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        let tiedLayouts = base.model.layouts.reversed().map {
            PersonalTypingModel.LayoutSummary(signature: $0.signature, lastUpdated: KeyboardDiagnosticsFixture.now, keys: $0.keys)
        }
        let model = PersonalTypingModel.Summary(layouts: tiedLayouts, keptWords: 0, countedWords: 0,
            wordCountTotal: 0, rejectedCorrections: 0)
        let tied = Presentation.make(snapshot: .init(model: model, diagnostics: base.diagnostics,
            learningFile: base.learningFile, diagnosticsFile: base.diagnosticsFile, isPersistent: true),
            learningEnabled: true, now: KeyboardDiagnosticsFixture.now)
        XCTAssertEqual(tied.learning?.layouts.map(\.id), tiedLayouts.map { $0.signature.id }.sorted())
    }

    @MainActor
    func testSmallFixtureAndAvailableModelWithNoTapMapDoNotInventEstimates() throws {
        let small = try XCTUnwrap(readout(.small).statistics)
        XCTAssertEqual(small.decisions.population, 1)
        XCTAssertTrue(small.decisions.canShowParts)
        XCTAssertEqual(small.wordCheckTime.n, 1)
        XCTAssertEqual(small.wordCheckTime.halfBucket?.id, 2)
        XCTAssertEqual(small.suggestionTime.n, 2)
        let base = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        let empty = Presentation.make(snapshot: .init(model: PersonalTypingModel.summarize(.init()),
            diagnostics: base.diagnostics, learningFile: base.learningFile,
            diagnosticsFile: base.diagnosticsFile, isPersistent: true),
            learningEnabled: true, now: KeyboardDiagnosticsFixture.now)
        XCTAssertTrue(empty.scope.learningAvailable)
        XCTAssertEqual(empty.learning?.layouts.count, 0)
        XCTAssertNil(empty.learning?.selectedLayout(id: nil))
        XCTAssertEqual(empty.learning?.keptWords, 0)
    }

    @MainActor
    func testAllLettersAndSampleStatusesHaveSeparateOffsetAndShapeAlternatives() throws {
        let learning = try XCTUnwrap(readout(.unsampled).learning)
        let layout = try XCTUnwrap(learning.layouts.first)
        XCTAssertEqual(layout.keys.map(\.id), "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))
        XCTAssertEqual(Array(layout.keys.prefix(5).map(\.n)), [0, 19, 20, 256, 0])
        XCTAssertEqual(Array(layout.keys.prefix(5).map(\.status)), [.none, .few, .twentyOrMore, .twentyOrMore, .none])
        XCTAssertEqual(layout.keysWithTwentyExamples, 2)
        XCTAssertEqual(layout.coverageText(locale: Locale(identifier: "en_US")), "2 of 26 keys with 20 or more tap examples – \(layout.title)")
        for index in [0, 4] {
            XCTAssertNil(layout.keys[index].offset)
            XCTAssertNil(layout.keys[index].halfLengths)
            XCTAssertNil(layout.keys[index].direction)
            XCTAssertEqual(layout.keys[index].offsetText, "Not available")
        }
        let sampled = layout.keys[1]
        XCTAssertEqual(sampled.accessibilityLabel(locale: Locale(identifier: "en_US")),
                       "B, 19 tap examples, Fewer than 20 tap examples, model offset 0.12 key spacings right, 0.06 up")
        for (index, status) in [(1, "Fewer than 20 tap examples"), (2, "20 or more tap examples"),
                                (3, "20 or more tap examples")] {
            let key = layout.keys[index]
            XCTAssertEqual(key.accessibilityLabel(locale: Locale(identifier: "en_US")),
                           "\(key.id), \(key.n) tap examples, \(status), model offset \(try XCTUnwrap(key.offset))")
            XCTAssertFalse(key.accessibilityLabel().contains("degrees"))
            XCTAssertFalse(key.accessibilityLabel().contains("half-lengths"))
        }
        XCTAssertTrue(sampled.shapeAccessibilityLabel.contains("About"))
        XCTAssertEqual(layout.keys[0].accessibilityLabel(), "A, no tap examples, model offset not available")
        XCTAssertEqual(layout.keys[0].shapeAccessibilityLabel, "A, model shape not available")
    }

    func testOffsetsRoundBeforeDirectionAndNeverProduceNegativeZero() {
        let locale = Locale(identifier: "en_US")
        let cases: [(Double, Double, String)] = [
            (0, 0, "At the key centre"), (-0.004, 0.004, "At the key centre"),
            (0.12, 0, "0.12 key spacings right"), (-0.12, 0, "0.12 key spacings left"),
            (0, 0.12, "0.12 key spacings down"), (0, -0.12, "0.12 key spacings up"),
            (-0.12, 0.23, "0.12 key spacings left, 0.23 down")]
        for (x, y, expected) in cases { XCTAssertEqual(Presentation.offsetText(x: x, y: y, locale: locale), expected) }
        XCTAssertEqual(Presentation.decimal(-0.004, locale: locale), "0.00")
        XCTAssertEqual(Presentation.decimal(0.12, locale: Locale(identifier: "de_DE")), "0,12")
        XCTAssertEqual(Presentation.integer(1234, locale: locale), "1,234")
    }

    func testOvalEigenaxesCorrelationAndRoundedCircleHaveNoInventedDirection() throws {
        let signature = KeyboardLayoutSignature(KeyboardLayout(width: 392))
        func rows(sigmaX: Double, sigmaY: Double, c: Double = 0) -> [Presentation.KeyRow] {
            Presentation.keyRows(.init(signature: signature, lastUpdated: Date(timeIntervalSince1970: 0),
                keys: [.init(letter: "a", n: 20, offsetX: 0, offsetY: 0, sigmaX: sigmaX, sigmaY: sigmaY, covarianceXY: c)]),
                locale: Locale(identifier: "en_US"))
        }
        let key = PersonalTypingModel.KeySummary(letter: "a", n: 20, offsetX: 0, offsetY: 0,
            sigmaX: 0.3, sigmaY: 0.3, covarianceXY: 0.04)
        let oval = KeyboardTouchGeometry.oval(for: key)
        XCTAssertEqual(oval.major, sqrt(0.13), accuracy: 0.000001)
        XCTAssertEqual(oval.minor, sqrt(0.05), accuracy: 0.000001)
        XCTAssertEqual(oval.angleDegrees, 45, accuracy: 0.000001)
        XCTAssertEqual(rows(sigmaX: 0.3, sigmaY: 0.3, c: 0.04)[0].direction,
                       "About 45 degrees clockwise from horizontal in key-spacing coordinates")
        XCTAssertEqual(rows(sigmaX: 0.3, sigmaY: 0.3, c: -0.04)[0].direction,
                       "About 45 degrees counterclockwise from horizontal in key-spacing coordinates")
        XCTAssertEqual(rows(sigmaX: 0.4, sigmaY: 0.2)[0].direction, "Horizontal in key-spacing coordinates")
        for pair in [(0.3, 0.3), (0.301, 0.304)] {
            XCTAssertEqual(rows(sigmaX: pair.0, sigmaY: pair.1)[0].direction, "No distinct long-axis direction at this precision")
        }
        let layout = KeyboardTouchGeometry.layout(for: signature)
        let a = try XCTUnwrap(layout.key(.character("a")))
        let pitch = KeyboardTouchGeometry.pitch(for: a, layout: layout)
        XCTAssertNotEqual(pitch.width, pitch.height)
        let points = KeyboardTouchGeometry.ellipsePoints(for: key, key: a, layout: layout)
        XCTAssertEqual(points.count, 32)
        // The normalized sampled ellipse reproduces the full covariance, not just two sigmas.
        let xs = points.map { Double($0.x - a.frame.midX) / Double(pitch.width) }
        let ys = points.map { Double($0.y - a.frame.midY) / Double(pitch.height) }
        XCTAssertEqual(zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 } * 2 / 32, key.covarianceXY, accuracy: 0.000001)
    }

    func testLayoutTitlesDescribeAllSignatureDimensions() {
        for orientation in [KeyboardOrientation.portrait, .landscape] {
            for strip in [false, true] {
                for globe in [false, true] {
                    let signature = KeyboardLayoutSignature(KeyboardLayout(width: 392, orientation: orientation,
                        showsGlobe: globe, showsStrip: strip))
                    XCTAssertEqual(Presentation.layoutTitle(signature, locale: Locale(identifier: "en_US")),
                        "\(orientation == .portrait ? "Portrait" : "Landscape"), 392 pt, \(strip ? "suggestions" : "no suggestions"), \(globe ? "globe" : "no globe")")
                }
            }
        }
    }

    @MainActor
    func testAll56ScenesParseExactlyAndContextsNeverUseARealStore() throws {
        XCTAssertEqual(KeyboardDiagnosticsFixture.scenes.count, 56)
        XCTAssertEqual(Set(KeyboardDiagnosticsFixture.scenes.map(\.name)).count, 56)
        for scene in KeyboardDiagnosticsFixture.scenes {
            XCTAssertEqual(KeyboardDiagnosticsFixture.scene(named: scene.name), scene)
            let args = ["Typr", "--snap-state", scene.name]
            XCTAssertEqual(KeyboardDiagnosticsFixture.scene(arguments: args), scene)
            let context = try XCTUnwrap(KeyboardDiagnosticsFixture.context(arguments: args))
            XCTAssertEqual(context.page, scene.page); XCTAssertEqual(context.state, scene.state)
            XCTAssertEqual(context.now, KeyboardDiagnosticsFixture.now)
            XCTAssertEqual(context.learningEnabled, scene.state != .learningOff)
            let second = KeyboardDiagnosticsFixture.context(for: scene)
            XCTAssertEqual(context.snapshot.model, second.snapshot.model)
            XCTAssertEqual(context.snapshot.diagnostics, second.snapshot.diagnostics)
            let model = KeyboardDiagnosticsModel(fixture: context.snapshot, learningEnabled: context.learningEnabled)
            model.startObserving(); model.refresh(); model.resetLearning(); model.resetStatistics(); model.stopObserving()
            XCTAssertEqual(model.snapshot.model, context.snapshot.model)
            XCTAssertEqual(model.snapshot.diagnostics, context.snapshot.diagnostics)
            XCTAssertEqual(model.learningEnabled, context.learningEnabled)
            XCTAssertNil(model.resetProblem)
            for page in KeyboardDiagnosticsPage.allCases {
                let pushed = context.navigating(to: page)
                XCTAssertEqual(pushed.page, page)
                XCTAssertEqual(pushed.snapshot.model, context.snapshot.model)
                XCTAssertEqual(pushed.snapshot.diagnostics, context.snapshot.diagnostics)
                XCTAssertEqual(pushed.now, context.now)
            }
            for invalid in [scene.name + "-", scene.name + "x", scene.name.uppercased(), String(scene.name.dropLast())] {
                XCTAssertNil(KeyboardDiagnosticsFixture.scene(named: invalid), invalid)
            }
        }
        for name in ["settings-keyboard-diagnostic", "settings-keyboard-diagnostics-populated",
                     "settings-keyboard-diagnostics-unknown", "settings-keyboard-diagnostics-empty-speed",
                     "settings-keyboard-diagnostics-speed-empty-empty", "settings-keyboard-diagnostics-learning-off-learning",
                     "settings-keyboard", "settings-keyboard-learned-words"] {
            XCTAssertNil(KeyboardDiagnosticsFixture.scene(named: name))
        }
        for args in [[], ["--snap-state"], ["settings-keyboard-diagnostics"],
                     ["--other", "settings-keyboard-diagnostics"], ["--snap-state", "--other", "settings-keyboard-diagnostics"]] {
            XCTAssertNil(KeyboardDiagnosticsFixture.scene(arguments: args))
        }
    }

    @MainActor
    private func readout(_ state: KeyboardDiagnosticsFixture.State = .populated) -> Presentation.Readout {
        let context = KeyboardDiagnosticsFixture.context(for: .init(page: .overview, state: state))
        return Presentation.make(snapshot: context.snapshot, learningEnabled: context.learningEnabled,
                                 now: context.now, locale: Locale(identifier: "en_US"))
    }

    @MainActor
    private func withStore(_ body: (URL, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "KeyboardDiagnosticsPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        try body(directory, defaults)
    }
}
