import UIKit

/// The drag handle's rules, shared by the full keyboard (drag down to the compact bar) and
/// the compact bar (drag up to the full keyboard). Translations and velocities are in
/// points, positive downward. While dragging, the keyboard's height follows the finger
/// (`KeyboardViewController`); these decide when a release switches.
nonisolated enum KeyboardGrabberDrag {
    enum Direction: Sendable {
        /// Full keyboard → compact bar.
        case down
        /// Compact bar → full keyboard.
        case up
    }

    /// How far the finger has to travel toward the switch before release switches.
    static let threshold: CGFloat = 36
    /// A quick flick switches from this far, if it is still moving toward the switch.
    static let flickDistance: CGFloat = 16
    static let flickVelocity: CGFloat = 600
    /// Moving back faster than this on release cancels even past the threshold.
    static let reverseVelocity: CGFloat = 150
    /// How far past the other keyboard's height the drag stretches, with resistance.
    static let overshoot: CGFloat = 14

    /// The handle's pill: long, and longer once a release would switch.
    static let pillWidth: CGFloat = 64
    static let armedPillWidth: CGFloat = 76
    static let pillHeight: CGFloat = 5

    /// Travel toward the switch; negative when the finger went the other way.
    static func travel(_ translation: CGFloat, _ direction: Direction) -> CGFloat {
        direction == .down ? translation : -translation
    }

    /// Past the threshold: release would switch (unless it reverses), so the handle shows it.
    static func isArmed(translation: CGFloat, direction: Direction) -> Bool {
        travel(translation, direction) >= threshold
    }

    /// Whether a release switches keyboards.
    static func commits(translation: CGFloat, velocity: CGFloat, direction: Direction) -> Bool {
        let distance = travel(translation, direction)
        let speed = travel(velocity, direction)
        if distance >= threshold { return speed > -reverseVelocity }
        return distance >= flickDistance && speed >= flickVelocity
    }

    /// The keyboard's height while dragging from `from` toward `to`: follows the finger
    /// 1:1 between the two, never past `from`, and stretches at most `overshoot` past `to`.
    static func height(from: CGFloat, to: CGFloat, translation: CGFloat, direction: Direction) -> CGFloat {
        let span = abs(to - from)
        let distance = max(0, travel(translation, direction))
        let moved: CGFloat
        if distance <= span {
            moved = distance
        } else {
            let extra = distance - span
            moved = span + overshoot * (1 - 1 / (extra / overshoot + 1))
        }
        return to >= from ? from + moved : from - moved
    }
}

/// The full keyboard's drag handle: a long pill centred in a zone above the suggestion
/// strip. The drag itself belongs to the keyboard's controller (it resizes the keyboard
/// live); this draws the handle and lets VoiceOver activate the switch like a button.
@MainActor
final class KeyboardGrabberView: UIView {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { setNeedsDisplay() } } }
    /// A release now would switch: the pill is longer and darker.
    var isArmed = false { didSet { if isArmed != oldValue { setNeedsDisplay() } } }
    /// VoiceOver activation.
    var onCommit: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Show compact keyboard"
        accessibilityHint = "Or drag the top of the keyboard down"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityActivate() -> Bool {
        onCommit?()
        return true
    }

    override func draw(_ rect: CGRect) {
        let width = isArmed ? KeyboardGrabberDrag.armedPillWidth : KeyboardGrabberDrag.pillWidth
        let height = KeyboardGrabberDrag.pillHeight
        let pill = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        let ink = isArmed ? palette.textBase.withAlphaComponent(0.6) : palette.textMuted.withAlphaComponent(0.45)
        ink.setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: height / 2).fill()
    }
}
