import UIKit

/// One slot in the 3-column suggestion strip above the keys.
nonisolated struct KeyboardSuggestion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Left slot (`"typed"`): keeps the exact characters and teaches Hex not to rewrite them.
        case keepLiteral
        /// Center slot: best replacement or completion (`autoReplace` highlights when Space will apply it).
        case primary(autoReplace: Bool)
        /// Right slot: runner-up completion or spelling guess.
        case secondary
    }

    let displayText: String
    let replacement: String
    let kind: Kind

    var willAutoReplace: Bool {
        if case .primary(let auto) = kind { return auto }
        return false
    }
}

/// Narrow seam over `UITextChecker` so unit tests can run deterministically or against UIKit's dictionary.
@MainActor
protocol TextChecking: AnyObject {
    func isWordValid(_ word: String) -> Bool
    func guesses(for word: String) -> [String]
    func completions(for prefix: String) -> [String]
    /// The word is valid in a language other than English that the person types, so
    /// English-only fixes (`im` -> `I'm`) must leave it alone (German `im`).
    func isValidOutsideEnglish(_ word: String) -> Bool
}

extension TextChecking {
    func isValidOutsideEnglish(_ word: String) -> Bool { false }
}

@MainActor
final class SystemTextChecker: TextChecking {
    private var checker: UITextChecker?
    /// `UITextChecker` languages, most preferred first. A word is valid when any of them
    /// knows it, and guesses and completions come from all of them.
    let languages: [String]

    init(languages: [String] = SystemTextChecker.typingLanguages()) {
        self.languages = languages.isEmpty ? ["en_US"] : languages
    }

    convenience init(language: String) {
        self.init(languages: [language])
    }

    /// The languages the person types: their keyboards and preferred languages that
    /// `UITextChecker` has a dictionary for, plus English, at most three.
    static func typingLanguages(
        preferred: [String] = Locale.preferredLanguages,
        keyboards: [String] = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage),
        available: [String] = UITextChecker.availableLanguages
    ) -> [String] {
        var result: [String] = []
        func add(_ identifier: String) {
            let normalized = identifier.replacingOccurrences(of: "-", with: "_")
            let base = normalized.split(separator: "_").first.map(String.init) ?? normalized
            let match = available.first { $0 == normalized }
                ?? available.first { $0 == base }
                ?? available.first { $0.hasPrefix(base + "_") }
            guard let match else { return }
            let matchBase = match.split(separator: "_").first.map(String.init) ?? match
            guard !result.contains(where: { $0.hasPrefix(matchBase) }) else { return }
            result.append(match)
        }
        (keyboards + preferred).forEach(add)
        add("en_US")
        return Array(result.prefix(3))
    }

    /// Warms `UITextChecker` after the keyboard's first frame commits so cold open stays < 12 ms.
    func warmUp() {
        guard checker == nil else { return }
        let instance = UITextChecker()
        for language in languages {
            _ = instance.rangeOfMisspelledWord(
                in: "hello",
                range: NSRange(location: 0, length: 5),
                startingAt: 0,
                wrap: false,
                language: language
            )
        }
        checker = instance
    }

    private var activeChecker: UITextChecker {
        if let checker { return checker }
        let instance = UITextChecker()
        checker = instance
        return instance
    }

    private func isValid(_ word: String, in language: String) -> Bool {
        let range = NSRange(location: 0, length: (word as NSString).length)
        guard range.length > 0 else { return true }
        let misspelled = activeChecker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        )
        return misspelled.location == NSNotFound
    }

    func isWordValid(_ word: String) -> Bool {
        languages.contains { isValid(word, in: $0) }
    }

    func isValidOutsideEnglish(_ word: String) -> Bool {
        languages.contains { !$0.hasPrefix("en") && isValid(word, in: $0) }
    }

    func guesses(for word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        guard range.length > 0 else { return [] }
        return Self.interleave(languages.map {
            activeChecker.guesses(forWordRange: range, in: word, language: $0) ?? []
        })
    }

    func completions(for prefix: String) -> [String] {
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        guard range.length > 0 else { return [] }
        return Self.interleave(languages.map {
            activeChecker.completions(forPartialWordRange: range, in: prefix, language: $0) ?? []
        })
    }

    /// Takes each language's best candidate in turn, dropping duplicates.
    static func interleave(_ lists: [[String]]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        let longest = lists.map(\.count).max() ?? 0
        for index in 0..<longest {
            for list in lists where index < list.count {
                if seen.insert(list[index].lowercased()).inserted {
                    result.append(list[index])
                }
            }
        }
        return result
    }
}

/// Persists words the user explicitly kept twice, bounded to 2,000 words / 64 KB in the App Group.
@MainActor
final class LearnedWordsStore {
    static let defaultsKey = "keyboard.learnedWords"
    static let maxWords = 2_000
    static let maxBytes = 64 * 1024

    private let defaults: UserDefaults?
    private(set) var words: [String] = []
    private var wordSet: Set<String> = []
    private var sessionKeepCounts: [String: Int] = [:]

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
        load()
    }

    func contains(_ word: String) -> Bool {
        wordSet.contains(word.lowercased())
    }

    /// Records an explicit keep (via `"quoted"` chip or Backspace-revert). Two keeps persist the word.
    func recordExplicitKeep(_ raw: String) {
        let key = raw.lowercased()
        guard key.count >= 2, key.count <= 40 else { return }
        let count = (sessionKeepCounts[key] ?? 0) + 1
        sessionKeepCounts[key] = count
        if count >= 2 {
            learn(key)
        }
    }

    func learn(_ raw: String) {
        let key = raw.lowercased()
        guard !key.isEmpty, !wordSet.contains(key) else { return }
        words.append(key)
        wordSet.insert(key)
        while words.count > Self.maxWords {
            let evicted = words.removeFirst()
            wordSet.remove(evicted)
        }
        save()
    }

    private func load() {
        guard let data = defaults?.data(forKey: Self.defaultsKey),
              data.count <= Self.maxBytes,
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        words = Array(decoded.suffix(Self.maxWords))
        wordSet = Set(words)
    }

    private func save() {
        guard let defaults else { return }
        while !words.isEmpty {
            if let data = try? JSONEncoder().encode(words), data.count <= Self.maxBytes {
                defaults.set(data, forKey: Self.defaultsKey)
                return
            }
            let evicted = words.removeFirst()
            wordSet.remove(evicted)
        }
    }
}

/// Aggressive (German-leaning) on-device suggestions and replace-on-space engine combining `UILexicon`,
/// deterministic contractions/transpositions, QWERTY-ranked `UITextChecker`, and `LearnedWordsStore`.
@MainActor
final class AutocorrectEngine {
    struct AppliedCorrection: Equatable {
        let original: String
        let insertedText: String
    }

    let checker: TextChecking
    let learnedWords: LearnedWordsStore
    var isEnabled = true
    private var lexiconShortcuts: [String: String] = [:]
    private var lexiconTerms: [String] = []
    private var lexiconTermSet: Set<String> = []
    /// Last token and its replacement: suggestions and Space ask for the same word.
    private var replacementCache: (token: String, replacement: String?)?
    private var suppressedInSession: Set<String> = []
    private(set) var lastCorrection: AppliedCorrection?

    init(
        checker: TextChecking? = nil,
        learnedWords: LearnedWordsStore? = nil
    ) {
        self.checker = checker ?? SystemTextChecker()
        self.learnedWords = learnedWords ?? LearnedWordsStore()
    }

    func loadLexicon(_ lexicon: UILexicon) {
        loadLexiconEntries(lexicon.entries.map { ($0.userInput, $0.documentText) })
    }

    func loadLexiconEntries(_ entries: [(userInput: String, documentText: String)]) {
        var shortcuts: [String: String] = [:]
        var terms: [String] = []
        for (input, output) in entries {
            let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedInput.isEmpty, !trimmedOutput.isEmpty else { continue }
            if trimmedInput.lowercased() != trimmedOutput.lowercased() {
                shortcuts[trimmedInput.lowercased()] = trimmedOutput
            } else {
                terms.append(trimmedOutput)
            }
        }
        lexiconShortcuts = shortcuts
        lexiconTerms = terms
        lexiconTermSet = Set(terms.map { $0.lowercased() })
        replacementCache = nil
    }

    func clearPendingUndo() {
        lastCorrection = nil
    }

    func recordAppliedCorrection(original: String, insertedText: String) {
        lastCorrection = AppliedCorrection(original: original, insertedText: insertedText)
    }

    func consumePendingUndo() -> AppliedCorrection? {
        defer { lastCorrection = nil }
        return lastCorrection
    }

    func suppressAndKeep(_ word: String) {
        suppressedInSession.insert(word.lowercased())
        learnedWords.recordExplicitKeep(word)
    }

    // MARK: - Token inspection

    /// Extracts the active word right before the caret, returning `nil` inside URLs, handles, paths, or numbers.
    static func currentToken(in beforeInput: String?) -> String? {
        guard let beforeInput, !beforeInput.isEmpty else { return nil }
        var end = beforeInput.endIndex
        var start = end
        while start > beforeInput.startIndex {
            let prev = beforeInput.index(before: start)
            let ch = beforeInput[prev]
            if ch.isLetter || (ch == "'" && start < end && prev > beforeInput.startIndex && beforeInput[beforeInput.index(before: prev)].isLetter) {
                start = prev
            } else {
                break
            }
        }
        guard start < end else { return nil }
        // Guard against tokens attached to `@`, `/`, `.`, `#`, `_`, `-`, or digits.
        if start > beforeInput.startIndex {
            let boundary = beforeInput[beforeInput.index(before: start)]
            if boundary == "@" || boundary == "/" || boundary == "." || boundary == "#"
                || boundary == "_" || boundary == "-" || boundary == ":" || boundary.isNumber {
                return nil
            }
        }
        let token = String(beforeInput[start..<end])
        guard token.first?.isLetter == true else { return nil }
        return token
    }

    // MARK: - Suggestions & Replace-on-Space

    func suggestions(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?
    ) -> [KeyboardSuggestion] {
        guard field == .text, autocorrectionType != .no else { return [] }
        guard let token = Self.currentToken(in: beforeInput) else { return [] }

        let lower = token.lowercased()
        let allowAuto = isEnabled
            && !suppressedInSession.contains(lower)
            && !learnedWords.contains(lower)
            && !Self.shorthandAllowlist.contains(lower)

        let autoFix = allowAuto ? cautiousReplacement(for: token) : nil
        var pool: [String] = []

        if let autoFix {
            pool.append(autoFix)
        } else if let suggested = Self.suggestOnlyContractions[lower], !checker.isValidOutsideEnglish(token) {
            pool.append(Self.matchCase(of: token, onto: suggested))
        }

        // Prefix matches from Contacts / lexicon terms.
        if lower.count >= 2 {
            for term in lexiconTerms where term.lowercased().hasPrefix(lower) && term.lowercased() != lower {
                let candidate = Self.matchCase(of: token, onto: term)
                if !pool.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                    pool.append(candidate)
                }
                if pool.count >= 3 { break }
            }
        }

        // Spelling guesses or prefix completions from `UITextChecker`.
        if pool.count < 2 && token.count >= 2 {
            let valid = Self.shorthandAllowlist.contains(lower) || learnedWords.contains(lower) || checker.isWordValid(token)
            if !valid {
                for guess in rankedGuesses(for: token) {
                    let cased = Self.matchCase(of: token, onto: guess)
                    if cased.caseInsensitiveCompare(token) != .orderedSame,
                       !pool.contains(where: { $0.caseInsensitiveCompare(cased) == .orderedSame }) {
                        pool.append(cased)
                    }
                    if pool.count >= 2 { break }
                }
            }
            if pool.count < 2 {
                let completions = checker.completions(for: token)
                    .filter { $0.count > token.count && $0.count <= token.count + 8 }
                    .sorted { a, b in
                        if a.count != b.count { return a.count < b.count }
                        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                    }
                for item in completions {
                    let cased = Self.matchCase(of: token, onto: item)
                    if !pool.contains(where: { $0.caseInsensitiveCompare(cased) == .orderedSame }) {
                        pool.append(cased)
                    }
                    if pool.count >= 2 { break }
                }
            }
        }

        let literal = KeyboardSuggestion(displayText: "“\(token)”", replacement: token, kind: .keepLiteral)
        let primary: KeyboardSuggestion = if let first = pool.first {
            KeyboardSuggestion(
                displayText: first,
                replacement: first,
                kind: .primary(autoReplace: autoFix != nil)
            )
        } else {
            KeyboardSuggestion(displayText: token, replacement: token, kind: .primary(autoReplace: false))
        }
        let secondary: KeyboardSuggestion? = if pool.count >= 2 {
            KeyboardSuggestion(displayText: pool[1], replacement: pool[1], kind: .secondary)
        } else {
            nil
        }
        return [literal, primary] + (secondary.map { [$0] } ?? [])
    }

    /// Returns `(tokenToDelete, replacement)` only when cautious autocorrect is confident.
    func replacementOnSpace(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?
    ) -> (original: String, replacement: String)? {
        guard isEnabled, field == .text, autocorrectionType != .no else { return nil }
        guard let token = Self.currentToken(in: beforeInput) else { return nil }
        let lower = token.lowercased()
        guard !suppressedInSession.contains(lower),
              !learnedWords.contains(lower),
              !Self.shorthandAllowlist.contains(lower) else { return nil }
        guard let fix = cautiousReplacement(for: token) else { return nil }
        return (token, fix)
    }

    private func cautiousReplacement(for token: String) -> String? {
        if let cache = replacementCache, cache.token == token { return cache.replacement }
        let replacement = computeReplacement(for: token)
        replacementCache = (token, replacement)
        return replacement
    }

    private func computeReplacement(for token: String) -> String? {
        let lower = token.lowercased()
        // 1. Explicit iOS Text Replacement (`omw` -> `On my way!`).
        if let shortcut = lexiconShortcuts[lower] {
            return shortcut
        }
        // Contacts and other lexicon terms (`Michaela`) are words, even without a dictionary entry.
        if lexiconTermSet.contains(lower) { return nil }
        // Leave ALL-CAPS acronyms (`API`, `PR`, `NYC`) alone unless matched in `UILexicon` above,
        // except unambiguous all-caps contractions/typos of 3+ letters (`DONT` -> `DON'T`, `TEH` -> `THE`).
        let isAllCaps = token.count >= 2 && token == token.uppercased() && token != token.lowercased()
        // Leave camelCase / PascalCase identifiers (`HexKey`, `iOS`) alone.
        let hasInternalCaps = token.dropFirst().contains(where: \.isUppercase) && !isAllCaps
        if hasInternalCaps { return nil }

        // 2. Deterministic contractions and common QWERTY transpositions, unless the word
        // belongs to another language the person types (German `im`, `wich`).
        if let fixed = Self.unambiguousFixes[lower], !checker.isValidOutsideEnglish(token) {
            if isAllCaps && token.count < 3 { return nil }
            return Self.matchCase(of: token, onto: fixed)
        }

        if isAllCaps { return nil }

        // 3. Common German slips (`nciht` -> `nicht`), when no language the person types knows the word.
        let wordIsValid = checker.isWordValid(token)
        if !wordIsValid, let fixed = Self.germanFixes[lower] {
            return Self.matchCase(of: token, onto: fixed)
        }

        // 4. Aggressive `UITextChecker` typo fix on words of 3+ characters, never rewriting valid
        // words. Several keyboard edits are allowed, more for longer words and for German.
        guard token.count >= 3, !token.contains("'"), !wordIsValid else { return nil }

        // German typed on QWERTY without umlauts or ß (`fuer`, `schoen`, `strasse`).
        if let spelled = germanSpelling(of: token) {
            return spelled
        }

        var bestGuess: String?
        var bestCost = Double.greatestFiniteMagnitude
        for (rank, rawGuess) in checker.guesses(for: token).prefix(12).enumerated() {
            // Missing spaces are handled by `splitReplacement`, which also fixes each half.
            guard !rawGuess.contains(" ") else { continue }
            let normalizedGuess = rawGuess.replacingOccurrences(of: "'", with: "").lowercased()
            guard normalizedGuess != lower || rawGuess != token else { continue }
            guard let editCost = Self.keyboardEditCost(from: lower, to: normalizedGuess) else { continue }
            let budget = Self.correctionBudget(forLength: token.count)
                + (checker.isValidOutsideEnglish(rawGuess) ? Self.germanBonus : 0)
            let cost = editCost + Double(rank) * 0.05
            if cost <= budget, cost < bestCost {
                bestCost = cost
                bestGuess = rawGuess
            }
        }

        // 5. A missing space (`wiegehts` -> `wie geht's`), each half allowed its own typo.
        if let split = splitReplacement(for: token), split.cost < bestCost {
            return split.text
        }
        guard let bestGuess else { return nil }
        return Self.matchCase(of: token, onto: bestGuess)
    }

    /// Fixed cost of inserting the missing space.
    static let splitPenalty = 0.4
    /// Most a guessed half of a split may cost: about one typo.
    static let splitPartBudget = 1.2

    /// Best way to read `token` as two words run together, or `nil`. Each half is a valid word,
    /// a known slip, or one cheap typo away from a guess; only one half may need a guess.
    private func splitReplacement(for token: String) -> (text: String, cost: Double)? {
        let chars = Array(token)
        guard chars.count >= 5, chars.count <= 30 else { return nil }
        var best: (text: String, cost: Double)?
        for cut in 2...(chars.count - 2) {
            let left = String(chars[..<cut])
            let right = String(chars[cut...])
            // Leave German compounds alone: `Haus` + `Tür` is one word, but `das` + `Haus` is two.
            if left.count >= 4, isNounOnly(right) { continue }
            guard let resolvedLeft = resolvePart(left, allowGuess: false)
                ?? (checker.isWordValid(right) ? resolvePart(left, allowGuess: true) : nil) else { continue }
            let rightAllowsGuess = resolvedLeft.cost == 0
            guard let resolvedRight = resolvePart(right, allowGuess: rightAllowsGuess) else { continue }
            let cost = Self.splitPenalty + resolvedLeft.cost + resolvedRight.cost
            guard cost <= Self.correctionBudget(forLength: chars.count) + Self.germanBonus else { continue }
            if best == nil || cost < best!.cost {
                let first = Self.matchCase(of: left, onto: resolvedLeft.word)
                best = (first + " " + resolvedRight.word, cost)
            }
        }
        return best
    }

    /// One half of a split: its own spelling, a known slip, or (with `allowGuess`) its best guess.
    private func resolvePart(_ part: String, allowGuess: Bool) -> (word: String, cost: Double)? {
        let lower = part.lowercased()
        if checker.isWordValid(part) { return (part, 0) }
        if let noun = Self.capitalized(lower), checker.isWordValid(noun), !checker.isWordValid(lower) {
            return (noun, 0.05)
        }
        if let fixed = Self.germanFixes[lower] { return (Self.matchCase(of: part, onto: fixed), 0.1) }
        if let fixed = Self.unambiguousFixes[lower], lower.count >= 3, !checker.isValidOutsideEnglish(part) {
            return (Self.matchCase(of: part, onto: fixed), 0.1)
        }
        guard part.count >= 3 else { return nil }
        if let spelled = germanSpelling(of: part) { return (spelled, 0.3) }
        guard allowGuess else { return nil }
        var best: (word: String, cost: Double)?
        for (rank, guess) in checker.guesses(for: part).prefix(6).enumerated() where !guess.contains(" ") {
            let normalized = guess.replacingOccurrences(of: "'", with: "").lowercased()
            guard let editCost = Self.keyboardEditCost(from: lower, to: normalized) else { continue }
            // One cheap typo per half: a split already guesses where the space goes.
            let budget = min(Self.splitPartBudget, Self.correctionBudget(forLength: part.count))
            let cost = editCost + Double(rank) * 0.05
            if cost <= budget, cost < (best?.cost ?? .greatestFiniteMagnitude) {
                best = (Self.matchCase(of: part, onto: guess), cost)
            }
        }
        return best
    }

    /// True when `word` is valid only capitalised: a German noun (`Haus`, `Tür`).
    private func isNounOnly(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard let noun = Self.capitalized(lower) else { return false }
        return !checker.isWordValid(lower) && checker.isWordValid(noun)
    }

    private static func capitalized(_ lower: String) -> String? {
        guard let first = lower.first, first.isLetter else { return nil }
        return first.uppercased() + lower.dropFirst()
    }

    /// Extra edit budget for a guess from a non-English dictionary the person types (German).
    static let germanBonus = 0.6

    /// How much weighted keyboard edit cost a correction may spend, growing with the word.
    static func correctionBudget(forLength length: Int) -> Double {
        switch length {
        case ..<4: 1.25
        case 4: 1.6
        case 5...6: 2.1
        case 7...9: 2.7
        default: 3.3
        }
    }

    /// Rewrites `ae`/`oe`/`ue`/`ss` to `ä`/`ö`/`ü`/`ß` when that spelling is a valid word,
    /// trying the capitalised form too for German nouns (`groesse` -> `Größe`).
    private func germanSpelling(of token: String) -> String? {
        let lower = token.lowercased()
        let digraphs: [(String, String)] = [("ae", "ä"), ("oe", "ö"), ("ue", "ü"), ("ss", "ß")]
        var positions: [(Range<String.Index>, String)] = []
        for (pair, umlaut) in digraphs {
            var search = lower.startIndex..<lower.endIndex
            while let found = lower.range(of: pair, range: search) {
                positions.append((found, umlaut))
                search = found.upperBound..<lower.endIndex
            }
        }
        guard !positions.isEmpty, positions.count <= 4 else { return nil }
        positions.sort { $0.0.lowerBound < $1.0.lowerBound }
        // Every non-empty subset, most replacements first.
        let subsets = (1..<(1 << positions.count)).sorted { $0.nonzeroBitCount > $1.nonzeroBitCount }
        for mask in subsets {
            var candidate = ""
            var cursor = lower.startIndex
            var overlaps = false
            for (index, (range, umlaut)) in positions.enumerated() where mask & (1 << index) != 0 {
                if range.lowerBound < cursor { overlaps = true; break }
                candidate += String(lower[cursor..<range.lowerBound]) + umlaut
                cursor = range.upperBound
            }
            if overlaps { continue }
            candidate += String(lower[cursor...])
            if checker.isWordValid(candidate) {
                return Self.matchCase(of: token, onto: candidate)
            }
            let noun = candidate.prefix(1).uppercased() + candidate.dropFirst()
            if checker.isWordValid(noun) {
                return Self.matchCase(of: token, onto: noun)
            }
        }
        return nil
    }

    private func rankedGuesses(for token: String) -> [String] {
        let lower = token.lowercased()
        return checker.guesses(for: token)
            .prefix(8)
            .enumerated()
            .sorted { a, b in
                let costA = Self.keyboardEditCost(
                    from: lower,
                    to: a.element.replacingOccurrences(of: "'", with: "").lowercased()
                ) ?? (4.0 + Double(abs(a.element.count - token.count)) * 0.3)
                let costB = Self.keyboardEditCost(
                    from: lower,
                    to: b.element.replacingOccurrences(of: "'", with: "").lowercased()
                ) ?? (4.0 + Double(abs(b.element.count - token.count)) * 0.3)
                return (costA + Double(a.offset) * 0.08) < (costB + Double(b.offset) * 0.08)
            }
            .map(\.element)
    }

    // MARK: - Case matching & QWERTY distance

    static func matchCase(of typed: String, onto target: String) -> String {
        guard !typed.isEmpty, !target.isEmpty else { return target }
        if typed.count >= 2 && typed == typed.uppercased() && typed != typed.lowercased() {
            return target.uppercased()
        }
        // Preserve intentional casing in `I`, `I'm`, `iPhone`, etc. unless `typed` started capitalized.
        if target != target.lowercased() {
            if typed.first?.isUppercase == true, let first = target.first, first.isLowercase {
                return first.uppercased() + target.dropFirst()
            }
            return target
        }
        if typed.first?.isUppercase == true, let first = target.first {
            return first.uppercased() + target.dropFirst()
        }
        return target
    }

    /// Returns a weighted cost if `source` and `target` are within 1 Damerau-Levenshtein edit; `nil` otherwise.
    static func singleEditKeyboardCost(from source: String, to target: String) -> Double? {
        if source == target { return 0 }
        let s = Array(source)
        let t = Array(target)
        let ds = s.count - t.count
        guard abs(ds) <= 1 else { return nil }

        if ds == 0 {
            var diffs: [Int] = []
            for i in 0..<s.count where s[i] != t[i] {
                diffs.append(i)
                if diffs.count > 2 { return nil }
            }
            if diffs.count == 1 {
                let i = diffs[0]
                // A missing umlaut on QWERTY (`grun` -> `grün`) is as likely as a neighbour key.
                if isUmlautPair(s[i], t[i]) { return 0.55 }
                return areAdjacentKeys(s[i], t[i]) ? 0.65 : 1.15
            }
            if diffs.count == 2, diffs[1] == diffs[0] + 1,
               s[diffs[0]] == t[diffs[1]], s[diffs[1]] == t[diffs[0]] {
                return 0.60
            }
            return nil
        }

        // Single insertion or deletion.
        let (shorter, longer) = s.count < t.count ? (s, t) : (t, s)
        var i = 0
        var j = 0
        var skippedIndex: Int?
        while i < shorter.count && j < longer.count {
            if shorter[i] == longer[j] {
                i += 1
                j += 1
            } else if skippedIndex == nil {
                skippedIndex = j
                j += 1
            } else {
                return nil
            }
        }
        let extraIdx = skippedIndex ?? (longer.count - 1)
        let extraChar = longer[extraIdx]
        let leftAdj = extraIdx > 0 && areAdjacentKeys(extraChar, longer[extraIdx - 1])
        let rightAdj = extraIdx + 1 < longer.count && areAdjacentKeys(extraChar, longer[extraIdx + 1])
        return (leftAdj || rightAdj) ? 0.70 : 0.90
    }

    /// Weighted Damerau-Levenshtein distance on the keyboard: neighbour keys, missing umlauts,
    /// doubled letters, and transpositions are cheap; `ae`/`oe`/`ue`/`ss` for `ä`/`ö`/`ü`/`ß` cheaper still.
    /// Returns `nil` past `limit`, so long unrelated words are rejected early.
    static func keyboardEditCost(from source: String, to target: String, limit: Double = 4.0) -> Double? {
        if source == target { return 0 }
        let s = Array(source)
        let t = Array(target)
        guard abs(s.count - t.count) <= 3 else { return nil }
        let n = s.count
        let m = t.count
        var d = Array(repeating: Array(repeating: Double.infinity, count: m + 1), count: n + 1)
        d[0][0] = 0
        func indelCost(_ chars: [Character], _ index: Int) -> Double {
            let ch = chars[index]
            if index > 0, chars[index - 1] == ch { return 0.5 }
            if index + 1 < chars.count, chars[index + 1] == ch { return 0.5 }
            let leftAdj = index > 0 && areAdjacentKeys(ch, chars[index - 1])
            let rightAdj = index + 1 < chars.count && areAdjacentKeys(ch, chars[index + 1])
            return (leftAdj || rightAdj) ? 0.7 : 0.9
        }
        for i in 0...n {
            for j in 0...m {
                if i == 0 && j == 0 { continue }
                var best = Double.infinity
                if i > 0 { best = min(best, d[i - 1][j] + indelCost(s, i - 1)) }
                if j > 0 { best = min(best, d[i][j - 1] + indelCost(t, j - 1)) }
                if i > 0 && j > 0 {
                    let a = s[i - 1]
                    let b = t[j - 1]
                    best = min(best, d[i - 1][j - 1] + substitutionCost(a, b))
                    if i > 1 && j > 1 && a == t[j - 2] && s[i - 2] == b && a != b {
                        best = min(best, d[i - 2][j - 2] + 0.6)
                    }
                    // `ae` -> `ä`, `ss` -> `ß` and back.
                    if i > 1, isGermanDigraph(s[i - 2], a, for: b) {
                        best = min(best, d[i - 2][j - 1] + 0.35)
                    }
                    if j > 1, isGermanDigraph(t[j - 2], b, for: a) {
                        best = min(best, d[i - 1][j - 2] + 0.35)
                    }
                }
                d[i][j] = best
            }
            if i > 0, let rowMin = d[i].min(), rowMin > limit { return nil }
        }
        let cost = d[n][m]
        return cost <= limit ? cost : nil
    }

    private static func substitutionCost(_ a: Character, _ b: Character) -> Double {
        if a == b { return 0 }
        if isUmlautPair(a, b) || (a == "s" && b == "ß") || (a == "ß" && b == "s") { return 0.45 }
        // QWERTZ habit: `y` and `z` swap places on German keyboards.
        if (a == "y" && b == "z") || (a == "z" && b == "y") { return 0.6 }
        return areAdjacentKeys(a, b) ? 0.65 : 1.15
    }

    private static func isGermanDigraph(_ first: Character, _ second: Character, for single: Character) -> Bool {
        switch (first, second, single) {
        case ("a", "e", "ä"), ("o", "e", "ö"), ("u", "e", "ü"), ("s", "s", "ß"): true
        default: false
        }
    }

    private static let keyCoordinates: [Character: (Double, Double)] = {
        var map: [Character: (Double, Double)] = [:]
        for (col, ch) in "qwertyuiop".enumerated() { map[ch] = (0, Double(col)) }
        for (col, ch) in "asdfghjkl".enumerated() { map[ch] = (1, Double(col) + 0.5) }
        for (col, ch) in "zxcvbnm".enumerated() { map[ch] = (2, Double(col) + 1.5) }
        return map
    }()

    static func isUmlautPair(_ a: Character, _ b: Character) -> Bool {
        let pairs: Set<String> = ["aä", "oö", "uü"]
        return pairs.contains(String([a, b])) || pairs.contains(String([b, a]))
    }

    static func areAdjacentKeys(_ a: Character, _ b: Character) -> Bool {
        guard let pa = keyCoordinates[a], let pb = keyCoordinates[b] else { return false }
        let dx = pa.1 - pb.1
        let dy = pa.0 - pb.0
        return (dx * dx + dy * dy).squareRoot() <= 1.6
    }

    // MARK: - Built-in dictionaries

    /// Valid words where an apostrophe form exists, offered as a suggestion without clobbering the word.
    static let suggestOnlyContractions: [String: String] = [
        "ill": "I'll",
        "id": "I'd",
        "were": "we're",
        "wed": "we'd",
        "well": "we'll",
        "its": "it's",
        "lets": "let's",
        "hell": "he'll",
        "shell": "she'll",
    ]

    /// Common chat & engineering shorthand that cautious autocorrect never rewrites.
    static let shorthandAllowlist: Set<String> = [
        "ok", "okay", "ty", "thx", "pls", "plz", "tmrw", "tbh", "idk", "imo", "imho",
        "lol", "lmao", "omg", "brb", "btw", "afaik", "fyi", "nvm", "rn", "irl", "jk",
        "np", "yw", "smh", "ikr", "ngl", "fr", "gg", "dm", "pr", "prs", "ci", "ui",
        "ux", "ios", "macos", "api", "apis", "url", "urls", "json", "sql", "ssh", "cli",
        "gpu", "cpu", "ram", "sdk", "hex", "wisp", "seer", "rune", "kit", "gonna",
        "wanna", "gotta", "kinda", "sorta", "yeah", "yep", "nope", "nah", "hey", "yo",
    ]

    /// ~125 unambiguous missing-apostrophe contractions and high-frequency QWERTY transpositions.
    static let unambiguousFixes: [String: String] = [
        // Pronoun & missing-apostrophe contractions
        "i": "I",
        "im": "I'm",
        "ive": "I've",
        "dont": "don't",
        "cant": "can't",
        "wont": "won't",
        "didnt": "didn't",
        "doesnt": "doesn't",
        "isnt": "isn't",
        "arent": "aren't",
        "wasnt": "wasn't",
        "werent": "weren't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hadnt": "hadn't",
        "wouldnt": "wouldn't",
        "couldnt": "couldn't",
        "shouldnt": "shouldn't",
        "mustnt": "mustn't",
        "neednt": "needn't",
        "youre": "you're",
        "youve": "you've",
        "youd": "you'd",
        "youll": "you'll",
        "theyre": "they're",
        "theyve": "they've",
        "theyd": "they'd",
        "theyll": "they'll",
        "weve": "we've",
        "shes": "she's",
        "hes": "he's",
        "itll": "it'll",
        "thats": "that's",
        "theres": "there's",
        "heres": "here's",
        "wheres": "where's",
        "whos": "who's",
        "whats": "what's",
        "hows": "how's",
        "whens": "when's",
        "whys": "why's",
        "aint": "ain't",
        "yall": "y'all",
        "oclock": "o'clock",
        "maam": "ma'am",
        "cmon": "c'mon",
        "wouldve": "would've",
        "couldve": "could've",
        "shouldve": "should've",
        "mightve": "might've",
        "mustve": "must've",
        // High-frequency QWERTY transpositions & fat-finger typos
        "teh": "the",
        "hte": "the",
        "taht": "that",
        "thta": "that",
        "adn": "and",
        "nad": "and",
        "wiht": "with",
        "iwth": "with",
        "waht": "what",
        "hwat": "what",
        "wich": "which",
        "whcih": "which",
        "thier": "their",
        "theri": "their",
        "recieve": "receive",
        "definately": "definitely",
        "seperate": "separate",
        "occured": "occurred",
        "untill": "until",
        "abotu": "about",
        "baout": "about",
        "becuase": "because",
        "beacuse": "because",
        "jsut": "just",
        "jstu": "just",
        "knwo": "know",
        "konw": "know",
        "tiem": "time",
        "tmie": "time",
        "shoudl": "should",
        "hsould": "should",
        "woudl": "would",
        "owuld": "would",
        "coudl": "could",
        "oculd": "could",
        "ahve": "have",
        "hvae": "have",
        "maek": "make",
        "mkae": "make",
        "thign": "thing",
        "hting": "thing",
        "peopel": "people",
        "poeple": "people",
        "workign": "working",
        "goign": "going",
        "doign": "doing",
        "runnign": "running",
        "comign": "coming",
        "thnaks": "thanks",
        "htanks": "thanks",
        "plase": "please",
        "pleaes": "please",
        "yuor": "your",
        "yoru": "your",
        "yuo": "you",
        "oyu": "you",
        "fomr": "from",
        "verry": "very",
        "evrey": "every",
        "realyl": "really",
        "realy": "really",
        "actualyl": "actually",
        "probalby": "probably",
        "tomorow": "tomorrow",
        "tommorow": "tomorrow",
        "tonihgt": "tonight",
        "tongiht": "tonight",
        "mesasge": "message",
        "messgae": "message",
        "keybaord": "keyboard",
        "keboard": "keyboard",
        "iphnoe": "iPhone",
        "ipohne": "iPhone",
    ]

    /// Frequent German slips, applied only when no dictionary the person types knows the word.
    static let germanFixes: [String: String] = [
        "ihc": "ich", "icg": "ich",
        "nciht": "nicht", "nihct": "nicht", "nichz": "nicht", "nicth": "nicht", "ncht": "nicht",
        "udn": "und", "nud": "und", "unf": "und",
        "dsa": "das", "dsas": "dass", "dasss": "dass",
        "dei": "die", "dier": "dir", "isr": "ist",
        "afu": "auf", "auc": "auch", "acuh": "auch", "ahuc": "auch",
        "ncoh": "noch", "nohc": "noch", "shcon": "schon", "scohn": "schon",
        "eien": "eine", "enie": "eine", "eienn": "einen", "eienm": "einem", "eienr": "einer",
        "wiel": "weil", "wnen": "wenn", "abre": "aber", "aebr": "aber",
        "imemr": "immer", "imer": "immer",
        "gehts": "geht's", "gibts": "gibt's", "habs": "hab's",
        "jetzz": "jetzt", "jezt": "jetzt", "jetz": "jetzt",
        "heuet": "heute", "huete": "heute", "morgne": "morgen", "mrogen": "morgen",
        "vielelicht": "vielleicht", "vieleicht": "vielleicht",
        "wirklcih": "wirklich", "wirklihc": "wirklich",
        "eigentlcih": "eigentlich", "eigendlich": "eigentlich",
        "bitet": "bitte", "btite": "bitte", "dnake": "danke", "dakne": "danke",
        "geanu": "genau", "gnau": "genau", "sien": "sein", "wier": "wir", "iwr": "wir",
        "hatet": "hatte", "hattte": "hatte",
        "konnen": "können", "koennen": "können", "mussen": "müssen", "muessen": "müssen",
        "fur": "für", "fuer": "für", "uber": "über", "ueber": "über",
        "zeti": "Zeit", "ziet": "Zeit",
    ]
}
