import Foundation
import OSLog

/// Only fixed typed reasons may enter observations. In particular, never stringify an Error.
enum CleanupGuardRule: String, Sendable {
    case notesLineAnchors = "notes-line-anchors"
    case notesMarkers = "notes-markers"
    case grew = "grew"
    case newValue = "new-value"
    case newWords = "new-words"

    /// Why the card says the change was not used.
    var explanation: String {
        switch self {
        case .notesLineAnchors: "it changed the line breaks"
        case .notesMarkers: "it changed bullet or new-line words"
        case .grew: "it was much longer than what you said"
        case .newValue: "it contained a number or link you didn't say"
        case .newWords: "it was mostly words you didn't say"
        }
    }
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
    /// Whether an accepted result differs from the transcript (never the text itself). Sent before `record`.
    func recordChange(_ changed: Bool)
    /// A model call that returned after its job was already resolved (deadline, expiry, cancel).
    func recordLate(latencyMilliseconds: Int64)
}

extension CleanupObserving {
    func recordChange(_ changed: Bool) {}
    func recordLate(latencyMilliseconds: Int64) {}
}

/// The last dictation's outcome for the Hex+ card: a fixed English summary, latency and time, never text.
@MainActor
final class CleanupDiagnostics: CleanupObserving {
    static let key = "hexplus.aiCleanup.last"
    private let defaults: UserDefaults?
    private var changed: Bool?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    func recordChange(_ changed: Bool) { self.changed = changed }

    func record(_ observation: CleanupObservation) {
        let summary = Self.summary(observation.outcome, latencyMilliseconds: observation.latencyMilliseconds, changed: changed)
        changed = nil
        // Off is the user's own choice; keep the previous result visible instead.
        if case .skipped(.off) = observation.outcome { return }
        let entry: [String: Any] = [
            "summary": summary,
            "at": Date().timeIntervalSince1970,
            "deadline": observation.outcome == .failed(.deadline)
        ]
        defaults?.set(entry, forKey: Self.key)
    }

    func recordLate(latencyMilliseconds: Int64) {
        guard var last = defaults?.dictionary(forKey: Self.key), last["deadline"] as? Bool == true,
              let summary = last["summary"] as? String else { return }
        last["summary"] = summary + " (it finished after \(Self.seconds(latencyMilliseconds)))"
        last["deadline"] = false
        defaults?.set(last, forKey: Self.key)
    }

    /// "Last dictation: …" with how long ago, or nil before the first dictation.
    func lastSummary(now: Date = Date()) -> String? {
        guard let last = defaults?.dictionary(forKey: Self.key), let summary = last["summary"] as? String,
              let at = last["at"] as? TimeInterval else { return nil }
        let minutes = Int(max(0, now.timeIntervalSince1970 - at) / 60)
        let ago = minutes < 1 ? "just now" : minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago"
        return "Last dictation (\(ago)): \(summary)"
    }

    static func seconds(_ milliseconds: Int64) -> String {
        String(format: "%.1f s", Double(milliseconds) / 1000)
    }

    static func summary(_ outcome: CleanupOutcome, latencyMilliseconds: Int64, changed: Bool?) -> String {
        let took = seconds(latencyMilliseconds)
        switch outcome {
        case .completed:
            return changed == false ? "Apple Intelligence changed nothing (\(took))" : "cleaned up by Apple Intelligence (\(took))"
        case .cancelled: return "cancelled"
        case .failed(let reason):
            switch reason {
            case .deadline: return "Apple Intelligence took longer than \(CleanupCoordinator.deadline.components.seconds) s; plain transcript used"
            case .guardRejected(let rule): return "Apple Intelligence's change was not used: \(rule.explanation) (\(took))"
            case .rateLimited: return "iOS limited Apple Intelligence (often in the background); plain transcript used"
            case .refused: return "Apple Intelligence refused this text; plain transcript used"
            case .contextWindow: return "too long for Apple Intelligence; plain transcript used"
            case .emptyOutput: return "Apple Intelligence returned nothing; plain transcript used"
            case .expired: return "iOS ended the background time; plain transcript used"
            case .unavailable: return "Apple Intelligence was unavailable"
            case .generationFailed: return "Apple Intelligence failed; plain transcript used"
            }
        case .skipped(let reason):
            switch reason {
            case .off: return "AI cleanup is off"
            case .verbatim: return "skipped in Verbatim style"
            case .language: return "skipped: fewer than 3 words, or a language Apple Intelligence doesn't support"
            case .budget: return "skipped: dictation too long"
            case .busy: return "skipped: the previous cleanup was still running"
            case .unavailable: return "skipped: Apple Intelligence unavailable"
            case .numbersOnly: return "skipped: numbers only"
            case .noBackgroundLease: return "skipped: iOS gave no background time"
            }
        }
    }
}

/// Logs and keeps the last outcome for the Hex+ card.
@MainActor
struct CleanupObservers: CleanupObserving {
    let observers: [any CleanupObserving]
    func record(_ observation: CleanupObservation) { observers.forEach { $0.record(observation) } }
    func recordChange(_ changed: Bool) { observers.forEach { $0.recordChange(changed) } }
    func recordLate(latencyMilliseconds: Int64) { observers.forEach { $0.recordLate(latencyMilliseconds: latencyMilliseconds) } }
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

    func recordLate(latencyMilliseconds: Int64) {
        Self.logger.info("dictation post-processing model returned after its deadline latency_ms=\(latencyMilliseconds)")
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
