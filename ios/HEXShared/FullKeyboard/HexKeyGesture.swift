import CoreGraphics
import Foundation

/// What a touch on the Hex key means, as a pure state machine.
///
/// A tap does nothing, so a stray tap while typing is harmless. Holding the key still
/// for `holdDuration` starts dictation (warm) or opens Hex (cold); dictation then keeps
/// recording after release, as a toggle. Sliding past `slideDistance` before that opens
/// the style menu, and the slide picks a row on release.
nonisolated struct HexKeyGesture: Equatable, Sendable {
    static let holdDuration: TimeInterval = 0.35
    static let slideDistance: CGFloat = 10

    enum Phase: Equatable, Sendable {
        case idle
        /// Finger down, not yet decided.
        case pending(start: CGPoint, since: TimeInterval)
        /// The hold fired; the rest of this touch does nothing.
        case held
        /// The slide opened the menu; moves hover rows, release picks.
        case menu
    }

    enum Action: Equatable, Sendable {
        case hold
        case openMenu
        case drag(CGPoint)
        case finishMenu(CGPoint)
    }

    private(set) var phase: Phase = .idle

    mutating func touchDown(at point: CGPoint, now: TimeInterval) {
        phase = .pending(start: point, since: now)
    }

    /// Returns `.hold` once the finger stayed still for `holdDuration`.
    mutating func tick(now: TimeInterval) -> Action? {
        guard case .pending(_, let since) = phase, now - since >= Self.holdDuration else { return nil }
        return holdElapsed()
    }

    /// The hold timer fired: a touch still undecided becomes a hold.
    mutating func holdElapsed() -> Action? {
        guard case .pending = phase else { return nil }
        phase = .held
        return .hold
    }

    mutating func touchMoved(to point: CGPoint, now: TimeInterval) -> [Action] {
        switch phase {
        case .pending(let start, _):
            if let hold = tick(now: now) { return [hold] }
            guard hypot(point.x - start.x, point.y - start.y) > Self.slideDistance else { return [] }
            phase = .menu
            return [.openMenu, .drag(point)]
        case .menu:
            return [.drag(point)]
        case .idle, .held:
            return []
        }
    }

    /// A release before the hold or the slide is a tap, which does nothing.
    mutating func touchUp(at point: CGPoint) -> Action? {
        defer { phase = .idle }
        if case .menu = phase { return .finishMenu(point) }
        return nil
    }

    mutating func cancel() {
        phase = .idle
    }
}
