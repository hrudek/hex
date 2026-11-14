import Accessibility
import SwiftUI
import UIKit
import XCTest
@testable import Typr

final class KeyboardDiagnosticsLayoutTests: XCTestCase {
    private typealias Presentation = KeyboardDiagnosticsPresentation

    @MainActor
    func testAllScenesAndFocusedReflowMatrixHave136UniqueHostings() {
        let focused: Set<KeyboardDiagnosticsFixture.State> = [.populated, .inconsistent, .unsampled, .unreadable]
        let sizes: [DynamicTypeSize] = [.large, .accessibility1, .accessibility5]
        var rendered = Set<String>()
        func render(_ scene: KeyboardDiagnosticsFixture.Scene, width: Int, sizeIndex: Int) {
            let key = "\(scene.name)/\(width)/\(sizeIndex)"
            guard rendered.insert(key).inserted else { return }
            autoreleasepool {
                let context = KeyboardDiagnosticsFixture.context(for: scene)
                let host = UIHostingController(rootView:
                    KeyboardDiagnosticsView(page: scene.page, context: context)
                        .environment(\.locale, Locale(identifier: "en_US"))
                        .dynamicTypeSize(sizes[sizeIndex]))
                let size = host.sizeThatFits(in: CGSize(width: CGFloat(width), height: 10_000))
                XCTAssertTrue(size.width.isFinite, key)
                XCTAssertTrue(size.height.isFinite, key)
                XCTAssertEqual(size.width, CGFloat(width), accuracy: 0.5, key)
                XCTAssertGreaterThan(size.height, 0, key)
            }
        }
        for scene in KeyboardDiagnosticsFixture.scenes {
            render(scene, width: 320, sizeIndex: 0)
        }
        XCTAssertEqual(rendered.count, 56)
        for scene in KeyboardDiagnosticsFixture.scenes where focused.contains(scene.state) {
            for width in [280, 320] {
                for index in sizes.indices { render(scene, width: width, sizeIndex: index) }
            }
        }
        XCTAssertEqual(rendered.count, 136)
    }

    @MainActor
    func testLatencyChartsAndTheirActualTablesShareOrderedRawDataAndMarking() throws {
        for state in [KeyboardDiagnosticsFixture.State.populated, .small, .inconsistent, .zero] {
            let statistics = try XCTUnwrap(readout(state).statistics)
            for (title, tableTitle, latency) in [
                ("Word check time", "Word check measurements", statistics.wordCheckTime),
                ("Suggestion search time", "Suggestion search measurements", statistics.suggestionTime)
            ] {
                let chart = KeyboardDiagnosticsSpeedView.chart(title: title, latency: latency)
                XCTAssertEqual(chart.title, title)
                XCTAssertEqual(chart.xTitle, "Duration class (ms)")
                XCTAssertEqual(chart.yTitle, "Measurements")
                XCTAssertEqual(chart.bars.map(\.id), (0..<7).map(String.init))
                XCTAssertEqual(chart.bars.map(\.category), latency.buckets.map(\.label))
                XCTAssertEqual(chart.bars.map(\.tick), latency.buckets.map(\.tick))
                XCTAssertEqual(chart.bars.map(\.value), latency.buckets.map(\.count))
                XCTAssertEqual(chart.bars.filter(\.isMarked).map(\.id), latency.halfBucket.map { [String($0.id)] } ?? [])
                let disclosure = KeyboardDiagnosticsSpeedView.measurementsTable(title: tableTitle, latency: latency)
                XCTAssertEqual(disclosure.title, tableTitle)
                let table = disclosure.content.table
                XCTAssertEqual(table.firstColumn, "Duration class")
                XCTAssertEqual(table.secondColumn, "Measurements")
                XCTAssertEqual(table.rows.map(\.first), latency.buckets.map(\.label))
                XCTAssertEqual(table.rows.map(\.accessibilityLabel), chart.bars.map(\.accessibilityLabel))
                try assertDescriptor(chart)
                let descriptor = chart.chartDescriptor.makeChartDescriptor()
                let yAxis = try XCTUnwrap(descriptor.yAxis)
                XCTAssertEqual(yAxis.range, 0...Double(max(1, latency.buckets.map(\.count).max() ?? 1)))
            }
        }
    }

    @MainActor
    func testTapExamplesChartAndTableIncludeEveryLetterAndNeverMergeLayouts() throws {
        let learning = try XCTUnwrap(readout(.unsampled).learning)
        for layout in learning.layouts {
            let view = KeyboardTouchModelView(model: layout)
            let chart = view.examplesChart
            XCTAssertEqual(chart.title, "Tap examples by key")
            XCTAssertEqual(chart.xTitle, "Letter")
            XCTAssertEqual(chart.yTitle, "Tap examples (counted up to 256)")
            XCTAssertEqual(chart.bars.map(\.id), "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))
            XCTAssertEqual(chart.bars.map(\.value), layout.keys.map(\.n))
            XCTAssertEqual(Array(chart.bars.prefix(5).map(\.value)), [0, 19, 20, 256, 0])
            XCTAssertEqual(chart.yTicks, [256, 192, 128, 64, 0])
            XCTAssertEqual(chart.reference, .init(value: 20, label: "20 examples"))
            XCTAssertTrue(chart.bars.allSatisfy { !$0.isMarked })
            XCTAssertEqual(view.examplesTable.rows.map(\.first), chart.bars.map(\.category))
            XCTAssertEqual(view.examplesTable.rows.map(\.accessibilityLabel), chart.bars.map(\.accessibilityLabel))
            try assertDescriptor(chart)
            XCTAssertEqual(chart.chartDescriptor.makeChartDescriptor().yAxis?.range, 0...256)
        }
    }

    @MainActor
    func testFallbackAndDisclosureDecisionsUseActualComponentConfiguration() throws {
        let populated = try XCTUnwrap(readout(.populated).statistics)
        let empty = try XCTUnwrap(readout(.zero).statistics)
        let layout = try XCTUnwrap(readout(.unsampled).learning?.layouts.first)
        let touch = KeyboardTouchModelView(model: layout)
        let table = KeyboardDiagnosticsSpeedView.measurementsTable(title: "Word check measurements", latency: populated.wordCheckTime)
        for size in [DynamicTypeSize.large, .accessibility1, .accessibility5] {
            let ax = size.isAccessibilitySize
            XCTAssertEqual(KeyboardDiagnosticsSpeedView.showsChart(latency: populated.wordCheckTime, at: size), !ax)
            XCTAssertFalse(KeyboardDiagnosticsSpeedView.showsChart(latency: empty.wordCheckTime, at: size))
            XCTAssertEqual(table.isExpanded(at: size), ax)
            XCTAssertEqual(touch.perKeyEstimates.isExpanded(at: size), ax)
            XCTAssertFalse(touch.modelShapeDetails.isExpanded(at: size))
            XCTAssertTrue(touch.modelShapeDetails.isExpanded(userChoice: true, at: size))
            XCTAssertFalse(table.isExpanded(userChoice: false, at: size))
            XCTAssertEqual(KeyboardTouchModelView.usesExamplesTable(at: size, width: 320), ax)
            XCTAssertTrue(KeyboardTouchModelView.usesExamplesTable(at: size, width: 280))
        }
        XCTAssertEqual(KeyboardTouchModelView.minimumExamplesChartWidth, 320)
        XCTAssertTrue(KeyboardTouchModelView.usesExamplesTable(at: .large, width: 319))
        XCTAssertFalse(KeyboardTouchModelView.usesExamplesTable(at: .large, width: 321))
    }

    @MainActor
    func testMethodComponentsRenderBothAbsoluteCountsWithExplicitLabels() throws {
        for scenario in 0..<3 {
            var diagnostics = KeyboardDiagnostics(now: KeyboardDiagnosticsFixture.now)
            // 0: u > x; 1: u > 0, x = 0; 2: u <= x but the total partition is invalid.
            let hasReplacements = scenario != 1
            diagnostics.increment(.boundaries, by: scenario == 2 ? 20 : hasReplacements ? 6 : 0)
            diagnostics.increment(.autoSpatialSameLength, by: hasReplacements ? 1 : 0)
            diagnostics.increment(.autoSpatialEdit, by: hasReplacements ? 1 : 0)
            diagnostics.increment(.autoSpellingFallback, by: hasReplacements ? 2 : 0)
            diagnostics.increment(.autoRule, by: hasReplacements ? 2 : 0)
            let undos = scenario == 0 ? 3 : 1
            for counter in [Presentation.Counter.undoSpatial, .undoSpelling, .undoRule] {
                diagnostics.increment(counter, by: undos)
            }
            let statistics = try self.statistics(diagnostics)
            XCTAssertEqual(statistics.methods.map(\.id), [.undoSpatial, .undoSpelling, .undoRule])
            for method in statistics.methods {
                let component = DiagnosticsMethodFeedback(method: method)
                let row = component.comparisonRow
                XCTAssertEqual(row.comparison.status, .incomparable)
                XCTAssertEqual(row.absoluteRows.map(\.label), ["Automatic replacements", "Recorded undos"])
                XCTAssertEqual(row.absoluteRows.map(\.value),
                               [Presentation.integer(hasReplacements ? 2 : 0), Presentation.integer(undos)])
                XCTAssertEqual(row.label, "Undone")
                XCTAssertEqual(row.emptyText, DiagnosticsCopy.noAutomatic)
            }
        }
    }

    @MainActor
    func testOverviewComponentsKeepNonzeroDecisionsAtZeroPopulationWithoutRatiosOrTracks() throws {
        var diagnostics = KeyboardDiagnostics(now: KeyboardDiagnosticsFixture.now)
        diagnostics.increment(.autoRule, by: 2)
        diagnostics.increment(.unchanged, by: 3)
        let statistics = try self.statistics(diagnostics)
        let decisions = KeyboardDiagnosticsView.recordedDecisions(statistics)
        XCTAssertEqual(decisions.heading, "Recorded decisions")
        XCTAssertEqual(decisions.partition.population, 0)
        XCTAssertEqual(decisions.partition.rows.map(\.count), [0, 0, 0, 2, 3])
        XCTAssertFalse(decisions.partition.canShowParts)
        XCTAssertEqual(decisions.partition.inconsistencyText(locale: Locale(identifier: "en_US")),
                       "These counts add up to 5, not 0. Some counters may be incomplete.")
        let automatic = KeyboardDiagnosticsView.automaticComparison(statistics)
        XCTAssertEqual(automatic.comparison.status, .incomparable)
        XCTAssertEqual(automatic.absoluteRows.map(\.label), ["Automatic replacements"])
        XCTAssertEqual(automatic.absoluteRows.map(\.value), ["2"])
        let empty = try self.statistics(KeyboardDiagnostics(now: KeyboardDiagnosticsFixture.now))
        XCTAssertEqual(KeyboardDiagnosticsView.automaticComparison(empty).comparison.status, .empty)
        XCTAssertTrue(KeyboardDiagnosticsView.automaticComparison(empty).absoluteRows.isEmpty)
        let emptyDecisions = KeyboardDiagnosticsView.recordedDecisions(empty).partition
        XCTAssertEqual(emptyDecisions.sum, 0)
        XCTAssertFalse(emptyDecisions.canShowParts)
        XCTAssertNil(emptyDecisions.inconsistencyText())
    }

    @MainActor
    func testChartHeightsRemainProportionalForVeryUnequalCounts() throws {
        let latency = Presentation.latency(buckets: [1, 0, 0, 0, 0, 0, Int(Int32.max)], referenceCount: 0)
        let chart = KeyboardDiagnosticsSpeedView.chart(title: "Word check time", latency: latency)
        XCTAssertEqual(chart.barHeight(for: 0), 0)
        XCTAssertEqual(chart.barHeight(for: Int(Int32.max)), 140)
        XCTAssertEqual(chart.barHeight(for: 1), 140 / CGFloat(Int32.max), accuracy: 0.000000000001)
        XCTAssertLessThan(chart.barHeight(for: 1), 1)
        try assertDescriptor(chart)
        // Hosting is a sizing check, not visual evidence for axes, contour or dashed line.
        for width in [280, 320] {
            let host = UIHostingController(rootView: chart)
            let size = host.sizeThatFits(in: CGSize(width: CGFloat(width), height: 10_000))
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(size.width, CGFloat(width) + 0.5)
        }
    }

    @MainActor
    func testDescriptorUpdateReplacesStaleCategoriesAndCounts() throws {
        let statistics = try XCTUnwrap(readout(.populated).statistics)
        let original = KeyboardDiagnosticsSpeedView.chart(title: "Word check time", latency: statistics.wordCheckTime)
        let descriptor = original.chartDescriptor.makeChartDescriptor()
        let layout = try XCTUnwrap(readout(.unsampled).learning?.layouts.first)
        let updated = KeyboardTouchModelView(model: layout).examplesChart
        updated.chartDescriptor.updateChartDescriptor(descriptor)
        XCTAssertEqual(descriptor.title, updated.title)
        XCTAssertEqual(descriptor.summary, updated.summary)
        let xAxis = try XCTUnwrap(descriptor.xAxis as? AXCategoricalDataAxisDescriptor)
        XCTAssertEqual(xAxis.categoryOrder, updated.bars.map(\.category))
        XCTAssertEqual(descriptor.yAxis?.range, 0...256)
        XCTAssertEqual(descriptor.series.first?.dataPoints.count, 26)
        for (point, bar) in zip(try XCTUnwrap(descriptor.series.first).dataPoints, updated.bars) {
            XCTAssertEqual(point.label, bar.accessibilityLabel)
            XCTAssertEqual(try XCTUnwrap(point.yValue).__number, Double(bar.value))
        }
    }

    @MainActor
    func testSharedRowsAndOpenTablesGrowAndStayWithinCompactWidth() throws {
        let statistics = try XCTUnwrap(readout(.inconsistent).statistics)
        func rowSize(_ size: DynamicTypeSize) -> CGSize {
            let host = UIHostingController(rootView:
                DiagnosticsValueRow(label: "Estimated upper bound for encoded next-word data", value: "2,147,483,647 bytes")
                    .dynamicTypeSize(size))
            return host.sizeThatFits(in: CGSize(width: 280, height: 10_000))
        }
        let regular = rowSize(.large)
        let accessible = rowSize(.accessibility5)
        XCTAssertGreaterThan(accessible.height, regular.height)
        XCTAssertLessThanOrEqual(accessible.width, 280.5)
        let host = UIHostingController(rootView:
            DiagnosticsLatencyTable(latency: statistics.wordCheckTime).dynamicTypeSize(.accessibility5))
        let table = host.sizeThatFits(in: CGSize(width: 280, height: 10_000))
        XCTAssertGreaterThan(table.height, 0)
        XCTAssertLessThanOrEqual(table.width, 280.5)
    }

    @MainActor
    private func assertDescriptor(_ chart: DiagnosticsBarChart, file: StaticString = #filePath, line: UInt = #line) throws {
        let descriptor = chart.chartDescriptor.makeChartDescriptor()
        XCTAssertEqual(descriptor.title, chart.title, file: file, line: line)
        XCTAssertEqual(descriptor.summary, chart.summary, file: file, line: line)
        let xAxis = try XCTUnwrap(descriptor.xAxis as? AXCategoricalDataAxisDescriptor, file: file, line: line)
        XCTAssertEqual(xAxis.title, chart.xTitle, file: file, line: line)
        XCTAssertEqual(xAxis.categoryOrder, chart.bars.map(\.category), file: file, line: line)
        let yAxis = try XCTUnwrap(descriptor.yAxis, file: file, line: line)
        XCTAssertEqual(yAxis.title, chart.yTitle, file: file, line: line)
        XCTAssertEqual(descriptor.series.count, 1, file: file, line: line)
        let series = try XCTUnwrap(descriptor.series.first, file: file, line: line)
        XCTAssertEqual(series.name, chart.title, file: file, line: line)
        XCTAssertFalse(series.isContinuous, file: file, line: line)
        XCTAssertEqual(series.dataPoints.count, chart.bars.count, file: file, line: line)
        for (point, bar) in zip(series.dataPoints, chart.bars) {
            XCTAssertEqual(point.xValue.__category, bar.category, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(point.yValue, file: file, line: line).__number, Double(bar.value), file: file, line: line)
            XCTAssertEqual(point.label, bar.accessibilityLabel, file: file, line: line)
        }
    }

    @MainActor
    private func statistics(_ diagnostics: KeyboardDiagnostics) throws -> Presentation.Statistics {
        let base = KeyboardDiagnosticsFixture.snapshot(state: .populated)
        let readout = Presentation.make(snapshot: .init(model: base.model, diagnostics: diagnostics,
            learningFile: base.learningFile, diagnosticsFile: base.diagnosticsFile, isPersistent: true),
            learningEnabled: true, now: KeyboardDiagnosticsFixture.now)
        return try XCTUnwrap(readout.statistics)
    }

    @MainActor
    private func readout(_ state: KeyboardDiagnosticsFixture.State) -> Presentation.Readout {
        let context = KeyboardDiagnosticsFixture.context(for: .init(page: .overview, state: state))
        return Presentation.make(snapshot: context.snapshot, learningEnabled: context.learningEnabled,
                                 now: context.now, locale: Locale(identifier: "en_US"))
    }
}
