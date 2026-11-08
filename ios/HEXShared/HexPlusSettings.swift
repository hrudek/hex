import Foundation

/// Hex+ switches, stored in the App Group so the keyboard reads them too.
/// Every switch is on by default; off keeps upstream's behaviour exactly.
@MainActor
struct HexPlusSettings {
    private enum Key {
        static let aiCleanup = "hexplus.aiCleanup"
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
