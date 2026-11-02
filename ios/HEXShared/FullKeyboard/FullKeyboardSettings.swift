import Foundation

/// Which Hex keyboard the person last chose: the full keyboard or the compact dictation bar.
enum KeyboardLayoutChoice: String {
    case full
    case compact
}

/// The full keyboard's switches in the shared App Group.
///
/// Without Full Access the keyboard cannot read the App Group, so `isEnabled` reads
/// `false` there and the keyboard keeps today's setup card.
@MainActor
struct FullKeyboardSettings {
    static let launchArgument = "--experiment-full-keyboard"

    private enum Key {
        static let fullKeyboard = "experiments.fullKeyboard"
        static let autocorrect = "settings.keyboardAutocorrect"
        static let layout = "keyboard.layout"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// Experiment: Hex shows a full QWERTY keyboard instead of the dictation bar. Off by default.
    var isEnabled: Bool {
        get { defaults?.bool(forKey: Key.fullKeyboard) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.fullKeyboard) }
    }

    /// Cautious autocorrect on space. On by default.
    var autocorrect: Bool {
        get { defaults?.object(forKey: Key.autocorrect) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.autocorrect) }
    }

    /// The keyboard the person switched to last. Missing or unknown values read as `.full`,
    /// so turning the experiment on keeps showing the full keyboard.
    var layoutChoice: KeyboardLayoutChoice {
        get { defaults?.string(forKey: Key.layout).flatMap(KeyboardLayoutChoice.init(rawValue:)) ?? .full }
        nonmutating set { defaults?.set(newValue.rawValue, forKey: Key.layout) }
    }

    /// Whether the person can switch to the full keyboard at all: the experiment is on, on an iPhone.
    static func offersFullKeyboard(experimentEnabled: Bool, isPhone: Bool) -> Bool {
        experimentEnabled && isPhone
    }

    /// The full keyboard shows only where it is offered and chosen; otherwise the compact bar.
    /// The choice is kept while the experiment is off, so it returns when it is on again.
    static func showsFullKeyboard(experimentEnabled: Bool, isPhone: Bool, choice: KeyboardLayoutChoice) -> Bool {
        offersFullKeyboard(experimentEnabled: experimentEnabled, isPhone: isPhone) && choice == .full
    }

    /// Simulator scenes pass `--experiment-full-keyboard` to turn the experiment on.
    func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains(Self.launchArgument) {
            isEnabled = true
        }
    }
}
