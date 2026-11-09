import UIKit

/// Typr: German layer for `AutocorrectEngine` (umlaut digraphs, ß, German typo fixes).
/// All German logic lives here so the upstream engine file only carries small hooks.
@MainActor
final class GermanAutocorrect {
    /// `nil` when the device has no German dictionary; only the built-in table works then.
    let checker: TextChecking?

    init(checker: TextChecking?) {
        self.checker = checker
    }

    static func system() -> GermanAutocorrect {
        let languages = UITextChecker.availableLanguages.filter { $0.hasPrefix("de") }
        let chosen = languages.first(where: { $0 == "de_DE" }) ?? languages.first
        guard let chosen else { return GermanAutocorrect(checker: nil) }
        return GermanAutocorrect(checker: SystemTextChecker(language: chosen))
    }

    func warmUp() {
        (checker as? SystemTextChecker)?.warmUp()
    }

    func isValid(_ word: String) -> Bool {
        guard let checker else { return false }
        return checker.isWordValid(word)
    }

    func guesses(for word: String) -> [String] {
        Array((checker?.guesses(for: word) ?? []).prefix(8))
    }

    /// English fixes that must not fire when German is on (`im` is a German word).
    func blocksEnglishFix(_ lower: String) -> Bool {
        if Self.blockedEnglishFixes.contains(lower) { return true }
        return lower.count >= 2 && isValid(lower)
    }

    // MARK: - Umlauts

    private static let digraphs: [(ascii: String, replacement: String)] = [
        ("ae", "ä"), ("oe", "ö"), ("ue", "ü"), ("ss", "ß"),
    ]

    /// Returns the German spelling for a token typed with `ae/oe/ue/ss`, or nil.
    func umlautReplacement(for token: String, englishValid: Bool) -> String? {
        guard token.count >= 3, !token.contains("'"), !englishValid else { return nil }
        let lower = token.lowercased()
        guard Self.digraphs.contains(where: { lower.contains($0.ascii) }) else { return nil }
        if isValid(token) || isValid(lower) { return nil }

        if let hit = Self.commonUmlautWords[lower] {
            return AutocorrectEngine.matchCase(of: token, onto: hit)
        }
        guard checker != nil else { return nil }

        let variants = Self.variants(of: lower)
        var accepted: [(variant: String, spelled: String)] = []
        for variant in variants {
            if isValid(variant) {
                accepted.append((variant, variant))
            } else {
                let capitalised = variant.prefix(1).uppercased() + variant.dropFirst()
                if isValid(capitalised) { accepted.append((variant, capitalised)) }
            }
        }
        guard !accepted.isEmpty else { return nil }

        let ranked = guesses(for: token).map { $0.lowercased() }
        var chosen: (variant: String, spelled: String)?
        var bestRank = Int.max
        for item in accepted {
            if let rank = ranked.firstIndex(of: item.variant), rank < bestRank {
                bestRank = rank
                chosen = item
            }
        }
        if chosen == nil {
            chosen = accepted.max { substitutions($0.variant, lower) < substitutions($1.variant, lower) }
        }
        guard let chosen else { return nil }
        return AutocorrectEngine.matchCase(of: token, onto: chosen.spelled)
    }

    private func substitutions(_ variant: String, _ original: String) -> Int {
        original.count - variant.count
    }

    /// Every combination of replacing each digraph occurrence (at most 4 occurrences), minus the identity.
    static func variants(of lower: String) -> [String] {
        var parts: [[String]] = []
        let chars = Array(lower)
        var i = 0
        var occurrences = 0
        while i < chars.count {
            if i + 1 < chars.count,
               let hit = digraphs.first(where: { Array($0.ascii) == [chars[i], chars[i + 1]] }) {
                occurrences += 1
                if occurrences > 4 { return [] }
                parts.append([hit.ascii, hit.replacement])
                i += 2
            } else {
                parts.append([String(chars[i])])
                i += 1
            }
        }
        var results = [""]
        for options in parts {
            results = results.flatMap { prefix in options.map { prefix + $0 } }
        }
        return results.filter { $0 != lower }
    }

    // MARK: - Typo cost

    private static let fold: [Character: Character] = ["ä": "a", "ö": "o", "ü": "u", "ß": "s"]

    /// Single-edit cost where an umlaut or ß in the target counts as a cheap 0.4 swap for its plain letter.
    func costAdjustedForUmlauts(from source: String, to target: String) -> Double? {
        let direct = AutocorrectEngine.singleEditKeyboardCost(from: source, to: target)
        let folded = String(target.map { Self.fold[$0] ?? $0 })
        guard folded != target else { return direct }
        // A missing umlaut ("fur" for "für") is cheaper than an ordinary
        // substitution, so it wins over the direct edit cost.
        let umlaut: Double?
        if folded == source {
            umlaut = 0.4
        } else if let base = AutocorrectEngine.singleEditKeyboardCost(from: source, to: folded) {
            umlaut = base + 0.4
        } else {
            umlaut = nil
        }
        switch (direct, umlaut) {
        case let (d?, u?): return min(d, u)
        case let (d?, nil): return d
        case let (nil, u?): return u
        case (nil, nil): return nil
        }
    }

    // MARK: - Built-in table

    /// Keys whose ASCII form is never a valid German or English word.
    static let blockedEnglishFixes: Set<String> = ["im"]

    static let commonUmlautWords: [String: String] = [
        "fuer": "für", "ueber": "über", "moechte": "möchte", "moechten": "möchten",
        "wuerde": "würde", "wuerden": "würden", "koennen": "können", "koennte": "könnte",
        "koennten": "könnten", "muessen": "müssen", "muesste": "müsste", "schoen": "schön",
        "waere": "wäre", "waeren": "wären", "haette": "hätte", "haetten": "hätten",
        "spaeter": "später", "natuerlich": "natürlich", "zurueck": "zurück",
        "gruesse": "Grüße", "gruss": "Gruß", "fuenf": "fünf", "zwoelf": "zwölf",
        "aendern": "ändern", "aenderung": "Änderung", "oeffnen": "öffnen",
        "moeglich": "möglich", "unmoeglich": "unmöglich", "taeglich": "täglich",
        "naechste": "nächste", "naechsten": "nächsten", "frueh": "früh",
        "frueher": "früher", "schluessel": "Schlüssel", "maedchen": "Mädchen",
        "maerz": "März", "muenchen": "München", "oesterreich": "Österreich",
        "koeln": "Köln", "strasse": "straße", "heiss": "heiß", "weiss": "weiß",
        "fuesse": "Füße", "schliessen": "schließen", "gefuehl": "Gefühl",
        "gefaehrlich": "gefährlich", "waehrend": "während", "waehlen": "wählen",
        "traeumen": "träumen", "buero": "Büro", "buecher": "Bücher", "tuer": "Tür",
        "faellt": "fällt", "faehig": "fähig", "faehrt": "fährt", "glueck": "Glück",
        "gluecklich": "glücklich", "hoeren": "hören", "hoert": "hört", "kuerze": "Kürze",
        "laecheln": "lächeln", "loesen": "lösen", "loesung": "Lösung", "pruefen": "prüfen",
        "ruecken": "rücken", "saetze": "Sätze", "tschuess": "tschüss", "uebung": "Übung",
        "ueberall": "überall", "ueberhaupt": "überhaupt", "verstaendlich": "verständlich",
        "vorschlaege": "Vorschläge", "wuensche": "Wünsche", "zaehlen": "zählen",
    ]
}
