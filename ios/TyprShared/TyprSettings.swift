import Foundation

/// Typr switches, stored in the App Group so the keyboard reads them too.
/// Switches default on. Dictation log deliberately retains saved history while off;
/// other switches keep upstream's behavior when off.
@MainActor
struct TyprSettings {
    private enum Key {
        static let aiCleanup = "typr.aiCleanup"
        static let dictationLog = "typr.dictationLog"
        static let showCleanupModel = "typr.showCleanupModel"
        static let germanAutocorrect = "typr.germanAutocorrect"
        static let keyboardSwitchKey = "typr.keyboardSwitchKey"
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

    /// Show the configured cleanup model in the Typr card, without changing cleanup itself.
    var showCleanupModel: Bool {
        get { defaults?.object(forKey: Key.showCleanupModel) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.showCleanupModel) }
    }

    /// Collection only. Off interrupts pending log entries but deliberately keeps saved history.
    var dictationLog: Bool {
        get { defaults?.object(forKey: Key.dictationLog) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationLog) }
    }

    /// Quick feedback for this keyboard instance's newly inserted dictation. Off keeps existing UI.
    var dictationFeedbackStrip: Bool {
        get { defaults?.object(forKey: DictationFeedbackBridge.stripKey) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: DictationFeedbackBridge.stripKey) }
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
