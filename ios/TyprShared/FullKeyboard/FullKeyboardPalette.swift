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

/// The same outlined Typr wordmark used by SwiftUI and the app icon.
enum TyprMarkPath {
    static func draw(in context: CGContext, rect: CGRect, color: UIColor, coreColor: UIColor?) {
        context.saveGState()
        context.setFillColor((coreColor ?? color).cgColor)
        context.addPath(TyprWordmark().path(in: rect).cgPath)
        context.fillPath()
        context.restoreGState()
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
