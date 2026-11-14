import Foundation
import Observation

/// App-side learning controls. Technical counters remain separate from personal learning.
@MainActor @Observable
final class KeyboardLearningSettingsModel {
    private(set) var snapshot: KeyboardLearningSnapshot
    private(set) var resetProblem: String?
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let defaults: UserDefaults?

    init(directory: URL? = KeyboardLearningStore.sharedDirectory,
         defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.directory = directory
        self.defaults = defaults
        snapshot = KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults)
    }

    func refresh() {
        snapshot = KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults)
    }

    func resetLearning() { reset(learning: true) }
    func resetTechnicalCounters() { reset(learning: false) }

    private func reset(learning: Bool) {
        let store = KeyboardLearningStore(directory: directory, defaults: defaults)
        var success = learning ? store.requestLearningReset() : store.requestDiagnosticsReset()
        if learning {
            do { try ProtectedPersonalLexicon.reset(directory: directory, defaults: defaults) }
            catch { success = false }
        }
        resetProblem = success ? nil : "Could not reset saved data. Try again when Typr can access its shared storage."
        refresh()
    }
}
