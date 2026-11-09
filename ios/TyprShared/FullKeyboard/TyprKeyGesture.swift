import CoreGraphics
import Foundation

/// The full keyboard's Typr key as a pure state machine. A tap (released before
/// `holdDuration` without moving more than `slop`) types a space. A still hold of
/// `holdDuration` fires the hold action (dictate, or open Typr). Moving more than `slop`
/// before then opens the style menu, and the release picks the row under the finger;
/// Typr: when the compact bar is allowed, a mostly downward move shows it instead.
/// Once the hold fires or the bar is shown, moves and the release are ignored.
nonisolated struct TyprKeyGesture: Equatable, Sendable {
    static let holdDuration: TimeInterval = 0.35
    static let slop: CGFloat = 10

    enum State: Equatable, Sendable {
        case idle
        case pressing
        case menu
        case fired
    }

    enum Output: Equatable, Sendable {
        case ignored
        case tap
        case hold
        case openMenu
        case dragMenu
        case releaseMenu
        case showCompactBar
    }

    private(set) var state: State = .idle
    private var origin: CGPoint = .zero

    mutating func touchDown(at point: CGPoint) {
        state = .pressing
        origin = point
    }

    /// `allowsCompactBar`: a downward slide shows the compact dictation bar (Typr).
    mutating func touchMoved(to point: CGPoint, allowsCompactBar: Bool = false) -> Output {
        switch state {
        case .pressing:
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            guard hypot(dx, dy) > Self.slop else { return .ignored }
            if allowsCompactBar && dy > abs(dx) {
                state = .fired
                return .showCompactBar
            }
            state = .menu
            return .openMenu
        case .menu:
            return .dragMenu
        case .idle, .fired:
            return .ignored
        }
    }

    /// The hold timer started at touch-down ran out.
    mutating func holdElapsed() -> Output {
        guard state == .pressing else { return .ignored }
        state = .fired
        return .hold
    }

    mutating func touchUp() -> Output {
        let output: Output = switch state {
        case .menu: .releaseMenu
        case .pressing: .tap
        case .idle, .fired: .ignored
        }
        state = .idle
        return output
    }

    mutating func cancel() {
        state = .idle
    }
}
