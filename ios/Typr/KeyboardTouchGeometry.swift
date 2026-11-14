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

    static func title(_ signature: KeyboardLayoutSignature) -> String {
        let orientation = signature.orientation == "landscape" ? "Landscape" : "Portrait"
        return "\(orientation), \(signature.widthBucket) pt, \(signature.showsStrip ? "suggestions" : "no suggestions"), \(signature.showsGlobe ? "globe" : "no globe")"
    }
}
