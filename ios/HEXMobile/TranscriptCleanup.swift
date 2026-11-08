import Foundation
import OSLog

@MainActor
protocol CleanupSession: AnyObject {
    func prewarm() async
    func clean(_ text: String, style: DictationStyle) async throws -> String
}

@MainActor
protocol TranscriptCleaning {
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
    private(set) var reservedBy: UUID?
    private var modelTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var pendingID: UUID?
    private var continuation: CheckedContinuation<String, Never>?
    private var fallback = ""
    private static let logger = Logger(subsystem: "hexplus", category: "ai-cleanup")

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

    func cancel(_ id: UUID) {
        if pendingID == id { resolve(id, value: fallback) }
        if reservedBy == id { modelTask?.cancel() }
    }

    private func resolve(_ id: UUID, value: String) {
        guard pendingID == id, let continuation else { return }
        self.continuation = nil
        pendingID = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        continuation.resume(returning: value)
    }

    func clean(_ raw: String, style: DictationStyle, job: CleanupJob,
               dependencies: TranscriptCleanupDependencies) async -> String {
        guard !Task.isCancelled, job.permitted, dependencies.cleaner.unavailableReason == nil,
              raw.utf8.count <= 1500, CleanupGuard.wordCount(raw) <= 250,
              dependencies.language.supports(raw), admit(job.id) else { return raw }
        return await withTaskCancellationHandler {
            // No suspension between cancellation check and continuation registration on MainActor.
            guard !Task.isCancelled else { release(job.id); return raw }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                pendingID = job.id
                fallback = raw
                job.onExpiry = { [weak self] in self?.cancel(job.id) }
                modelTask = Task {
                    do {
                        let revised = try await job.session.clean(raw, style: style)
                        let accepted = CleanupGuard.accepts(input: raw, output: revised, style: style)
                        if !accepted { Self.logger.info("fallback: structural guard") }
                        resolve(job.id, value: accepted ? revised : raw)
                    } catch {
                        // Never log localized errors, prompts, responses, or transcripts.
                        Self.logger.info("fallback: model generation error")
                        resolve(job.id, value: raw)
                    }
                    release(job.id)
                }
                deadlineTask = Task {
                    do { try await dependencies.sleep(.seconds(4)) } catch { return }
                    guard !Task.isCancelled, pendingID == job.id else { return }
                    Self.logger.info("fallback: deadline")
                    cancel(job.id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(job.id) }
        }
    }
}
