import Foundation
import XCTest
@testable import Typr

final class KeyboardDiagnosticsPresentationTests: XCTestCase {
    private typealias Presentation = KeyboardDiagnosticsPresentation

    func testSharesRetainZeroDenominatorsAndNeverImplyAccuracy() {
        XCTAssertEqual(Presentation.share(0, of: 0), "0 of 0")
        XCTAssertEqual(Presentation.share(2, of: 10), "2 of 10")
        XCTAssertEqual(Presentation.barShare(0, maximum: 0), 0)
        XCTAssertEqual(Presentation.barShare(2, maximum: 10), 0.2)
        XCTAssertEqual(Presentation.barShare(12, maximum: 10), 1)
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

    func testEveryCounterHasAPlainLanguageLabelAndEveryRefusalIsPresented() {
        for counter in KeyboardDiagnostics.Counter.allCases {
            let label = Presentation.label(counter)
            XCTAssertFalse(label.isEmpty, counter.rawValue)
            XCTAssertNotEqual(label, counter.rawValue)
        }
        let refusals: Set<KeyboardDiagnostics.Counter> = [.refusedLiteralValid, .refusedProtected,
            .refusedAmbiguous, .refusedIncompleteSearch, .refusedMissingResource, .refusedValidation,
            .refusedBelowMargin, .resourceLoading]
        XCTAssertEqual(Set(Presentation.refusals), refusals)
        XCTAssertTrue(Presentation.label(.refusedIncompleteSearch).contains("limit"))
        XCTAssertTrue(Presentation.label(.refusedProtected).contains("Protected"))
        XCTAssertEqual(Presentation.label(.storeWriteFailed), "Save failures or repairs")
        for source in TouchLabelSource.allCases { XCTAssertFalse(Presentation.sourceLabel(source).isEmpty) }
        for reason in TouchLabelRejection.allCases { XCTAssertFalse(Presentation.rejectionLabel(reason).isEmpty) }
    }

    func testHistogramLabelsMatchStoredBucketOrderAndEdges() {
        XCTAssertEqual(Presentation.histogramLabels,
                       ["<1 ms", "1–2 ms", "2–5 ms", "5–10 ms", "10–20 ms", "20–50 ms", "≥50 ms"])
        for (index, seconds) in [0.0, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05].enumerated() {
            var diagnostics = KeyboardDiagnostics()
            diagnostics.recordLatency(seconds, kind: .boundary)
            diagnostics.recordLatency(seconds, kind: .suggestion)
            XCTAssertEqual(diagnostics.boundaryMs.count, Presentation.histogramLabels.count)
            XCTAssertEqual(diagnostics.boundaryMs[index], 1)
            XCTAssertEqual(diagnostics.suggestionMs[index], 1)
            XCTAssertEqual(diagnostics.boundaryMs.reduce(0, +), 1)
        }
    }

    @MainActor
    func testUnavailableAndStaleStatesDoNotClaimCurrentFullAccess() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        func snapshot(saved: Date?, persistent: Bool = true) -> KeyboardLearningSnapshot {
            KeyboardLearningSnapshot(model: PersonalTypingModel.summarize(.init()), diagnostics: .init(now: now),
                learningFile: .init(bytes: nil, modifiedAt: nil),
                diagnosticsFile: .init(bytes: saved == nil ? nil : 100, modifiedAt: saved), isPersistent: persistent)
        }
        let empty = snapshot(saved: nil)
        XCTAssertNil(Presentation.updatedAt(empty))
        XCTAssertEqual(Presentation.availability(empty, now: now), "Full Access is off or the keyboard hasn't saved data yet.")
        XCTAssertNil(Presentation.availability(snapshot(saved: now), now: now))
        XCTAssertNotNil(Presentation.availability(snapshot(saved: now.addingTimeInterval(-86_401)), now: now))
        XCTAssertNotNil(Presentation.availability(snapshot(saved: now, persistent: false), now: now))
        XCTAssertEqual(Presentation.fileSize(nil), "Not saved yet")
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
        XCTAssertTrue(KeyboardDiagnosticsFixture.requested(arguments: ["Typr", "--snap-state", "settings-keyboard-diagnostics"]))
        for args in [[], ["--snap-state"], ["settings-keyboard-diagnostics"], ["--snap-state", "settings-keyboard"]] {
            XCTAssertFalse(KeyboardDiagnosticsFixture.requested(arguments: args))
        }
        let fixture = KeyboardDiagnosticsFixture.snapshot()
        let second = KeyboardDiagnosticsFixture.snapshot()
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
