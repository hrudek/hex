import Foundation

/// Hex+ switches, stored in the App Group so the keyboard reads them too.
/// Every switch is on by default; off keeps upstream's behaviour exactly.
@MainActor
struct HexPlusSettings {
    private enum Key {
        static let germanAutocorrect = "hexplus.germanAutocorrect"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// German autocorrect on the full keyboard (ae/oe/ue/ss to umlauts, German typo fixes). On by default.
    var germanAutocorrect: Bool {
        get { defaults?.object(forKey: Key.germanAutocorrect) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.germanAutocorrect) }
    }
}
