import SwiftUI
import UIKit

/// The full keyboard's colours, light and dark, calibrated against Apple's iOS 26
/// Liquid Glass system keyboard. Dark is chosen by the field's `keyboardAppearance`
/// first, then the host's interface style.
struct FullKeyboardPalette: Equatable {
    let isDark: Bool

    static func isDark(appearance: UIKeyboardAppearance?, traits: UITraitCollection) -> Bool {
        switch appearance {
        case .dark?:
            return true
        case .light?:
            return false
        default:
            return traits.userInterfaceStyle == .dark
        }
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Stand-in for the system Liquid Glass platter, used only in standalone snapshot scenes.
    var backdrop: UIColor { isDark ? Self.rgb(0x17181A) : Self.rgb(0xDFE1E6) }

    var textBase: UIColor { isDark ? .white : .black }
    var textMuted: UIColor { isDark ? UIColor(white: 1, alpha: 0.56) : Self.rgb(0x525763) }

    /// Unified iOS 26 Liquid Glass keycap fill across letters and modifiers:
    /// `white @ 0.16` composites to `(61,61,63)` on dark `(23,24,26)` and `(94,94,96)` on dark-field `(64,64,66)`.
    var keyFill: UIColor { isDark ? UIColor(white: 1, alpha: 0.16) : .white }
    var keyPressedFill: UIColor { isDark ? UIColor(white: 1, alpha: 0.28) : Self.rgb(0xD8DCE4) }
    /// Secondary fill for non-key chips and the recording panel's cancel pill.
    var functionFill: UIColor { isDark ? UIColor(white: 1, alpha: 0.09) : UIColor(white: 0, alpha: 0.065) }
    var keyShadow: UIColor { .clear }

    /// Opaque so balloons and menus float cleanly over the strip and neighbouring keys.
    var popupFill: UIColor { isDark ? Self.rgb(0x4E5056) : .white }
    var popupBorder: UIColor { isDark ? UIColor(white: 1, alpha: 0.14) : UIColor(white: 0, alpha: 0.08) }
    var popupShadow: UIColor { UIColor(white: 0, alpha: isDark ? 0.42 : 0.18) }

    var chipFill: UIColor { isDark ? UIColor(white: 1, alpha: 0.11) : UIColor(white: 0, alpha: 0.065) }
    var wellFill: UIColor { isDark ? UIColor(white: 1, alpha: 0.055) : UIColor(white: 0, alpha: 0.045) }
    var separator: UIColor { isDark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.10) }
    var selectFill: UIColor { isDark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 0, alpha: 0.075) }
    var selectText: UIColor { textBase }

    /// Apple system keyboard action blue (`#007AFF`).
    var actionFill: UIColor { Self.rgb(0x007AFF) }
    var actionPressedFill: UIColor { Self.rgb(0x0062CC) }
    var warmCore: UIColor { Self.rgb(0xFF9500) }
    var recordingDot: UIColor { Self.rgb(0xE54D42) }

    static let cornerRadius: CGFloat = 8.5
}

/// The same outlined Typr wordmark used by SwiftUI and the app icon, optically
/// centered like the icon because the keyboard key centers it on the keycap.
enum TyprMarkPath {
    static func draw(in context: CGContext, rect: CGRect, color: UIColor, coreColor: UIColor?) {
        context.saveGState()
        context.setFillColor((coreColor ?? color).cgColor)
        context.addPath(TyprWordmark(opticallyCentered: true).path(in: rect).cgPath)
        context.fillPath()
        context.restoreGState()
    }
}

/// Drawing-only geometry. Never used for hit testing or gesture thresholds.
struct JoinedSpaceKeycap {
    let space: CGRect
    let typr: CGRect
    let radius: CGFloat

    init?(layout: KeyboardLayout) {
        guard let space = layout.key(.space), let typr = layout.key(.typr),
              abs(typr.frame.minX - space.frame.maxX - layout.metrics.gap) < 0.01 else { return nil }
        self.space = space.frame
        self.typr = typr.frame
        radius = layout.metrics.cornerRadius
    }

    var frame: CGRect { space.union(typr) }

    /// A soft sloping seam, entirely decorative and independent of the touch boundary.
    static func seam(cap: CGRect, radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cap.minX + 2 * radius, y: cap.minY))
        path.addCurve(
            to: CGPoint(x: cap.minX, y: cap.maxY),
            controlPoint1: CGPoint(x: cap.minX, y: cap.minY),
            controlPoint2: CGPoint(x: cap.minX + 2 * radius, y: cap.maxY)
        )
        return path
    }

    static func typrRegion(cap: CGRect, radius: CGFloat) -> UIBezierPath {
        let path = seam(cap: cap, radius: radius)
        path.addLine(to: CGPoint(x: cap.maxX - radius, y: cap.maxY))
        path.addQuadCurve(to: CGPoint(x: cap.maxX, y: cap.maxY - radius),
                          controlPoint: CGPoint(x: cap.maxX, y: cap.maxY))
        path.addLine(to: CGPoint(x: cap.maxX, y: cap.minY + radius))
        path.addQuadCurve(to: CGPoint(x: cap.maxX - radius, y: cap.minY),
                          controlPoint: CGPoint(x: cap.maxX, y: cap.minY))
        path.close()
        return path
    }

    func draw(in context: CGContext, palette: FullKeyboardPalette, spacePressed: Bool) {
        let outline = UIBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius)
        context.saveGState()
        outline.addClip()
        context.setFillColor((spacePressed ? palette.keyPressedFill : palette.keyFill).cgColor)
        context.fill(frame)
        if spacePressed {
            // Replace, rather than stack, translucent fills on the Typr side.
            context.saveGState()
            Self.typrRegion(cap: typr, radius: radius).addClip()
            context.clear(frame)
            context.setFillColor(palette.keyFill.cgColor)
            context.fill(frame)
            context.restoreGState()
        }
        context.restoreGState()
        let ink = palette.isDark ? UIColor(white: 1, alpha: 0.42) : UIColor(white: 0, alpha: 0.24)
        ink.setStroke()
        outline.lineWidth = 0.8
        outline.stroke()
        let seam = Self.seam(cap: typr.insetBy(dx: 0, dy: 0.5), radius: radius)
        seam.lineWidth = 0.8
        seam.stroke()
    }
}

extension CGContext {
    /// Draws a continuous-corner iOS 26 Liquid Glass keycap with no legacy under-shadow.
    func fillKeycap(_ rect: CGRect, fill: UIColor, shadow: UIColor = .clear, radius: CGFloat = FullKeyboardPalette.cornerRadius) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        saveGState()
        if shadow != .clear {
            setShadow(offset: CGSize(width: 0, height: 1), blur: 0.5, color: shadow.cgColor)
        }
        addPath(path)
        setFillColor(fill.cgColor)
        fillPath()
        restoreGState()
    }
}
