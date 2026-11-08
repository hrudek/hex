import Foundation
import OSLog

/// Only fixed typed reasons may enter observations. In particular, never stringify an Error.
enum CleanupGuardRule: String, Sendable {
    case notesLineAnchors = "notes-line-anchors"
    case alignment = "alignment"
}

enum CleanupFailureReason: Equatable, Sendable {
    case contextWindow, refused, rateLimited, generationFailed, unavailable, deadline, expired, emptyOutput
    case guardRejected(CleanupGuardRule)

    var label: String {
        switch self {
        case .contextWindow: "context-window"
        case .refused: "refused"
        case .rateLimited: "rate-limited"
        case .generationFailed: "generation-failed"
        case .unavailable: "unavailable"
        case .deadline: "deadline"
        case .expired: "expired"
        case .emptyOutput: "empty-output"
        case .guardRejected(let rule): "guard-rejected(\(rule.rawValue))"
        }
    }
}

enum CleanupSkipReason: String, Sendable {
    case off, verbatim, language, budget, busy, unavailable
    case numbersOnly = "numbers-only"
    case noBackgroundLease = "no-background-lease"
}

enum CleanupOutcome: Equatable, Sendable {
    case completed
    case failed(CleanupFailureReason)
    case skipped(CleanupSkipReason)
    case cancelled
}

struct CleanupObservation: Equatable, Sendable {
    let outcome: CleanupOutcome
    let latencyMilliseconds: Int64
}

@MainActor
protocol CleanupObserving {
    func record(_ observation: CleanupObservation)
}

@MainActor
struct CleanupLogger: CleanupObserving {
    private static let logger = Logger(subsystem: "hexplus", category: "ai-cleanup")
    func record(_ observation: CleanupObservation) {
        let latency = observation.latencyMilliseconds
        switch observation.outcome {
        case .completed:
            Self.logger.info("dictation post-processing completed latency_ms=\(latency)")
        case .failed(let reason):
            Self.logger.warning("dictation post-processing failed; pasting the plain transcript latency_ms=\(latency) reason=\(reason.label, privacy: .public)")
        case .skipped(.numbersOnly):
            Self.logger.info("dictation post-processing skipped for a numbers-only transcript latency_ms=\(latency)")
        case .skipped(let reason):
            Self.logger.info("dictation post-processing skipped latency_ms=\(latency) reason=\(reason.rawValue, privacy: .public)")
        case .cancelled:
            Self.logger.info("dictation post-processing cancelled latency_ms=\(latency)")
        }
    }
}

/// Production adapters discard FoundationModels' associated error contexts before throwing.
enum CleanupModelError: Error {
    case contextWindow, refused, rateLimited, generationFailed, unavailable

    var reason: CleanupFailureReason {
        switch self {
        case .contextWindow: .contextWindow
        case .refused: .refused
        case .rateLimited: .rateLimited
        case .generationFailed: .generationFailed
        case .unavailable: .unavailable
        }
    }
}

/// A UI-only ten-second cache. Generation always uses the cleaner's fresh availability.
@MainActor
final class CleanupAvailabilityCache {
    private var cached: (ContinuousClock.Instant, String?)?
    private let now: () -> ContinuousClock.Instant
    private let read: () -> String?

    init(now: @escaping () -> ContinuousClock.Instant = { .now }, read: @escaping () -> String?) {
        self.now = now
        self.read = read
    }

    func invalidate() { cached = nil }

    var reason: String? {
        let instant = now()
        if let (checked, reason) = cached, checked.duration(to: instant) < .seconds(10) { return reason }
        let reason = read()
        cached = (instant, reason)
        return reason
    }
}
