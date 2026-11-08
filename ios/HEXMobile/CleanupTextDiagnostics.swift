import Foundation

/// Opt-in, per-operation text diagnostics. Never forwarded to the text-free logger or App Group.
@MainActor
protocol CleanupTextDiagnostics: AnyObject {
    func cleanupResolved(_ observation: CleanupObservation, changed: Bool?)
    func modelAnswer(_ text: String, use: CleanupAnswerUse, modelMilliseconds: Int64)
    /// A thrown call has a duration, but no answer. Cancellation after resolution reports neither.
    func modelFailed(modelMilliseconds: Int64)
}

extension CleanupTextDiagnostics {
    func modelFailed(modelMilliseconds: Int64) {}
}

enum CleanupAnswerUse: Equatable, Sendable {
    case accepted
    case rejected(CleanupFailureReason)
    case late
}

extension CleanupOutcome {
    var dictationLogLabel: String {
        switch self {
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .failed(let reason): "failed(\(reason.label))"
        case .skipped(let reason): "skipped(\(reason.rawValue))"
        }
    }
}

/// Monotonic durations only; wall-clock changes must not affect diagnostics.
func dictationLogMilliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant = .now) -> Int64 {
    let parts = start.duration(to: end).components
    return max(0, parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
}
