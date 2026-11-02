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
        static let compactAllowed = "settings.keyboardCompactAllowed"
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

    /// The person may switch between the full keyboard and the compact bar (drag handle,
    /// keyboard key). On by default; off always shows the full keyboard.
    var compactAllowed: Bool {
        get { defaults?.object(forKey: Key.compactAllowed) as? Bool ?? true }
        nonmutating set { defaults?.set(newValue, forKey: Key.compactAllowed) }
    }

    /// The full keyboard exists here at all: the experiment is on, on an iPhone.
    static func offersFullKeyboard(experimentEnabled: Bool, isPhone: Bool) -> Bool {
        experimentEnabled && isPhone
    }

    /// The drag handles and the compact bar's keyboard key show: the full keyboard exists
    /// and switching is allowed.
    static func offersSwitching(experimentEnabled: Bool, isPhone: Bool, compactAllowed: Bool) -> Bool {
        offersFullKeyboard(experimentEnabled: experimentEnabled, isPhone: isPhone) && compactAllowed
    }

    /// Which surface shows. Without the full keyboard, the compact bar. With it, the full
    /// keyboard unless switching is allowed and the person chose the compact bar. The
    /// choice is kept while switching or the experiment is off, so it returns with them.
    static func showsFullKeyboard(
        experimentEnabled: Bool,
        isPhone: Bool,
        compactAllowed: Bool,
        choice: KeyboardLayoutChoice
    ) -> Bool {
        guard offersFullKeyboard(experimentEnabled: experimentEnabled, isPhone: isPhone) else { return false }
        return !compactAllowed || choice == .full
    }

    /// Simulator scenes pass `--experiment-full-keyboard` to turn the experiment on.
    func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains(Self.launchArgument) {
            isEnabled = true
        }
    }
}
