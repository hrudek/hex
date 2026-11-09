import Foundation

/// Everything one dictation needs from vocabulary, frozen at recording start: the Apple Speech
/// hints, the spelling fixes before AI cleanup (Custom vocabulary first, then the built-in
/// tech glossary), the terms named to cleanup, and the spelling restore after formatting.
/// Callers never order the passes or merge the lists themselves.
nonisolated struct DictationVocabulary: Sendable {
    enum Source: String, Sendable {
        case custom
        case builtIn = "built-in"
    }

    struct Prepared: Equatable, Sendable {
        /// The recognized text with spellings fixed, handed to cleanup or formatting.
        let text: String
        /// Spellings for AI cleanup: every active user term, then the glossary terms that
        /// appear in this dictation.
        let cleanupTerms: [String]
    }

    /// Apple's documented limit for contextual strings.
    static let maxSpeechHints = CustomVocabularySettings.maxTermCount

    /// Active Custom vocabulary terms (empty while that experiment is off).
    let userTerms: [String]
    private let userRules: [VocabularySpelling.Rule]

    init(userTerms: [String], soundsLike: [String: [String]] = [:]) {
        self.userTerms = userTerms
        userRules = CustomVocabularySettings.rules(terms: userTerms, soundsLike: soundsLike)
    }

    /// Reads the Custom vocabulary switch, terms and sounds-like forms once.
    init(settings: CustomVocabularySettings) {
        if settings.isEnabled {
            self.init(userTerms: settings.terms, soundsLike: settings.soundsLike)
        } else {
            self.init(userTerms: [])
        }
    }

    /// The user's terms first, then the glossary's listed terms, without duplicate spellings,
    /// capped at Apple's limit of 100.
    var speechHints: [String] {
        var seen = Set<String>()
        let all = (userTerms + TechGlossary.listedTerms).filter {
            seen.insert(VocabularySpelling.normalizedKey($0)).inserted
        }
        return Array(all.prefix(Self.maxSpeechHints))
    }

    /// Spelling keys the glossary must leave alone, so the user's own terms and forms win:
    /// every form, every term and each word of a term (a user's "Herdr Tool" keeps its "Herdr").
    private var protectedKeys: Set<String> {
        var keys = Set<String>()
        for rule in userRules {
            keys.insert(VocabularySpelling.normalizedKey(rule.match))
            keys.insert(VocabularySpelling.normalizedKey(rule.spelling))
            for word in rule.spelling.split(whereSeparator: { $0.isWhitespace || $0 == "-" }) {
                keys.insert(VocabularySpelling.normalizedKey(String(word)))
            }
        }
        return keys
    }

    /// Fixes spellings in the recognized text before cleanup, reporting each replacement.
    func beforeCleanup(_ recognized: String,
                       onReplacement: ((_ before: String, _ after: String, _ term: String, _ source: Source) -> Void)? = nil)
        -> Prepared {
        let reportCustom: ((String, String, String) -> Void)? = onReplacement.map { report in
            { before, after, term in report(before, after, term, .custom) }
        }
        let reportBuiltIn: ((String, String, String) -> Void)? = onReplacement.map { report in
            { before, after, term in report(before, after, term, .builtIn) }
        }
        let protected = protectedKeys
        let custom = VocabularySpelling.apply(rules: userRules, to: recognized, onReplacement: reportCustom)
        let glossary = TechGlossary.apply(to: custom, protectedKeys: protected, onReplacement: reportBuiltIn)
        let glossaryTerms = glossary.terms.filter { !protected.contains(VocabularySpelling.normalizedKey($0)) }
        return Prepared(text: glossary.text, cleanupTerms: userTerms + glossaryTerms)
    }

    /// Restores the user's spellings after a style changed their case ("iPhone" → "IPhone").
    /// The glossary does not run again: its fixes are already in the text cleanup received.
    func afterFormatting(_ formatted: String,
                         onReplacement: ((_ before: String, _ after: String, _ term: String) -> Void)? = nil) -> String {
        VocabularySpelling.apply(rules: userRules, to: formatted, onReplacement: onReplacement)
    }
}
