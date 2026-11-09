import Foundation

/// A deterministic pass over an accepted cleanup answer. The on-device model joins English and
/// technical compounds with hyphens ("Pull-Request", "Speech-to-Text-Apps"); the owner writes them
/// with spaces ("Pull Request", "Speech to Text Apps"). Conservative: a hyphenated word is split only
/// when every part is a listed English or technical word. Everything else keeps its hyphen: E-Mail and
/// other one-letter parts, abbreviations ("PR-Feedback", "AI-Modell"), numbers and ranges ("5-10",
/// "iPhone-17"), German compounds ("Feedback-Menü", "Speech-to-Text-Nachrichten"), and any word inside
/// a link, address or file name.
///
/// To extend: add the lowercase singular of an English or technical word to `englishWords` (a plural
/// with a trailing "s" is covered). Add only words that are not also common German compound parts.
enum CleanupHyphens {
    static let englishWords: Set<String> = [
        // Git and code review
        "pull", "request", "push", "merge", "commit", "branch", "rebase", "review", "reviewer", "worktree",
        "repo", "repository", "issue", "bug", "fix", "hotfix", "patch", "release", "deploy", "deployment",
        "build", "pipeline", "workflow", "action", "check", "feature", "flag", "code", "open", "source",
        // Apps and AI
        "speech", "text", "voice", "app", "web", "cloud", "server", "client", "agent", "bot", "prompt",
        "token", "session", "model", "chat", "message", "keyboard", "dictation", "update", "upgrade",
        "login", "account", "cache", "backend", "frontend", "framework", "library", "package", "plugin",
        "widget", "screenshot", "terminal", "shell", "script", "tab", "pane", "window", "star", "stack",
        "team", "meeting", "test", "unit", "store",
        // Product names
        "github", "gitlab", "git", "xcode", "swift", "python", "iphone", "ipad", "mac", "apple", "google",
        "testflight", "docker", "claude", "chatgpt", "openai"
    ]

    /// Allowed only between two listed words ("Speech-to-Text").
    static let connectors: Set<String> = ["to"]

    static func apply(_ text: String) -> String {
        let chunks = try! NSRegularExpression(pattern: #"\S+"#)
        let compounds = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:-[\p{L}\p{N}]+)+"#)
        let linkLike = try! NSRegularExpression(pattern: #"[/@]|\.[\p{L}\p{N}]"#)
        let source = text as NSString
        let result = NSMutableString(string: text)
        for chunk in chunks.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            // Links, addresses and file names keep every character.
            guard linkLike.firstMatch(in: text, range: chunk.range) == nil else { continue }
            for match in compounds.matches(in: text, range: chunk.range) {
                let word = source.substring(with: match.range)
                guard splits(word) else { continue }
                // "-" and " " have the same UTF-16 length, so later ranges stay valid.
                result.replaceCharacters(in: match.range, with: word.replacingOccurrences(of: "-", with: " "))
            }
        }
        return result as String
    }

    /// Whether every part of a hyphenated word is a listed English or technical word.
    static func splits(_ word: String) -> Bool {
        let parts = word.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return false }
        for (index, part) in parts.enumerated() {
            // One-letter parts (E-Mail, T-Shirt) and digits (iPhone-17, 5-10) keep the hyphen.
            guard part.count >= 2, part.allSatisfy({ $0.isLetter }) else { return false }
            // Abbreviations (PR-Feedback, AI-Modell) keep the hyphen, as German writes them.
            if part == part.uppercased() { return false }
            let lower = part.lowercased()
            if connectors.contains(lower) {
                if index == 0 || index == parts.count - 1 { return false }
                continue
            }
            let singular = lower.hasSuffix("s") ? String(lower.dropLast()) : lower
            guard englishWords.contains(lower) || englishWords.contains(singular) else { return false }
        }
        return true
    }
}
