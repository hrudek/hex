import Foundation

/// What a dictation's cleanup knows besides its transcript: the chosen dictation language and a
/// little preceding text, so the model can tell the topic ("Pulrequest" in a conversation about Git).
/// The preceding text is data only, kept in memory and never written to the dictation log.
struct CleanupContext: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        /// The host field's text before the cursor, sent by the keyboard with a warm start.
        case keyboard
        /// This app session's recent dictation results.
        case previousDictations = "previous-dictations"
    }

    /// Small on purpose: it shares the on-device model's context window with the instructions,
    /// the transcript and the answer.
    static let maximumCharacters = 300

    var language: DictationLanguage = .automatic
    var preceding: String?
    var source: Source?

    /// The keyboard's text if it has any, else the recent dictations, capped to the last
    /// `maximumCharacters` characters.
    static func make(language: DictationLanguage, keyboard: String?, previousDictations: String?) -> CleanupContext {
        if let text = tail(keyboard) {
            return CleanupContext(language: language, preceding: text, source: .keyboard)
        }
        if let text = tail(previousDictations) {
            return CleanupContext(language: language, preceding: text, source: .previousDictations)
        }
        return CleanupContext(language: language)
    }

    /// The last `limit` characters with whitespace collapsed, starting at a word; nil when empty.
    static func tail(_ text: String?, limit: Int = maximumCharacters) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var kept: [Substring] = []
        var count = 0
        for word in words.reversed() {
            let added = word.count + (kept.isEmpty ? 0 : 1)
            if count + added > limit {
                // A single word longer than the limit keeps its end only.
                if kept.isEmpty { kept.append(word.suffix(limit)) }
                break
            }
            kept.append(word)
            count += added
        }
        let result = kept.reversed().joined(separator: " ")
        return result.isEmpty ? nil : result
    }
}

/// The last few dictation results of this app session, in memory only, for cleanup context when
/// the keyboard sent none (cold start, dictating inside Typr). Entries older than `window` are ignored.
@MainActor
final class CleanupContextHistory {
    static let window: TimeInterval = 10 * 60
    static let maximumEntries = 3

    private var entries: [(text: String, at: TimeInterval)] = []

    func record(_ text: String, at time: TimeInterval) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append((trimmed, time))
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
    }

    func recent(at time: TimeInterval) -> String? {
        let fresh = entries.filter { time - $0.at <= Self.window && time >= $0.at }.map { $0.text }
        return fresh.isEmpty ? nil : fresh.joined(separator: " ")
    }

    func clear() { entries.removeAll() }
}
