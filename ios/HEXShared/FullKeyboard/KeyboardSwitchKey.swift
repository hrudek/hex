import CoreGraphics
import UIKit

// Typr: the key that switches between the full keyboard and the compact dictation bar.

/// The full keyboard's switch key as a pure state machine. A tap does nothing, so fast
/// typing never switches by accident; a hold of `holdDuration` switches once. Sliding off
/// the key before then cancels the hold.
nonisolated struct KeyboardSwitchHold: Equatable, Sendable {
    static let holdDuration: TimeInterval = 0.35

    enum State: Equatable, Sendable {
        case idle
        case pressing
        case fired
        case cancelled
    }

    private(set) var state: State = .idle

    mutating func touchDown() {
        state = .pressing
    }

    /// The finger moved; `inside` is false once it left the key.
    mutating func touchMoved(inside: Bool) {
        if state == .pressing && !inside {
            state = .cancelled
        }
    }

    /// The hold timer started at touch-down ran out. True exactly once per press.
    mutating func holdElapsed() -> Bool {
        guard state == .pressing else { return false }
        state = .fired
        return true
    }

    mutating func touchUp() {
        state = .idle
    }
}

/// Where the compact bar (`false`) or the full keyboard (`true`) was last chosen with the
/// switch key. Kept in the keyboard's own defaults, so it works without Full Access.
@MainActor
struct KeyboardSurfaceChoice {
    private static let key = "typr.keyboardShowsCompactBar"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The compact dictation bar was picked over the full keyboard. Off by default.
    var showsCompactBar: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    /// Whether the full keyboard is mounted: its experiment on, and, with the Typr switch
    /// key on, the compact bar not chosen. With the switch off this is today's rule.
    static func wantsFullKeyboard(experimentOn: Bool, switchKeyOn: Bool, compactChosen: Bool) -> Bool {
        experimentOn && !(switchKeyOn && compactChosen)
    }
}

/// The full keyboard's switch key, drawn over the key plane at `KeyKind.compactSwitch`.
/// Hold it for `KeyboardSwitchHold.holdDuration` to show the compact dictation bar.
@MainActor
final class KeyboardSwitchKeyControl: UIControl {
    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { setNeedsDisplay() } } }
    var cornerRadius: CGFloat = FullKeyboardPalette.cornerRadius { didSet { if cornerRadius != oldValue { setNeedsDisplay() } } }
    /// The drawn keycap inside the control's (larger) touch target.
    var keycapFrame: CGRect = .zero { didSet { if keycapFrame != oldValue { setNeedsDisplay() } } }
    var isLandscape = false { didSet { if isLandscape != oldValue { setNeedsDisplay() } } }

    /// The hold ran out: show the compact bar.
    var onHold: (() -> Void)?

    private var hold = KeyboardSwitchHold()
    private var holdWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Show dictation bar"
        accessibilityHint = "Hold to switch to the compact dictation bar"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { setNeedsDisplay() } }
    }

    override func accessibilityActivate() -> Bool {
        onHold?()
        return true
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        hold.touchDown()
        isHighlighted = true
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.holdElapsed() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardSwitchHold.holdDuration, execute: work)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let inside = bounds.insetBy(dx: -8, dy: -8).contains(touch.location(in: self))
        hold.touchMoved(inside: inside)
        if hold.state == .cancelled {
            stopTimer()
            isHighlighted = false
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        stopTimer()
        isHighlighted = false
        hold.touchUp()
    }

    override func cancelTracking(with event: UIEvent?) {
        stopTimer()
        isHighlighted = false
        hold.touchUp()
    }

    private func holdElapsed() {
        holdWork = nil
        guard hold.holdElapsed() else { return }
        isHighlighted = false
        onHold?()
    }

    private func stopTimer() {
        holdWork?.cancel()
        holdWork = nil
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let cap = keycapFrame == .zero ? bounds : keycapFrame
        context.fillKeycap(
            cap,
            fill: isHighlighted ? palette.keyPressedFill : palette.keyFill,
            radius: cornerRadius
        )
        let config = UIImage.SymbolConfiguration(pointSize: isLandscape ? 15 : 17, weight: .regular)
        guard let image = UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: config)?
            .withTintColor(palette.textBase, renderingMode: .alwaysOriginal) else { return }
        image.draw(at: CGPoint(x: cap.midX - image.size.width / 2, y: cap.midY - image.size.height / 2))
    }
}
