import Foundation

/// Success data is reduced to counts immediately; neither transcript nor audio is retained.
@MainActor
final class UsageDictationRecorder {
    private struct Pending {
        let token: UsageCaptureToken
        let words: UInt64
        let seconds: Double
    }
    let store: UsageStatisticsStore
    private var pending: [UUID: Pending] = [:]
    private(set) var lastError: Error?
    init(store: UsageStatisticsStore) { self.store = store }

    func beginCapture() -> UsageCaptureToken? {
        flush()
        do { return try store.beginCapture() }
        catch { lastError = error; return nil }
    }
    func success(_ token: UsageCaptureToken?, recognized: String, delivered: String, seconds: Double) {
        guard let token, !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !delivered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              seconds.isFinite, seconds > 0, seconds <= 86400 else { return }
        let count = UsageWordTracker.count(recognized)
        if pending[token.id] == nil {
            guard pending.count < 2048 else { lastError = UsageStatisticsStore.Failure.capacity; return }
            pending[token.id] = Pending(token: token, words: count, seconds: seconds)
        }
        flush()
    }
    func flush() {
        lastError = nil
        for (id, value) in pending {
            do {
                try store.recordCapture(value.token, words: value.words, seconds: value.seconds)
                pending.removeValue(forKey: id)
            } catch {
                lastError = error
                if let failure = error as? UsageStatisticsStore.Failure,
                   [.staleGeneration, .expired, .invalid].contains(failure) {
                    pending.removeValue(forKey: id)
                }
            }
        }
    }
}
