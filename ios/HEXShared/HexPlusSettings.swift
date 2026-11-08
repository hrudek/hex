import Foundation

/// Hex+ switches, stored in the App Group so the keyboard reads them too.
/// Switches default on. Dictation log deliberately retains saved history while off;
/// other switches keep upstream's behavior when off.
@MainActor
struct HexPlusSettings {
    private enum Key {
        static let aiCleanup = "hexplus.aiCleanup"
        static let dictationLog = "hexplus.dictationLog"
        static let showCleanupModel = "hexplus.showCleanupModel"
        static let germanAutocorrect = "hexplus.germanAutocorrect"
        static let keyboardSwitchKey = "hexplus.keyboardSwitchKey"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// On-device Apple Intelligence cleanup. Off retains the plain transcription path.
    var aiCleanup: Bool {
        get { defaults?.object(forKey: Key.aiCleanup) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.aiCleanup) }
    }

    /// Show the configured cleanup model in the Hex+ card, without changing cleanup itself.
    var showCleanupModel: Bool {
        get { defaults?.object(forKey: Key.showCleanupModel) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.showCleanupModel) }
    }

    /// Collection only. Off interrupts pending log entries but deliberately keeps saved history.
    var dictationLog: Bool {
        get { defaults?.object(forKey: Key.dictationLog) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationLog) }
    }

    /// German autocorrect on the full keyboard (ae/oe/ue/ss to umlauts, German typo fixes). On by default.
    var germanAutocorrect: Bool {
        get { defaults?.object(forKey: Key.germanAutocorrect) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.germanAutocorrect) }
    }

    /// A key on both keyboards switches between the full keyboard and the compact dictation
    /// bar (the full keyboard's key needs a short hold). On by default.
    var keyboardSwitchKey: Bool {
        get { defaults?.object(forKey: Key.keyboardSwitchKey) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.keyboardSwitchKey) }
    }
}
