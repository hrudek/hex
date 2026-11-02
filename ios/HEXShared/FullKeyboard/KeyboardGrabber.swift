import UIKit

/// The drag handle's rules, shared by the full keyboard (drag down to the compact bar) and
/// the compact bar (drag up to the full keyboard). Translations and velocities are in
/// points, positive downward.
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
    static let flickVelocity: CGFloat = 700
    /// Moving back faster than this on release cancels even past the threshold.
    static let reverseVelocity: CGFloat = 150
    /// The pill follows the finger at most this far.
    static let maxPillOffset: CGFloat = 6

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

    /// Where the pill sits: a damped share of the travel toward the switch, nothing the other way.
    static func pillOffset(translation: CGFloat, direction: Direction) -> CGFloat {
        let distance = max(0, travel(translation, direction))
        let damped = min(maxPillOffset, distance * 0.2)
        return direction == .down ? damped : -damped
    }
}

/// The full keyboard's drag handle: a pill centred in a zone above the suggestion strip.
/// Dragging down past the threshold and releasing switches to the compact bar. The whole
/// zone is the touch target, and VoiceOver activates it like a button.
@MainActor
final class KeyboardGrabberView: UIView {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { setNeedsDisplay() } } }
    /// Release past the threshold, or VoiceOver activation.
    var onCommit: (() -> Void)?
    /// The drag crossed the threshold toward the switch (once per crossing).
    var onArm: (() -> Void)?

    private let direction: KeyboardGrabberDrag.Direction = .down
    private var translation: CGFloat = 0
    private var isArmed = false
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Show compact keyboard"
        accessibilityHint = "Or drag the handle down"
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityActivate() -> Bool {
        onCommit?()
        return true
    }

    /// Drops a drag in progress without switching (the view is going away or recording began).
    func reset() {
        if pan.state == .began || pan.state == .changed {
            pan.isEnabled = false
            pan.isEnabled = true
        }
        settle()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Claim only a mostly vertical drag that starts here; sideways ones fall through.
        guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            translation = gesture.translation(in: self).y
            let armed = KeyboardGrabberDrag.isArmed(translation: translation, direction: direction)
            if armed && !isArmed { onArm?() }
            isArmed = armed
            setNeedsDisplay()
        case .ended:
            let commit = KeyboardGrabberDrag.commits(
                translation: gesture.translation(in: self).y,
                velocity: gesture.velocity(in: self).y,
                direction: direction
            )
            settle()
            if commit { onCommit?() }
        default:
            // .cancelled and .failed never switch.
            settle()
        }
    }

    private func settle() {
        translation = 0
        isArmed = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let offset = UIAccessibility.isReduceMotionEnabled
            ? 0
            : KeyboardGrabberDrag.pillOffset(translation: translation, direction: direction)
        // Armed: wider and darker, so the state reads without motion too.
        let width: CGFloat = isArmed ? 44 : 36
        let height: CGFloat = 5
        let pill = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2 + offset,
            width: width,
            height: height
        )
        let ink = isArmed ? palette.textBase.withAlphaComponent(0.6) : palette.textMuted.withAlphaComponent(0.45)
        ink.setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: height / 2).fill()
    }
}
