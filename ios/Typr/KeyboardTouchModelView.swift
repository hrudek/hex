import SwiftUI

/// Stored letter-key geometry only; this view never receives or draws raw taps.
/// All numbers, labels and statuses come from `KeyboardDiagnosticsPresentation.Layout`.
struct KeyboardTouchModelView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let model: KeyboardDiagnosticsPresentation.Layout

    private var summary: PersonalTypingModel.LayoutSummary { model.summary }
    private var layout: KeyboardLayout { KeyboardTouchGeometry.layout(for: summary.signature) }
    private var letters: [KeyboardKey] {
        layout.keys.filter { $0.character?.allSatisfy(\.isLetter) == true }
    }
    private var top: CGFloat { letters.map(\.frame.minY).min() ?? 0 }
    private var keysHeight: CGFloat { (letters.map(\.frame.maxY).max() ?? layout.totalHeight) - top }
    /// One key spacing in layout units, taken from the first letter key.
    private var pitch: CGSize {
        letters.first.map { KeyboardTouchGeometry.pitch(for: $0, layout: layout) } ?? CGSize(width: 1, height: 1)
    }
    private var footerHeight: CGFloat { pitch.height + 12 }

    // Compatibility for the pre-redesign view; removed together with the old wrappers.
    init(summary: PersonalTypingModel.LayoutSummary) {
        model = KeyboardDiagnosticsPresentation.Layout(
            summary: summary, title: KeyboardDiagnosticsPresentation.layoutTitle(summary.signature),
            keys: KeyboardDiagnosticsPresentation.keyRows(summary))
    }

    init(model: KeyboardDiagnosticsPresentation.Layout) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            canvas
            scaleLabels
            DiagnosticsNote("Dot: model offset from the key centre. Line: shift from the key centre. Oval: the model's shape, not your measured tap scatter or an accuracy score.")
            DiagnosticsNote("With few examples, the offset leans towards the key centre and the oval towards a shape shared by all keys of this layout. At 20 examples, a key's own taps count as much as this default. With more than 20, they count more.")
            DiagnosticsNote("Solid outline: 20 or more tap examples. Dashed outline: fewer than 20. This isn't a quality rating or a switch that starts learning.")
            DiagnosticsDisclosure(title: "How to read the map") {
                DiagnosticsNote("Offsets are shown in key spacings: the distance from one key centre to the next. The scale bars show one key spacing across and down.")
                DiagnosticsNote("The map shows the saved model, not where you tap right now. Typr also adapts within a session; that short-term adjustment isn't saved and isn't shown.")
                DiagnosticsNote("Tap examples are counted without weights, up to 256 per key. Model estimates keep adapting; after 64 examples, means use a moving average.")
            }
            examplesByKey
            DiagnosticsDisclosure(title: "Per-key model estimates", openAtAccessibilitySizes: true) {
                ForEach(model.keys) { key in
                    estimateBlock(key)
                }
            }
            DiagnosticsDisclosure(title: "Model shape details") {
                DiagnosticsNote("These are approximate dimensions of the model oval in key spacings, not a confidence interval. Screen scaling can change the visible angle.")
                ForEach(model.keys) { key in
                    shapeBlock(key)
                }
            }
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        Canvas { context, size in
            let scale = size.width / layout.width
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: -top)
            let ink = contrast == .increased ? TyprTheme.textBase : TyprTheme.success
            let faint = contrast == .increased ? TyprTheme.textBase : TyprTheme.textFaint
            for key in letters {
                let stats = summary.keys.first { $0.letter == key.character }
                let sampled = (stats?.n ?? 0) > 0
                let calibrated = stats?.isCalibrated == true
                let color = calibrated ? ink : faint
                let cap = Path(roundedRect: key.frame, cornerRadius: 5)
                context.fill(cap, with: .color(TyprTheme.layer01))
                context.stroke(cap, with: .color(color.opacity(0.6)), lineWidth: 1)
                context.draw(Text(key.label).font(.system(size: 12)).foregroundColor(TyprTheme.textMuted),
                             at: CGPoint(x: key.frame.midX, y: key.frame.minY + 10))
                guard sampled, let stats else { continue }
                let center = KeyboardTouchGeometry.center(for: stats, key: key, layout: layout)
                var oval = Path()
                oval.addLines(KeyboardTouchGeometry.ellipsePoints(for: stats, key: key, layout: layout))
                oval.closeSubpath()
                let style = calibrated
                    ? StrokeStyle(lineWidth: 1.5)
                    : StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                context.stroke(oval, with: .color(color), style: style)
                var line = Path()
                line.move(to: CGPoint(x: key.frame.midX, y: key.frame.midY))
                line.addLine(to: center)
                context.stroke(line, with: .color(color), lineWidth: 1.5)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
                             with: .color(color))
            }
            // Scale bars: exactly one key spacing across and down, in the same units as the keys.
            let baseY = top + keysHeight + 8
            let bar = TyprTheme.textBase
            var across = Path()
            across.move(to: CGPoint(x: 8, y: baseY + pitch.height))
            across.addLine(to: CGPoint(x: 8 + pitch.width, y: baseY + pitch.height))
            context.stroke(across, with: .color(bar), lineWidth: 2)
            var down = Path()
            down.move(to: CGPoint(x: 8 + pitch.width + 32, y: baseY))
            down.addLine(to: CGPoint(x: 8 + pitch.width + 32, y: baseY + pitch.height))
            context.stroke(down, with: .color(bar), lineWidth: 2)
        }
        .aspectRatio(layout.width / max(1, keysHeight + footerHeight), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saved tap model. Tap examples and model estimates are listed below.")
    }

    private var scaleLabels: some View {
        Text("1 key spacing across, 1 key spacing down")
            .font(.footnote)
            .foregroundStyle(TyprTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    // MARK: Tap examples by key

    private var bars: [DiagnosticsBar] {
        model.keys.map { key in
            let count = KeyboardDiagnosticsPresentation.integer(key.n)
            return DiagnosticsBar(id: key.id, tick: key.id, category: key.id, value: key.n,
                                  accessibilityLabel: "\(key.id), \(count) tap examples")
        }
    }

    @ViewBuilder private var examplesByKey: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiagnosticsSubheading("Tap examples by key")
            if dynamicTypeSize.isAccessibilitySize {
                examplesTable
            } else {
                // Geometric rule: 26 labels need at least 320 pt; otherwise the open table replaces the chart.
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .leading, spacing: 12) {
                        DiagnosticsBarChart(
                            title: "Tap examples by key",
                            summary: Self.chartHelp,
                            xTitle: "Letter",
                            yTitle: "Tap examples (counted up to 256)",
                            bars: bars,
                            yTicks: [256, 192, 128, 64, 0],
                            reference: .init(value: 20, label: "20 examples"))
                        DiagnosticsNote(Self.chartHelp)
                        DiagnosticsDisclosure(title: "Tap examples by key") { examplesTable }
                    }
                    .frame(minWidth: 320)
                    examplesTable
                }
            }
        }
    }

    private static let chartHelp = "Counts stop increasing at 256 per key; they are not lifetime tap totals. The line marks 20 examples, where a key's own taps and the default count equally."

    private var examplesTable: some View {
        DiagnosticsTable(
            title: "Tap examples by key", firstColumn: "Letter", secondColumn: "Tap examples (counted up to 256)",
            rows: model.keys.map { key in
                DiagnosticsTableRow(
                    id: key.id, first: key.id, second: KeyboardDiagnosticsPresentation.integer(key.n),
                    accessibilityLabel: "\(key.id), \(KeyboardDiagnosticsPresentation.integer(key.n)) tap examples")
            })
    }

    // MARK: Per-key blocks

    private func estimateBlock(_ key: KeyboardDiagnosticsPresentation.KeyRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.id).font(.subheadline.weight(.semibold)).foregroundStyle(TyprTheme.textBase)
            detailLine("Tap examples (counted up to 256)", KeyboardDiagnosticsPresentation.integer(key.n))
            detailLine("Model offset", key.offsetText)
            detailLine("Status", key.status.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.accessibilityLabel())
    }

    private func shapeBlock(_ key: KeyboardDiagnosticsPresentation.KeyRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.id).font(.subheadline.weight(.semibold)).foregroundStyle(TyprTheme.textBase)
            detailLine("Model oval half-lengths", key.halfLengthsText)
            detailLine("Long-axis direction", key.directionText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.shapeAccessibilityLabel)
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.footnote).foregroundStyle(TyprTheme.textMuted)
            Text(value).font(.subheadline).foregroundStyle(TyprTheme.textBase).monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
