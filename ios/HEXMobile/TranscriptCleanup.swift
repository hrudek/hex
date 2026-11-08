import Foundation

@MainActor
protocol CleanupSession: AnyObject {
    func prewarm() async
    func clean(_ text: String, style: DictationStyle) async throws -> String
}

@MainActor
protocol TranscriptCleaning {
    /// Fresh availability, never the UI's cached value.
    var unavailableReason: String? { get }
    func makeSession() -> any CleanupSession
}

@MainActor
protocol LanguageDetecting {
    func supports(_ text: String) -> Bool
}

@MainActor
protocol BackgroundTaskStarting {
    /// nil represents UIKit's invalid token; it must never be ended.
    func begin(expiration: @escaping @MainActor () -> Void) -> Int?
    func end(_ token: Int)
}

@MainActor
struct TranscriptCleanupDependencies {
    let cleaner: any TranscriptCleaning
    let language: any LanguageDetecting
    let background: any BackgroundTaskStarting
    let isEnabled: @MainActor () -> Bool
    var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var observer: any CleanupObserving = CleanupLogger()
    var clock: @MainActor () -> ContinuousClock.Instant = { .now }
}

/// Owns a capture's background lease independently of the model operation's lifetime.
@MainActor
final class CleanupJob {
    let id = UUID()
    let session: any CleanupSession
    private let background: any BackgroundTaskStarting
    private var token: Int?
    private(set) var expired = false
    private(set) var permitted = false
    private var ended = false
    var onExpiry: (@MainActor () -> Void)?

    init(session: any CleanupSession, background: any BackgroundTaskStarting) {
        self.session = session
        self.background = background
    }

    func begin() {
        let acquired = background.begin { [weak self] in
            guard let self else { return }
            self.expired = true
            self.permitted = false
            self.onExpiry?()
            self.finish()
        }
        // Expiration is allowed to run synchronously, before begin returns its token.
        if ended {
            if let acquired { background.end(acquired) }
        } else {
            token = acquired
            permitted = acquired != nil && !expired
        }
    }

    func finish() {
        guard !ended else { return }
        ended = true
        permitted = false
        onExpiry = nil
        if let token { background.end(token) }
        token = nil
    }
}

/// A cancelled/timed-out model retains the sole reservation until it really returns.
/// Unstructured tasks are intentional: structured task groups would await an uncooperative model.
@MainActor
final class CleanupCoordinator {
    private struct Pending {
        let id: UUID
        let continuation: CheckedContinuation<String, Never>
        let raw: String
        let started: ContinuousClock.Instant
        let dependencies: TranscriptCleanupDependencies
    }

    private(set) var reservedBy: UUID?
    private var modelTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var pending: Pending?

    func admit(_ id: UUID) -> Bool {
        guard reservedBy == nil else { return false }
        reservedBy = id
        return true
    }

    func release(_ id: UUID) {
        guard reservedBy == id else { return }
        reservedBy = nil
        modelTask = nil
    }

    func prewarm(_ job: CleanupJob) {
        guard admit(job.id) else { return }
        modelTask = Task {
            await job.session.prewarm()
            release(job.id)
        }
    }

    func cancel(_ id: UUID, outcome: CleanupOutcome = .cancelled) {
        if let pending, pending.id == id { resolve(id, value: pending.raw, outcome: outcome) }
        if reservedBy == id { modelTask?.cancel() }
    }

    private func observe(_ outcome: CleanupOutcome, started: ContinuousClock.Instant,
                         dependencies: TranscriptCleanupDependencies) {
        let elapsed = started.duration(to: dependencies.clock()).components
        let milliseconds = max(0, elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        dependencies.observer.record(CleanupObservation(outcome: outcome, latencyMilliseconds: milliseconds))
    }

    func recordSkip(_ reason: CleanupSkipReason, dependencies: TranscriptCleanupDependencies) {
        observe(.skipped(reason), started: dependencies.clock(), dependencies: dependencies)
    }

    private func resolve(_ id: UUID, value: String, outcome: CleanupOutcome) {
        guard let pending, pending.id == id else { return }
        self.pending = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        // Only the resolution winner observes; late model/deadline/cancellation paths are no-ops.
        observe(outcome, started: pending.started, dependencies: pending.dependencies)
        pending.continuation.resume(returning: value)
    }

    func clean(_ raw: String, style: DictationStyle, job: CleanupJob?,
               dependencies: TranscriptCleanupDependencies, skipReason: CleanupSkipReason? = nil) async -> String {
        let started = dependencies.clock()
        func skip(_ reason: CleanupSkipReason) -> String {
            observe(.skipped(reason), started: started, dependencies: dependencies)
            return raw
        }
        guard !Task.isCancelled else {
            observe(.cancelled, started: started, dependencies: dependencies)
            return raw
        }
        if skipReason == .off || skipReason == .verbatim { return skip(skipReason!) }
        // Desktop #949: after ASR, before language/admission. Prewarm may already have run.
        if CleanupNumbers.only(raw) { return skip(.numbersOnly) }
        if let skipReason { return skip(skipReason) }
        guard let job else { return skip(.busy) }
        if job.expired {
            observe(.failed(.expired), started: started, dependencies: dependencies)
            return raw
        }
        guard job.permitted else { return skip(.noBackgroundLease) }
        guard dependencies.cleaner.unavailableReason == nil else { return skip(.unavailable) }
        guard raw.utf8.count <= 1500, CleanupGuard.wordCount(raw) <= 250 else { return skip(.budget) }
        guard dependencies.language.supports(raw) else { return skip(.language) }
        guard admit(job.id) else { return skip(.busy) }
        return await withTaskCancellationHandler {
            // No suspension between cancellation check and continuation registration on MainActor.
            guard !Task.isCancelled else {
                release(job.id)
                observe(.cancelled, started: started, dependencies: dependencies)
                return raw
            }
            return await withCheckedContinuation { continuation in
                pending = Pending(id: job.id, continuation: continuation, raw: raw, started: started, dependencies: dependencies)
                job.onExpiry = { [weak self] in self?.cancel(job.id, outcome: .failed(.expired)) }
                modelTask = Task {
                    // A model that returns after its job was resolved only reports how long it really took.
                    func reportIfLate() -> Bool {
                        guard pending?.id != job.id else { return false }
                        let elapsed = started.duration(to: dependencies.clock()).components
                        dependencies.observer.recordLate(
                            latencyMilliseconds: max(0, elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000))
                        return true
                    }
                    do {
                        let revised = try await job.session.clean(raw, style: style)
                        if reportIfLate() { release(job.id); return }
                        // Inspect RAW Notes line anchors before trimming or classifying empty output.
                        if style == .notes && raw.components(separatedBy: "\n").count != revised.components(separatedBy: "\n").count {
                            resolve(job.id, value: raw, outcome: .failed(.guardRejected(.notesLineAnchors)))
                        } else if revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            resolve(job.id, value: raw, outcome: .failed(.emptyOutput))
                        } else if !CleanupGuard.accepts(input: raw, output: revised, style: style) {
                            resolve(job.id, value: raw, outcome: .failed(.guardRejected(.alignment)))
                        } else {
                            let cleaned = revised.trimmingCharacters(in: .whitespacesAndNewlines)
                            dependencies.observer.recordChange(cleaned != raw.trimmingCharacters(in: .whitespacesAndNewlines))
                            resolve(job.id, value: cleaned, outcome: .completed)
                        }
                    } catch {
                        if reportIfLate() { release(job.id); return }
                        // Never inspect descriptions, associated contexts, prompts, or refusal explanations.
                        let reason = (error as? CleanupModelError)?.reason ?? .generationFailed
                        let outcome: CleanupOutcome = reason == .unavailable ? .skipped(.unavailable) : .failed(reason)
                        resolve(job.id, value: raw, outcome: outcome)
                    }
                    release(job.id)
                }
                deadlineTask = Task {
                    do { try await dependencies.sleep(.seconds(4)) } catch { return }
                    guard !Task.isCancelled, pending?.id == job.id else { return }
                    cancel(job.id, outcome: .failed(.deadline))
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(job.id) }
        }
    }
}
