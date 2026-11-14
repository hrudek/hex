import Foundation
import Observation

/// App-side read/reset adapter. Never saves learning or exposes retained words to the view.
@MainActor @Observable
final class KeyboardDiagnosticsModel {
    private(set) var snapshot: KeyboardLearningSnapshot
    private(set) var learningEnabled: Bool
    private(set) var resetProblem: String?
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let fixture: Bool
    @ObservationIgnored private var observer: KeyboardLearningObserver?

    init(directory: URL? = KeyboardLearningStore.sharedDirectory,
         defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.directory = directory
        self.defaults = defaults
        fixture = false
        snapshot = KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults)
        learningEnabled = TyprSettings(defaults: defaults).personalLearning
    }

    /// Snapshot scenes stay entirely in memory, including refresh and reset actions.
    init(fixture: KeyboardLearningSnapshot, learningEnabled: Bool = true) {
        directory = nil
        defaults = nil
        self.fixture = true
        snapshot = fixture
        self.learningEnabled = learningEnabled
    }

    func startObserving() {
        guard !fixture else { return }
        if observer == nil {
            // Snapshot-driven refresh adapted from AVGVSTVS96/iikb App/Stats/TapsPage.swift (MIT).
            observer = KeyboardLearningObserver { [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stopObserving() {
        observer?.invalidate()
        observer = nil
    }

    func refresh() {
        guard !fixture else { return }
        snapshot = KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults)
        learningEnabled = TyprSettings(defaults: defaults).personalLearning
    }

    func resetLearning() { reset(learning: true) }
    func resetStatistics() { reset(learning: false) }

    private func reset(learning: Bool) {
        guard !fixture else { return }
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
