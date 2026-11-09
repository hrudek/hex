import Foundation

/// The custom vocabulary experiment's switch and terms in the shared App Group.
nonisolated struct CustomVocabularySettings {
    static let maxTermCount = 100
    static let maxTermLength = 64
    static let maxSoundsLikePerTerm = 10

    private enum Key {
        static let enabled = "experiments.customVocabulary"
        static let terms = "customVocabulary.terms"
        /// Added later as a separate key, so the term list keeps its original format.
        static let soundsLike = "customVocabulary.soundsLike"
    }

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// Experiment: listed terms are spelled Typr's way after dictation. Off by default.
    var isEnabled: Bool {
        get { defaults?.bool(forKey: Key.enabled) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.enabled) }
    }

    /// The saved terms, always sanitized in the order they were added.
    var terms: [String] {
        get { Self.sanitize(defaults?.stringArray(forKey: Key.terms) ?? []) }
        nonmutating set { defaults?.set(Self.sanitize(newValue), forKey: Key.terms) }
    }

    /// Empty while the experiment is off, so dictation stays exactly as it is today.
    var activeTerms: [String] {
        isEnabled ? terms : []
    }

    /// Optional "sounds like" forms per saved term (what the speech engine writes instead,
    /// e.g. "Herder" for "herdr"), keyed by the term's spelling key. Forms of a term that is
    /// no longer saved are ignored.
    var soundsLike: [String: [String]] {
        let stored = defaults?.dictionary(forKey: Key.soundsLike) as? [String: [String]] ?? [:]
        return Self.sanitize(soundsLike: stored, terms: terms)
    }

    func soundsLike(for term: String) -> [String] {
        soundsLike[VocabularySpelling.normalizedKey(term)] ?? []
    }

    func setSoundsLike(_ forms: [String], for term: String) {
        var all = soundsLike
        all[VocabularySpelling.normalizedKey(term)] = forms
        defaults?.set(Self.sanitize(soundsLike: all, terms: terms), forKey: Key.soundsLike)
    }

    /// Spelling rules while the experiment is on: every term first (so a term always keeps its
    /// own spelling), then its sounds-like forms. Empty while off.
    var activeRules: [VocabularySpelling.Rule] {
        guard isEnabled else { return [] }
        return Self.rules(terms: terms, soundsLike: soundsLike)
    }

    static func rules(terms: [String], soundsLike: [String: [String]]) -> [VocabularySpelling.Rule] {
        var rules = terms.map(VocabularySpelling.Rule.init(term:))
        for term in terms {
            for form in soundsLike[VocabularySpelling.normalizedKey(term)] ?? [] {
                rules.append(VocabularySpelling.Rule(match: form, spelling: term))
            }
        }
        return rules
    }

    /// Keeps forms of saved terms only: trimmed, 2+ letters or digits, at most 64 characters,
    /// never the spelling key of any saved term, unique across all terms, ten per term.
    static func sanitize(soundsLike raw: [String: [String]], terms: [String]) -> [String: [String]] {
        let termKeys = terms.map(VocabularySpelling.normalizedKey)
        var seen = Set(termKeys)
        var result: [String: [String]] = [:]
        for termKey in termKeys {
            var forms: [String] = []
            for rawForm in raw[termKey] ?? [] {
                let form = rawForm.components(separatedBy: .newlines).joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                guard !form.isEmpty, form.count <= maxTermLength else { continue }
                let key = VocabularySpelling.normalizedKey(form)
                guard key.count >= 2, seen.insert(key).inserted else { continue }
                forms.append(form)
                if forms.count == maxSoundsLikePerTerm { break }
            }
            if !forms.isEmpty { result[termKey] = forms }
        }
        return result
    }

    /// Splits the editor's comma-separated field into forms.
    static func parseSoundsLike(_ field: String) -> [String] {
        field.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Trims each term, drops blanks, terms whose letters and digits are shorter
    /// than two characters, duplicates of the same spelling key, terms longer than
    /// 64 characters, and anything past Apple's 100 contextual-string limit.
    static func sanitize(_ rawTerms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawTerm in rawTerms {
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= maxTermLength else { continue }

            let key = VocabularySpelling.normalizedKey(term)
            guard key.count >= 2, seen.insert(key).inserted else { continue }

            result.append(term)
            if result.count == maxTermCount {
                break
            }
        }

        return result
    }
}
