import Foundation

/// The language the owner dictates in. Automatic keeps the previous behavior: Apple Speech uses the
/// first supported preferred language and cleanup may skip a language the model does not support.
/// An explicit language fixes the speech locale and tells cleanup which language to write.
/// To add a language: a case, its raw value (BCP 47 language code), label, speech locale and
/// cleanup instruction. Stored raw values must never change.
nonisolated enum DictationLanguage: String, CaseIterable, Codable, Sendable {
    case automatic
    case german = "de"
    case english = "en"

    /// The picker label, in the language itself.
    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    /// The Apple Speech locale requested for an explicit language; nil for automatic.
    var speechLocaleIdentifier: String? {
        switch self {
        case .automatic: nil
        case .german: "de-DE"
        case .english: "en-US"
        }
    }

    /// Locale identifiers Apple Speech tries in order. An explicit language comes first; the
    /// automatic order (preferred languages, current locale, en-US) follows, so dictation still
    /// works on a device without that language's speech model. The log records what was used.
    func speechLocaleCandidates(preferred: [String], current: String) -> [String] {
        var identifiers: [String] = []
        if let speechLocaleIdentifier { identifiers.append(speechLocaleIdentifier) }
        identifiers += preferred
        identifiers.append(current)
        identifiers.append("en-US")
        var seen = Set<String>()
        return identifiers.filter { seen.insert($0).inserted }
    }

    /// The cleanup prompt's language line; nil for automatic (the transcript's own language).
    var cleanupInstruction: String? {
        switch self {
        case .automatic: nil
        case .german:
            "Language: the speaker dictates German. Write the whole text in correct German. Keep English words and technical terms exactly as spoken; never translate them."
        case .english:
            "Language: the speaker dictates English. Write the whole text in correct English. Keep words from other languages exactly as spoken; never translate them."
        }
    }
}
