import Foundation

// Typr: switching between the full keyboard and the compact dictation bar. The compact
// bar's keyboard key shows the full keyboard; sliding down on the full keyboard's Typr
// key (`TyprKeyGesture`) shows the compact bar.

/// Where the compact bar (`false`) or the full keyboard (`true`) was last chosen with the
/// switch key. Kept in the keyboard's own defaults, so it works without Full Access.
@MainActor
struct KeyboardSurfaceChoice {
    private static let key = "typr.keyboardShowsCompactBar"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The compact dictation bar was picked over the full keyboard. Off by default.
    var showsCompactBar: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    /// Whether the full keyboard is mounted: its experiment on, and, with the Typr switch
    /// key on, the compact bar not chosen. With the switch off this is today's rule.
    static func wantsFullKeyboard(experimentOn: Bool, switchKeyOn: Bool, compactChosen: Bool) -> Bool {
        experimentOn && !(switchKeyOn && compactChosen)
    }
}
