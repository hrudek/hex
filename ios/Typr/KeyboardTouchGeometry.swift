import Foundation
import CoreGraphics

/// Reconstruct bucket geometry, not hit targets. The personal model already shrinks offsets and sigma.
nonisolated enum KeyboardTouchGeometry {
    static func layout(for signature: KeyboardLayoutSignature) -> KeyboardLayout {
        KeyboardLayout(width: CGFloat(signature.widthBucket),
            orientation: signature.orientation == "landscape" ? .landscape : .portrait,
            layer: .letters, showsGlobe: signature.showsGlobe, showsStrip: signature.showsStrip)
    }

    static func center(for summary: PersonalTypingModel.KeySummary, key: KeyboardKey,
                       layout: KeyboardLayout) -> CGPoint {
        CGPoint(x: key.frame.midX + CGFloat(summary.offsetX) * (key.frame.width + layout.metrics.gap),
                y: key.frame.midY + CGFloat(summary.offsetY) * (key.frame.height + layout.metrics.rowGap))
    }

    // Pitch-to-point display adapted from AVGVSTVS96/iikb
    // Packages/KeyboardModules/Sources/KeyboardCore/Correction/Aim.swift (MIT).
    static func ellipse(for summary: PersonalTypingModel.KeySummary, key: KeyboardKey,
                        layout: KeyboardLayout) -> CGRect {
        let center = center(for: summary, key: key, layout: layout)
        let rx = CGFloat(summary.sigmaX) * (key.frame.width + layout.metrics.gap)
        let ry = CGFloat(summary.sigmaY) * (key.frame.height + layout.metrics.rowGap)
        return CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
    }

    /// Cholesky maps a unit circle to the full covariance ellipse (fixed 32 segments).
    static func ellipsePoints(for summary: PersonalTypingModel.KeySummary, key: KeyboardKey,
                              layout: KeyboardLayout) -> [CGPoint] {
        let center = center(for: summary, key: key, layout: layout)
        let l11 = summary.sigmaX
        let l21 = summary.covarianceXY / l11
        let l22 = sqrt(max(0, summary.sigmaY * summary.sigmaY - l21 * l21))
        let width = Double(key.frame.width + layout.metrics.gap)
        let height = Double(key.frame.height + layout.metrics.rowGap)
        return (0..<32).map { i in
            let angle = Double(i) * 2 * Double.pi / 32
            return CGPoint(x: center.x + width * l11 * cos(angle),
                           y: center.y + height * (l21 * cos(angle) + l22 * sin(angle)))
        }
    }

    struct Oval: Equatable, Sendable {
        let major: Double
        let minor: Double
        /// Positive clockwise, in normalized key-spacing coordinates (not screen points).
        let angleDegrees: Double
    }

    static func pitch(for key: KeyboardKey, layout: KeyboardLayout) -> CGSize {
        CGSize(width: key.frame.width + layout.metrics.gap,
               height: key.frame.height + layout.metrics.rowGap)
    }

    /// Eigenaxes of the already tempered summary covariance. Does not modify the model.
    static func oval(for summary: PersonalTypingModel.KeySummary) -> Oval {
        let a = summary.sigmaX * summary.sigmaX
        let b = summary.sigmaY * summary.sigmaY
        let c = summary.covarianceXY
        let separation = hypot(a - b, 2 * c)
        return Oval(major: sqrt(max(0, (a + b + separation) / 2)),
                    minor: sqrt(max(0, (a + b - separation) / 2)),
                    angleDegrees: atan2(2 * c, a - b) * 90 / .pi)
    }

    // Compatibility title for the pre-redesign canvas; new pages use layoutTitle(_:locale:).
    static func title(_ signature: KeyboardLayoutSignature) -> String {
        let orientation = signature.orientation == "landscape" ? "Landscape" : "Portrait"
        return "\(orientation), \(signature.widthBucket) pt, \(signature.showsStrip ? "suggestions" : "no suggestions"), \(signature.showsGlobe ? "globe" : "no globe")"
    }
}
