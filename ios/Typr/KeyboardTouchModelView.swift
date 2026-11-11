import SwiftUI

/// Stored letter-key geometry only; this view never receives or draws raw taps.
struct KeyboardTouchModelView: View {
    let summary: PersonalTypingModel.LayoutSummary

    private var layout: KeyboardLayout { KeyboardTouchGeometry.layout(for: summary.signature) }
    private var letters: [KeyboardKey] {
        layout.keys.filter { $0.character?.allSatisfy(\.isLetter) == true }
    }
    private var top: CGFloat { letters.map(\.frame.minY).min() ?? 0 }
    private var height: CGFloat { (letters.map(\.frame.maxY).max() ?? layout.totalHeight) - top }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Canvas { context, size in
                let scale = size.width / layout.width
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: 0, y: -top)
                for key in letters {
                    let stats = summary.keys.first { $0.letter == key.character }
                    let calibrated = stats?.isCalibrated == true
                    let ink = calibrated ? TyprTheme.success : TyprTheme.textFaint
                    let cap = Path(roundedRect: key.frame, cornerRadius: 5)
                    context.fill(cap, with: .color(TyprTheme.layer01))
                    context.stroke(cap, with: .color(ink.opacity(0.6)), lineWidth: 1)
                    context.draw(Text(key.label).font(.system(size: 12)).foregroundColor(TyprTheme.textMuted),
                                 at: CGPoint(x: key.frame.midX, y: key.frame.minY + 10))
                    if let stats {
                        let center = KeyboardTouchGeometry.center(for: stats, key: key, layout: layout)
                        context.stroke(Path(ellipseIn: KeyboardTouchGeometry.ellipse(for: stats, key: key, layout: layout)),
                                       with: .color(ink.opacity(0.7)), lineWidth: 1)
                        var line = Path()
                        line.move(to: CGPoint(x: key.frame.midX, y: key.frame.midY))
                        line.addLine(to: center)
                        context.stroke(line, with: .color(ink), lineWidth: 1.5)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
                                     with: .color(ink))
                    }
                }
            }
            .aspectRatio(layout.width / max(1, height), contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stored touch offsets and spread. Per-key sample counts follow below.")
            Text("Line and dot: shrunk offset from key center. Ellipse: one sigma of spread, not an accuracy score. Gray outlined keys have fewer than 20 effective samples and are not used for calibration. Geometry uses the stored width bucket.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
            DisclosureGroup("Per-key effective sample counts") {
                // Include unsampled keys so the denominator of the model's coverage is visible.
                ForEach(letters, id: \.kind) { key in
                    HStack {
                        Text(key.label)
                        Spacer()
                        Text((summary.keys.first { $0.letter == key.character }?.n ?? 0).formatted())
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.vertical, 4)
                }
                Text("Effective counts are capped at 256 per key; they are not lifetime tap totals.")
                    .font(.footnote).foregroundStyle(TyprTheme.textMuted)
            }
        }
    }
}
