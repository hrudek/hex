import Foundation

/// App-only instructions, not a keyboard setting. A missing override follows future default updates.
@MainActor
struct CleanupPromptPreferences {
    private static let key = "typr.cleanupPrompt"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var instructions: String {
        guard let saved = defaults.string(forKey: Self.key), Self.canSave(saved) else {
            return CleanupPrompt.instructions
        }
        return saved
    }

    var isCustom: Bool { instructions != CleanupPrompt.instructions }

    static func canSave(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Preserve the user's exact text. Empty drafts cannot replace working instructions.
    @discardableResult
    func save(_ text: String) -> Bool {
        guard Self.canSave(text) else { return false }
        if text == CleanupPrompt.instructions {
            reset()
        } else {
            defaults.set(text, forKey: Self.key)
        }
        return true
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
