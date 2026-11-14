import SwiftUI

/// Content of the "Speed" detail page: two measurement groups, each with a summary,
/// a chart (normal text sizes) and a complete table that is always reachable.
struct KeyboardDiagnosticsSpeedView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let readout: KeyboardDiagnosticsPresentation.Readout

    private typealias Presentation = KeyboardDiagnosticsPresentation

    var body: some View {
        if let statistics = readout.statistics {
            DiagnosticsSection {
                DiagnosticsNote("Measured inside the keyboard on this iPhone. This is not typing speed and not the time until text appears on screen. Duration classes get wider to the right.")
                DiagnosticsDisclosure(title: "What is measured") {
                    DiagnosticsNote("Word check time covers the decision and its bookkeeping at a word boundary. It doesn't include inserting the result into the text field or drawing it on screen.")
                    DiagnosticsNote("Suggestion search time covers counted searches. Depending on the search path, it can include finding completions and building rankings. Searches that reuse an earlier result aren't counted. The two timings don't cover identical work.")
                }
            }
            group(title: "Word check time", tableTitle: "Word check measurements",
                  latency: statistics.wordCheckTime, counterLabel: "Recorded word checks")
            group(title: "Suggestion search time", tableTitle: "Suggestion search measurements",
                  latency: statistics.suggestionTime, counterLabel: "Recorded suggestion searches")
        } else {
            DiagnosticsSection {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope)
            }
        }
    }

    private func group(title: String, tableTitle: String, latency: Presentation.Latency,
                       counterLabel: String) -> some View {
        DiagnosticsSection {
            DiagnosticsLatencySummary(title: title, latency: latency)
            if let highest = latency.highestBucket {
                DiagnosticsNote("Highest recorded duration class: \(highest.label).")
            }
            if let text = latency.discrepancyText() {
                DiagnosticsValueRow(label: counterLabel, value: Presentation.integer(latency.referenceCount))
                DiagnosticsNote(text)
            }
            if Self.showsChart(latency: latency, at: dynamicTypeSize) {
                Self.chart(title: title, latency: latency)
                DiagnosticsNote(Self.chartHelp)
            }
            Self.measurementsTable(title: tableTitle, latency: latency)
        }
    }

    private static let chartHelp = "Outlined bar: the class used for the half-of-measurements summary. Bars count measurements, not time spent. Each chart has its own count scale."

    static func showsChart(latency: KeyboardDiagnosticsPresentation.Latency, at size: DynamicTypeSize) -> Bool {
        latency.n > 0 && !size.isAccessibilitySize
    }

    static func measurementsTable(title: String, latency: KeyboardDiagnosticsPresentation.Latency)
        -> DiagnosticsDisclosure<DiagnosticsLatencyTable> {
        DiagnosticsDisclosure(title: title, openAtAccessibilitySizes: true) {
            DiagnosticsLatencyTable(latency: latency)
        }
    }

    static func chart(title: String, latency: KeyboardDiagnosticsPresentation.Latency) -> DiagnosticsBarChart {
        DiagnosticsBarChart(
            title: title, summary: chartHelp, xTitle: "Duration class (ms)", yTitle: "Measurements",
            bars: bars(latency), yTicks: [max(1, latency.buckets.map(\.count).max() ?? 1), 0])
    }

    private static func bars(_ latency: Presentation.Latency) -> [DiagnosticsBar] {
        latency.buckets.map { bucket in
            let count = Presentation.integer(bucket.count)
            let marked = bucket.id == latency.halfBucket?.id
            return DiagnosticsBar(
                id: String(bucket.id), tick: bucket.tick, category: bucket.label, value: bucket.count,
                accessibilityLabel: "\(bucket.label), \(count) measurements"
                    + (marked ? ". Class used for the half-of-measurements summary." : ""),
                isMarked: marked)
        }
    }
}
