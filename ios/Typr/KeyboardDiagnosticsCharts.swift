import SwiftUI
import Accessibility

/// One bar of a diagnostics chart. All numbers and labels are prepared by `KeyboardDiagnosticsPresentation`.
struct DiagnosticsBar: Identifiable, Equatable {
    let id: String
    /// Short text under the bar.
    let tick: String
    /// Full category name used by the audio graph.
    let category: String
    let value: Int
    /// Spoken label of the data point, for example `<class>, <count> measurements`.
    let accessibilityLabel: String
    /// Drawn with an outline and described in text, never by colour alone.
    var isMarked = false
}

/// Bar chart drawn with SwiftUI shapes so that axis titles, the outlined bar and the dashed reference
/// line stay under our control. The audio graph comes from the Accessibility framework.
struct DiagnosticsBarChart: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let summary: String
    let xTitle: String
    let yTitle: String
    let bars: [DiagnosticsBar]
    /// Evenly spaced y labels from top to bottom, for example `[256, 128, 0]`. The first value is the axis maximum.
    let yTicks: [Int]
    var reference: Reference?

    struct Reference: Equatable {
        let value: Int
        let label: String
    }

    init(title: String, summary: String, xTitle: String, yTitle: String,
         bars: [DiagnosticsBar], yTicks: [Int], reference: Reference? = nil) {
        self.title = title
        self.summary = summary
        self.xTitle = xTitle
        self.yTitle = yTitle
        self.bars = bars
        self.yTicks = yTicks
        self.reference = reference
    }

    private let plotHeight: CGFloat = 140
    private var yMax: Int { max(1, yTicks.first ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(yTitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                yLabels
                VStack(alignment: .leading, spacing: 4) {
                    plot
                    xLabels
                }
            }
            Text(xTitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityChartDescriptor(chartDescriptor)
    }

    var chartDescriptor: DiagnosticsChartDescriptor {
        DiagnosticsChartDescriptor(title: title, summary: summary, xTitle: xTitle, yTitle: yTitle,
                                   bars: bars, yMax: Double(yMax))
    }

    private var yLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Array(yTicks.enumerated()), id: \.offset) { index, tick in
                if index > 0 { Spacer(minLength: 0) }
                Text(KeyboardDiagnosticsPresentation.integer(tick))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(TyprTheme.textMuted)
                    .fixedSize()
            }
        }
        .frame(height: plotHeight)
    }

    private var plot: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                ForEach(Array(yTicks.enumerated()), id: \.offset) { index, _ in
                    if index > 0 { Spacer(minLength: 0) }
                    Rectangle().fill(TyprTheme.borderWeak).frame(height: 1)
                }
            }
            HStack(alignment: .bottom, spacing: bars.count > 12 ? 2 : 6) {
                ForEach(bars) { bar in
                    barShape(bar)
                }
            }
            if let reference {
                referenceLine(reference)
            }
        }
        .frame(height: plotHeight)
        .accessibilityHidden(true)
    }

    /// Exact proportional height: tiny positive counts must not be inflated to a minimum visible bar.
    func barHeight(for value: Int) -> CGFloat {
        plotHeight * CGFloat(min(1, max(0, Double(value) / Double(yMax))))
    }

    private func barShape(_ bar: DiagnosticsBar) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(TyprTheme.agentBlue)
                .frame(height: barHeight(for: bar.value))
                .overlay {
                    if bar.isMarked {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(TyprTheme.textBase, lineWidth: contrast == .increased ? 3 : 2)
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func referenceLine(_ reference: Reference) -> some View {
        let fraction = min(1, max(0, Double(reference.value) / Double(yMax)))
        return VStack(alignment: .leading, spacing: 0) {
            Text(reference.label)
                .font(.caption2)
                .foregroundStyle(TyprTheme.textBase)
                .fixedSize()
            DashedLine()
                .stroke(TyprTheme.textBase, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
        }
        .offset(y: -plotHeight * CGFloat(fraction))
    }

    private var xLabels: some View {
        HStack(alignment: .top, spacing: bars.count > 12 ? 2 : 6) {
            ForEach(bars) { bar in
                Text(bar.tick)
                    .font(.caption2)
                    .foregroundStyle(TyprTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Horizontal line; dashed when stroked so the reference is distinguishable without colour.
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Audio graph for a bar chart: ordered categories on x, counts on y.
struct DiagnosticsChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let xTitle: String
    let yTitle: String
    let bars: [DiagnosticsBar]
    let yMax: Double

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let updated = makeChartDescriptor()
        descriptor.title = updated.title
        descriptor.summary = updated.summary
        descriptor.xAxis = updated.xAxis
        descriptor.yAxis = updated.yAxis
        descriptor.series = updated.series
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: bars.map { $0.category })
        let yAxis = AXNumericDataAxisDescriptor(
            title: yTitle, range: 0...yMax, gridlinePositions: [],
            valueDescriptionProvider: { KeyboardDiagnosticsPresentation.integer(Int($0)) })
        let points = bars.map { AXDataPoint(x: $0.category, y: Double($0.value), additionalValues: [], label: $0.accessibilityLabel) }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false, dataPoints: points)
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}
