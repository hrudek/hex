import UIKit

/// One slot in the 3-column suggestion strip above the keys.
nonisolated struct KeyboardSuggestion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Left slot (`"typed"`): keeps the exact characters and teaches Typr not to rewrite them.
        case keepLiteral
        /// Center slot: best replacement or completion (`autoReplace` highlights when Space will apply it).
        case primary(autoReplace: Bool)
        /// Right slot: runner-up completion or spelling guess.
        case secondary
    }

    let displayText: String
    let replacement: String
    let kind: Kind
    var isCompletion = false

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
}

@MainActor
final class SystemTextChecker: TextChecking {
    private var checker: UITextChecker?
    private let language: String

    init(language: String = "en_US") {
        self.language = language
    }

    /// Warms `UITextChecker` after the keyboard's first frame commits so cold open stays < 12 ms.
    func warmUp() {
        guard checker == nil else { return }
        let instance = UITextChecker()
        _ = instance.rangeOfMisspelledWord(
            in: "hello",
            range: NSRange(location: 0, length: 5),
            startingAt: 0,
            wrap: false,
            language: language
        )
        checker = instance
    }

    private var activeChecker: UITextChecker {
        if let checker { return checker }
        let instance = UITextChecker()
        checker = instance
        return instance
    }

    func isWordValid(_ word: String) -> Bool {
        let ns = word as NSString
        let range = NSRange(location: 0, length: ns.length)
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

    func guesses(for word: String) -> [String] {
        let ns = word as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard range.length > 0 else { return [] }
        return activeChecker.guesses(forWordRange: range, in: word, language: language) ?? []
    }

    func completions(for prefix: String) -> [String] {
        let ns = prefix as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard range.length > 0 else { return [] }
        return activeChecker.completions(forPartialWordRange: range, in: prefix, language: language) ?? []
    }
}

/// Cautious on-device suggestions and replace-on-space engine combining `UILexicon`, deterministic
/// rules, bounded spatial decoding, system spelling and the session's personal protections.
@MainActor
final class AutocorrectEngine {
    /// The path that produced a word boundary's final text.
    enum CorrectionKind: Equatable { case unchanged, autoSpatial, autoSpelling, autoRule }

    struct AppliedCorrection: Equatable {
        let original: String
        let insertedText: String
        var kind: CorrectionKind = .autoRule
        var keptWordWasNew: Bool? = nil
    }

    /// One completed word awaiting trust: RAM only, never persisted, logged or exported.
    // Delayed word feedback adapted from AVGVSTVS96/iikb
    // Packages/KeyboardModules/Sources/KeyboardCore/Typing/TypingEngine+Words.swift (MIT).
    struct PendingFeedback: Equatable {
        let evidence: KeyboardTouchWord?
        let literal: String
        let finalText: String
        let kind: CorrectionKind
        /// Decoder alignment of an automatic spatial replacement (diagnostic context only).
        let alignment: [Int?]?
        /// Unchanged, valid or kept literal with complete evidence while learning was on.
        let learnable: Bool
        let epoch: Int
        var suffix: String { finalText + " " }
    }

    /// One automatic-correction decision; a boundary records it exactly once.
    private struct Decision {
        var text: String?
        var kind = CorrectionKind.unchanged
        var counter = KeyboardDiagnostics.Counter.unchanged
        var refusal: KeyboardDiagnostics.Counter?
        var alignment: [Int?]?
    }

    private struct DecodeCache {
        let evidence: KeyboardTouchWord
        let languages: Set<SpatialWordDecoder.Language>
        let generation: Int
        let outcome: SpatialWordDecoder.Outcome
    }

    /// Per-token system lookups, computed only for candidates actually used (#96 review note 3).
    private struct SpellingCache {
        let token: String
        var germanGuesses: [String]?
        var spatial: [String: (text: String, validated: Bool)] = [:]
    }

    /// Fully aligned, RAM-only evidence for the spatial decoder.
    let touchInput = KeyboardTouchInput()
    let spatialDecoder: SpatialWordDecoder?
    let contextResources: KeyboardContextResources
    let checker: TextChecking
    let learning: KeyboardLearningSession
    var isEnabled = true { didSet { invalidateDecode() } }
    var englishEnabled = true { didSet { invalidateDecode() } }
    /// Typr: German layer; `nil` keeps today's behaviour exactly.
    var german: GermanAutocorrect? { didSet { invalidateDecode() } }
    private(set) var lexiconShortcuts: [String: String] = [:]
    private var lexiconTerms: [String] = []
    private var lexiconTermKeys: Set<String> = []
    private var suppressedInSession: Set<String> = []
    private var reversibleRejection: RejectedCorrection?
    private(set) var lastCorrection: AppliedCorrection?
    private(set) var pendingFeedback: PendingFeedback?
    private var observedResets: Int
    private var observedFeedbackEpoch: Int
    private var decodeCache: DecodeCache?
    private var spellingCache: SpellingCache?

    init(
        checker: TextChecking? = nil,
        learning: KeyboardLearningSession? = nil,
        spatialDecoder: SpatialWordDecoder? = .bundled,
        contextResources: KeyboardContextResources? = nil
    ) {
        self.contextResources = contextResources ?? .bundled
        self.spatialDecoder = spatialDecoder
        self.checker = checker ?? SystemTextChecker()
        let learning = learning ?? KeyboardLearningSession()
        self.learning = learning
        observedResets = learning.resets
        observedFeedbackEpoch = learning.feedbackEpoch
    }

    func loadLexicon(_ lexicon: UILexicon) {
        loadLexiconEntries(lexicon.entries.map { ($0.userInput, $0.documentText) })
    }

    func loadLexiconEntries(_ entries: [LexiconEntry]) {
        loadLexiconEntries(entries.map { ($0.userInput, $0.documentText) })
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
        lexiconTermKeys = Set(terms.map { $0.lowercased() })
    }

    func clearPendingUndo() {
        lastCorrection = nil
    }

    func recordAppliedKeep(_ word: String, wasNew: Bool) {
        lastCorrection = AppliedCorrection(original: word, insertedText: word + " ", keptWordWasNew: wasNew)
    }

    func recordAppliedCorrection(original: String, insertedText: String) {
        lastCorrection = AppliedCorrection(original: original, insertedText: insertedText,
                                           kind: pendingFeedback?.kind ?? .autoRule)
    }

    func consumePendingUndo() -> AppliedCorrection? {
        defer { lastCorrection = nil }
        return lastCorrection
    }

    /// Explicit keep: protects the spelling for this engine and in the personal lexicon.
    func suppressAndKeep(_ word: String) {
        suppressedInSession.insert(word.lowercased())
        learning.keep(word)
    }

    /// Settings poll and keyboard appearance: switch value, app resets and storage access.
    func syncLearning() {
        learning.refresh()
        if observedFeedbackEpoch != learning.feedbackEpoch {
            observedFeedbackEpoch = learning.feedbackEpoch
            pendingFeedback = nil
            lastCorrection = nil
            reversibleRejection = nil
        }
        guard observedResets != learning.resets else { return }
        observedResets = learning.resets
        suppressedInSession = []
        lastCorrection = nil
        pendingFeedback = nil
    }

    /// Cursor, field, layout or host text changed: no tap, decode or pending word survives.
    func discardEvidence() {
        touchInput.clear()
        decodeCache = nil
        pendingFeedback = nil
        reversibleRejection = nil
    }

    func discardFeedback() {
        pendingFeedback = nil
        reversibleRejection = nil
    }

    private func invalidateDecode() {
        decodeCache = nil
        spellingCache = nil
    }

    // MARK: - Feedback transaction

    /// The next word's first letter arrives: trust the previous word only
    /// if it is still intact right before the cursor.
    func settleFeedback(beforeInput: String?, insertedLetter: String, afterInput: String?) {
        reversibleRejection = nil
        guard let pending = pendingFeedback else { return }
        pendingFeedback = nil
        guard pending.learnable, pending.epoch == learning.feedbackEpoch,
              insertedLetter.count == 1, insertedLetter.first?.isLetter == true,
              afterInput?.hasSuffix(pending.suffix + insertedLetter) == true,
              let evidence = pending.evidence, let beforeInput, beforeInput.hasSuffix(pending.suffix),
              beforeInput.dropLast(pending.suffix.count).last?.isLetter != true else { return }
        learnIdentity(evidence, literal: pending.literal, source: .literalValid)
        learning.recordWord(pending.literal)
    }

    /// Backspace restored the typed word right after an automatic replacement.
    func recordUndo(_ undo: AppliedCorrection) {
        if let wasNew = undo.keptWordWasNew {
            pendingFeedback = nil
            if wasNew {
                learning.forgetKeep(undo.original)
                suppressedInSession.remove(undo.original.lowercased())
            }
            return
        }
        let pending = pendingFeedback
        pendingFeedback = nil
        switch undo.kind {
        case .autoSpatial: learning.increment(.undoSpatial)
        case .autoSpelling: learning.increment(.undoSpelling)
        case .autoRule, .unchanged: learning.increment(.undoRule)
        }
        if let pending, pending.literal == undo.original, pending.suffix == undo.insertedText,
           pending.epoch == learning.feedbackEpoch, let evidence = pending.evidence {
            learnIdentity(evidence, literal: undo.original, source: .undo)
        }
        suppressedInSession.insert(undo.original.lowercased())
        // Current boundary corrections append one separator; keep other callers safe.
        let hasSeparator = undo.insertedText.last.map { " .,?!".contains($0) } ?? false
        let replacement = hasSeparator ? String(undo.insertedText.dropLast()) : undo.insertedText
        let pair = RejectedCorrection(typed: undo.original, replacement: replacement)
        let wasRejected = learning.model.state.rejected.contains(pair)
        learning.rejectCorrection(typed: undo.original, replacement: replacement)
        reversibleRejection = wasRejected ? nil : pair
    }

    /// An explicit strip choice. `evidence` must be captured before the word is invalidated.
    func recordSuggestionFeedback(_ suggestion: KeyboardSuggestion, literal: String,
                                  evidence: KeyboardTouchWord?) {
        pendingFeedback = nil
        if let pair = reversibleRejection,
           pair.typed == PersonalLexiconSnapshot.normalize(literal),
           pair.replacement == PersonalLexiconSnapshot.normalize(suggestion.replacement),
           suggestion.kind != .keepLiteral {
            learning.forgetRejection(pair)
            suppressedInSession.remove(literal.lowercased())
        }
        reversibleRejection = nil
        let evidence = evidence?.text == literal ? evidence : nil
        let mayLearn = touchInput.isLearningIntact && evidence?.learningIntact != false
        // The center slot repeats the typed word when nothing else applies: not an alternative.
        guard suggestion.kind == .keepLiteral || suggestion.replacement != literal else { return }
        if suggestion.kind == .keepLiteral {
            learning.increment(.keepChip)
            if let evidence { learnIdentity(evidence, literal: literal, source: .keep) }
            suppressAndKeep(literal)
            if mayLearn { learning.recordWord(literal) }
        } else if suggestion.isCompletion || Self.isPrefixExtension(suggestion.replacement, of: literal) {
            learning.increment(.manualCompletionPick)
            if mayLearn { learning.recordWord(suggestion.replacement) }
        } else {
            learning.increment(.manualAlternativePick)
            if let evidence, evidence.learningIntact { learnAligned(evidence, word: suggestion.replacement) }
            if mayLearn { learning.recordWord(suggestion.replacement) }
        }
    }

    private func learnIdentity(_ evidence: KeyboardTouchWord, literal: String, source: TouchLabelSource) {
        guard evidence.learningIntact, evidence.text == literal, evidence.samples.count == literal.count else { return }
        let labels = evidence.samples.compactMap { sample in
            sample.text.lowercased().first.map { TouchLabel(point: sample.point, letter: $0) }
        }
        learning.learn(labels, layout: evidence.layout, source: source)
    }

    /// Only uniquely aligned tap/letter pairs; the model also rejects taps > 1 pitch from the key.
    private func learnAligned(_ evidence: KeyboardTouchWord, word: String) {
        let taps = evidence.samples.compactMap { $0.text.lowercased().first }
        guard taps.count == evidence.samples.count,
              let alignment = SpatialWordDecoder.align(word: word, taps: taps) else {
            learning.recordRejection(.ambiguousAlignment, count: evidence.samples.count)
            return
        }
        let letters = Array(word.lowercased())
        var labels: [TouchLabel] = []
        for (index, tap) in alignment.enumerated() {
            guard let tap, letters.indices.contains(index), evidence.samples.indices.contains(tap) else { continue }
            labels.append(TouchLabel(point: evidence.samples[tap].point, letter: letters[index]))
        }
        learning.recordRejection(.ambiguousAlignment, count: evidence.samples.count - labels.count)
        learning.learn(labels, layout: evidence.layout, source: .manualPick)
    }

    // MARK: - Token inspection

    /// Extracts the active word right before the caret, returning `nil` inside URLs, handles, paths, or numbers.
    static func currentToken(in beforeInput: String?) -> String? {
        guard let beforeInput, !beforeInput.isEmpty else { return nil }
        let end = beforeInput.endIndex
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

    private static func isPrefixExtension(_ word: String, of literal: String) -> Bool {
        let word = word.lowercased(), literal = literal.lowercased()
        return word.count > literal.count && word.hasPrefix(literal)
    }

    // MARK: - Suggestions & Replace-on-Space

    func suggestions(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?
    ) -> [KeyboardSuggestion] {
        let evidence = touchInput.evidence(beforeInput: beforeInput)
        guard field == .text, autocorrectionType != .no else { return [] }
        let activeToken = Self.currentToken(in: beforeInput)
        let context = contextResources.model?.context(before: beforeInput, currentToken: activeToken)
        guard let token = activeToken else {
            guard isEnabled, let beforeInput, beforeInput.last?.isWhitespace == true,
                  let context, context.canPredict, let model = contextResources.model else { return [] }
            return model.suggestions(after: context.previous, weightDE: context.state.weightDE,
                                     german: german != nil, english: englishEnabled).enumerated().map { index, word in
                KeyboardSuggestion(displayText: word.display, replacement: word.display,
                                   kind: index == 1 ? .primary(autoReplace: false) : .secondary,
                                   isCompletion: true)
            }
        }

        let lower = token.lowercased()
        let autoFix = isEnabled ? decide(token, evidence: evidence, forSuggestions: true).text : nil
        let spatial = spatialResult(for: token, evidence: evidence, forSuggestions: true)
        var pool: [String] = []
        var completions: Set<String> = []
        let poolLimit = isEnabled && contextResources.model != nil ? 8 : 2

        if let pair = reversibleRejection, pair.typed == PersonalLexiconSnapshot.normalize(token) {
            // Rejected protections suppress automatic decisions, not the immediate explicit revert.
            pool.append(Self.matchCase(of: token, onto: pair.replacement))
        }
        if let autoFix {
            if !pool.contains(autoFix) { pool.append(autoFix) }
        } else if englishEnabled, let suggested = Self.suggestOnlyContractions[lower] {
            pool.append(Self.matchCase(of: token, onto: suggested))
        }

        // Spatial words (including above-literal one-edit candidates) use the same slots, never changing
        // typed characters. Display-only, below-literal structural edit suggestions follow, only for a
        // literal nothing else trusts; automatic decisions read `candidates` alone.
        let protectsLiteral = spatial?.suggestions.contains(where: { $0.edit != .none }) == true
            && protectsFromEditSuggestions(token)
        for candidate in spatial?.suggestions ?? [] {
            if pool.count >= poolLimit { break }
            if candidate.edit != .none && protectsLiteral { continue }
            let text = spatialSpelling(candidate, token: token).text
            if candidate.edit != .none && learning.protections.isRejected(typed: token, replacement: text) { continue }
            if !pool.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { pool.append(text) }
        }

        // Prefix matches from Contacts / lexicon terms.
        if lower.count >= 2 && pool.count < poolLimit {
            for term in lexiconTerms where term.lowercased().hasPrefix(lower) && term.lowercased() != lower {
                let candidate = Self.matchCase(of: token, onto: term)
                if !pool.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                    pool.append(candidate)
                    completions.insert(candidate)
                }
                if pool.count >= 3 { break }
            }
        }

        // Spelling guesses or prefix completions from `UITextChecker`.
        if pool.count < poolLimit && token.count >= 2 {
            // Typr: German-valid words count as valid; German guesses come first.
            let valid = Self.shorthandAllowlist.contains(lower) || literalIsValid(token)
            if !valid {
                for guess in germanGuesses(for: token) + (englishEnabled ? rankedGuesses(for: token) : []) {
                    let cased = Self.matchCase(of: token, onto: guess)
                    if cased.caseInsensitiveCompare(token) != .orderedSame,
                       !pool.contains(where: { $0.caseInsensitiveCompare(cased) == .orderedSame }) {
                        pool.append(cased)
                    }
                    if pool.count >= poolLimit { break }
                }
            }
            if englishEnabled && pool.count < poolLimit {
                let checked = checker.completions(for: token)
                    .filter { $0.count > token.count && $0.count <= token.count + 8 }
                    .sorted { a, b in
                        if a.count != b.count { return a.count < b.count }
                        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                    }
                for item in checked {
                    let cased = Self.matchCase(of: token, onto: item)
                    if !pool.contains(where: { $0.caseInsensitiveCompare(cased) == .orderedSame }) {
                        pool.append(cased)
                        completions.insert(cased)
                    }
                    if pool.count >= poolLimit { break }
                }
            }
        }

        // Context only reorders display alternatives. Keep the automatic or explicit revert
        // first (Space and its highlight must still describe the unchanged decision).
        if isEnabled, let context, let model = contextResources.model {
            let pinned = autoFix != nil || reversibleRejection?.typed == PersonalLexiconSnapshot.normalize(token)
            let head = pinned ? Array(pool.prefix(1)) : []
            pool = head + model.rerank(Array(pool.dropFirst(head.count)), context: context,
                                       german: german != nil, english: englishEnabled)
        }

        let literal = KeyboardSuggestion(displayText: "“\(token)”", replacement: token, kind: .keepLiteral)
        let primary: KeyboardSuggestion = if let first = pool.first {
            KeyboardSuggestion(
                displayText: first,
                replacement: first,
                kind: .primary(autoReplace: autoFix != nil),
                isCompletion: completions.contains(first) || Self.isPrefixExtension(first, of: token)
            )
        } else {
            KeyboardSuggestion(displayText: token, replacement: token, kind: .primary(autoReplace: false))
        }
        let secondary: KeyboardSuggestion? = if pool.count >= 2 {
            KeyboardSuggestion(displayText: pool[1], replacement: pool[1], kind: .secondary,
                               isCompletion: completions.contains(pool[1]) || Self.isPrefixExtension(pool[1], of: token))
        } else {
            nil
        }
        return [literal, primary] + (secondary.map { [$0] } ?? [])
    }

    /// One word-boundary transaction (space, Typr key or sentence punctuation): decides once, records diagnostics once and
    /// opens the pending feedback. Returns `(tokenToDelete, replacement)` only for a cautious fix.
    func replacementOnSpace(
        beforeInput: String?,
        field: KeyboardFieldKind,
        autocorrectionType: UITextAutocorrectionType?
    ) -> (original: String, replacement: String)? {
        let evidence = touchInput.evidence(beforeInput: beforeInput)
        pendingFeedback = nil
        guard isEnabled, field == .text, autocorrectionType != .no else { return nil }
        guard let token = Self.currentToken(in: beforeInput) else { return nil }
        let started = DispatchTime.now().uptimeNanoseconds
        let decision = decide(token, evidence: evidence, forSuggestions: false)
        let learnable = decision.text == nil && evidence?.learningIntact == true && learning.isLearningEnabled
            && literalIsValid(token)
        pendingFeedback = PendingFeedback(evidence: evidence, literal: token, finalText: decision.text ?? token,
                                          kind: decision.kind, alignment: decision.alignment,
                                          learnable: learnable, epoch: learning.feedbackEpoch)
        learning.increment(.boundaries)
        // Complete means usable by the decoder, not merely observed by the tracker.
        if !(3...SpatialWordDecoder.maxLetters).contains(token.count) {
            learning.increment(.evidenceLengthOutOfRange)
        } else if !token.lowercased().allSatisfy({ ("a"..."z").contains($0) }) {
            learning.increment(.evidenceUnsupported)
        } else {
            learning.increment(evidence != nil ? .evidenceComplete : .evidenceMissing)
        }
        learning.increment(decision.counter)
        if let refusal = decision.refusal { learning.increment(refusal) }
        learning.recordLatency(Self.seconds(since: started), kind: .boundary)
        return decision.text.map { (token, $0) }
    }

    /// Suggestion-only edit words would displace the normal completions of a spelling Typr trusts:
    /// valid in an enabled language (including a lowercase-typed German noun), kept or a contact.
    private func protectsFromEditSuggestions(_ token: String) -> Bool {
        let lower = token.lowercased()
        return suppressedInSession.contains(lower) || lexiconTermKeys.contains(lower)
            || literalIsValid(token)
    }

    /// Valid in an enabled dictionary or explicitly kept (the only literals trusted by learning).
    func literalIsValid(_ token: String) -> Bool {
        learning.protections.isKept(token) || dictionaryAcceptsLiteral(token)
    }

    private func dictionaryAcceptsLiteral(_ token: String) -> Bool {
        let lower = token.lowercased()
        let title = lower.prefix(1).uppercased() + lower.dropFirst()
        return (englishEnabled && (checker.isWordValid(token) || checker.isWordValid(lower)))
            || (german.map { $0.isValid(token) || $0.isValid(lower) || $0.isValid(title) } ?? false)
    }

    private static func seconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000_000
    }

    // MARK: - Spatial decoding

    private func spatialResult(for token: String, evidence: KeyboardTouchWord?,
                               forSuggestions: Bool) -> SpatialWordDecoder.Result? {
        if case .result(let result)? = spatialOutcome(for: token, evidence: evidence, forSuggestions: forSuggestions) {
            return result
        }
        return nil
    }

    /// One decode per (evidence, languages, learning generation), shared by the strip and the boundary.
    private func spatialOutcome(for token: String, evidence: KeyboardTouchWord?,
                                forSuggestions: Bool) -> SpatialWordDecoder.Outcome? {
        guard isEnabled, let evidence, evidence.text == token,
              token == token.lowercased() || (token.first?.isUppercase == true && String(token.dropFirst()) == token.dropFirst().lowercased()),
              !Self.shorthandAllowlist.contains(token.lowercased()) else {
            decodeCache = nil
            return nil
        }
        var languages: Set<SpatialWordDecoder.Language> = []
        if englishEnabled { languages.insert(.english) }
        if german != nil { languages.insert(.german) }
        guard !languages.isEmpty else { return nil }
        let generation = learning.generation
        if let cache = decodeCache, cache.generation == generation, cache.languages == languages,
           cache.evidence == evidence {
            return cache.outcome
        }
        let outcome: SpatialWordDecoder.Outcome
        if let spatialDecoder {
            let started = DispatchTime.now().uptimeNanoseconds
            // Calibration and personal words are supplied only while learning is on.
            outcome = spatialDecoder.decodeDetailed(evidence, languages: languages,
                                                    calibration: learning.calibration(for: evidence.layout),
                                                    personal: learning.personalPriors)
            if forSuggestions, case .result = outcome, !spatialDecoder.isResourceLoading {
                learning.increment(.suggestionDecodes)
                learning.recordLatency(Self.seconds(since: started), kind: .suggestion)
            }
        } else {
            outcome = .unavailable(.resource)
        }
        decodeCache = spatialDecoder?.isResourceLoading == true ? nil
            : DecodeCache(evidence: evidence, languages: languages, generation: generation, outcome: outcome)
        return outcome
    }

    private func spatialSpelling(_ candidate: SpatialWordDecoder.Candidate, token: String) -> (text: String, validated: Bool) {
        let plain = Self.matchCase(of: token, onto: candidate.word)
        if candidate.language == .english { return (plain, checker.isWordValid(plain)) }
        let guesses = germanGuesses(for: token)
        if let cached = spellingCache?.spatial[candidate.word] { return cached }
        // FrequencyWords is lowercase: German casing comes only from an exact system guess.
        let spelling: (text: String, validated: Bool)
        if let guess = guesses.first(where: { $0.lowercased() == candidate.word }), german?.isValid(guess) == true {
            spelling = (Self.matchCase(of: token, onto: guess), true)
        } else if candidate.language == nil, englishEnabled, checker.isWordValid(plain) {
            spelling = (plain, true)
        } else {
            spelling = (plain, false)
        }
        spellingCache?.spatial[candidate.word] = spelling
        return spelling
    }

    private func germanGuesses(for token: String) -> [String] {
        if spellingCache?.token != token { spellingCache = SpellingCache(token: token) }
        if let guesses = spellingCache?.germanGuesses { return guesses }
        let guesses = german?.guesses(for: token) ?? []
        spellingCache?.germanGuesses = guesses
        return guesses
    }

    // MARK: - Correction policy

    private func automatic(_ text: String, token: String, kind: CorrectionKind,
                           counter: KeyboardDiagnostics.Counter, alignment: [Int?]? = nil) -> Decision {
        guard text != token else { return Decision() }
        guard !learning.protections.isRejected(typed: token, replacement: text) else {
            return Decision(refusal: .refusedProtected)
        }
        return Decision(text: text, kind: kind, counter: counter, alignment: alignment)
    }

    /// One correction path, in order: explicit text replacement, deterministic DE/EN rules,
    /// context guards, protections, spatial decoder on complete evidence, spelling-only fallback.
    /// Explicit keeps and shorthand veto everything, as the learned-word protection did.
    private func decide(_ token: String, evidence: KeyboardTouchWord?, forSuggestions: Bool) -> Decision {
        let lower = token.lowercased()
        guard !suppressedInSession.contains(lower), !learning.protections.isKept(token),
              !Self.shorthandAllowlist.contains(lower) else { return Decision(refusal: .refusedProtected) }
        // 1. Explicit iOS Text Replacement (`omw` -> `On my way!`).
        if let shortcut = lexiconShortcuts[lower] {
            return automatic(shortcut, token: token, kind: .autoRule, counter: .autoRule)
        }
        // Leave ALL-CAPS acronyms (`API`, `PR`, `NYC`) alone unless matched in `UILexicon` above,
        // except unambiguous all-caps contractions/typos of 3+ letters (`DONT` -> `DON'T`, `TEH` -> `THE`).
        let isAllCaps = token.count >= 2 && token == token.uppercased() && token != lower
        // Leave camelCase / PascalCase identifiers (`TyprKey`, `iOS`) alone.
        let hasInternalCaps = token.dropFirst().contains(where: \.isUppercase) && !isAllCaps
        guard !hasInternalCaps else { return Decision(refusal: .refusedProtected) }

        // 2. Deterministic rules. Typr: German umlaut digraphs first, so `FUER` -> `FÜR`.
        if let german,
           let umlaut = german.umlautReplacement(
               for: token,
               englishValid: englishEnabled && (checker.isWordValid(token) || checker.isWordValid(lower))
           ) {
            return automatic(umlaut, token: token, kind: .autoRule, counter: .autoRule)
        }
        if englishEnabled, let fixed = Self.unambiguousFixes[lower], german?.blocksEnglishFix(lower) != true {
            if isAllCaps && token.count < 3 { return Decision(refusal: .refusedProtected) }
            return automatic(Self.matchCase(of: token, onto: fixed), token: token, kind: .autoRule, counter: .autoRule)
        }

        // 3. Context guards: inferred corrections only for plain words of 3+ letters.
        guard !isAllCaps else { return Decision(refusal: .refusedProtected) }
        guard token.count >= 3, !token.contains("'") else { return Decision() }

        // 4. Protections: Contacts/lexicon terms and words valid in an enabled dictionary.
        guard !lexiconTermKeys.contains(lower) else { return Decision(refusal: .refusedProtected) }
        guard !dictionaryAcceptsLiteral(token) else { return Decision(refusal: .refusedLiteralValid) }

        // 5. Spatial decoder. Only a complete search may replace; a lowercase-typed German noun
        //    (`haus`, valid as `Haus`) is protected from becoming a different word.
        var refusal: KeyboardDiagnostics.Counter?
        switch spatialOutcome(for: token, evidence: evidence, forSuggestions: forSuggestions) {
        case nil, .unavailable(.evidence)?:
            break
        case .unavailable(.resource)?:
            refusal = spatialDecoder?.isResourceLoading == true ? .resourceLoading : .refusedMissingResource
        case .result(let result)?:
            switch result.automaticDecision(literalIsValid: false) {
            case .replace(let best):
                let spelling = spatialSpelling(best, token: token)
                if spelling.validated {
                    let decision = automatic(spelling.text, token: token, kind: .autoSpatial,
                                             counter: best.edit == .none ? .autoSpatialSameLength : .autoSpatialEdit,
                                             alignment: best.alignment)
                    if decision.text != nil { return decision }
                    refusal = decision.refusal
                } else {
                    refusal = .refusedValidation
                }
            case .refuse(let reason):
                refusal = switch reason {
                case .incompleteSearch: .refusedIncompleteSearch
                case .ambiguous: .refusedAmbiguous
                case .editNeedsInvalidLiteral: .refusedLiteralValid // Defensive: valid literals are guarded above.
                case .noCandidate, .belowMargin: .refusedBelowMargin
                }
            }
            // #96: only geometry that genuinely points elsewhere vetoes the spelling fallback;
            // prior-promoted, geometrically worse neighbours do not. An incomplete search never
            // authorizes any inferred replacement.
            if !result.complete || result.geometryPrefersAlternative { return Decision(refusal: refusal) }
        }

        // 6. Spelling-only fallback. Typr: German guesses win over English ones.
        if let german {
            var germanBest: String?
            var germanScore = Double.greatestFiniteMagnitude
            for (rank, rawGuess) in germanGuesses(for: token).enumerated() {
                guard !rawGuess.contains(" ") else { continue }
                let normalized = rawGuess.replacingOccurrences(of: "'", with: "").lowercased()
                guard let cost = german.costAdjustedForUmlauts(from: lower, to: normalized) else { continue }
                let total = cost + Double(rank) * 0.08
                if total < germanScore {
                    germanScore = total
                    germanBest = rawGuess
                }
            }
            if let germanBest, germanScore <= 1.6 {
                var decision = automatic(Self.matchCase(of: token, onto: germanBest), token: token,
                                         kind: .autoSpelling, counter: .autoSpellingFallback)
                decision.refusal = decision.refusal ?? refusal
                return decision
            }
        }

        guard englishEnabled else { return Decision(refusal: refusal) }
        var bestGuess: String?
        var bestScore = Double.greatestFiniteMagnitude
        for (rank, rawGuess) in checker.guesses(for: token).prefix(8).enumerated() {
            // Skip multi-word splits (`alot` -> `a lot` is fine only if single space, keep v1 single-token + apostrophe).
            guard !rawGuess.contains(" ") else { continue }
            let normalizedGuess = rawGuess.replacingOccurrences(of: "'", with: "").lowercased()
            guard let editCost = Self.singleEditKeyboardCost(from: lower, to: normalizedGuess) else { continue }
            let totalScore = editCost + Double(rank) * 0.08
            if totalScore < bestScore {
                bestScore = totalScore
                bestGuess = rawGuess
            }
        }
        guard let bestGuess, bestScore <= 1.35 else { return Decision(refusal: refusal) }
        var decision = automatic(Self.matchCase(of: token, onto: bestGuess), token: token,
                                 kind: .autoSpelling, counter: .autoSpellingFallback)
        decision.refusal = decision.refusal ?? refusal
        return decision
    }

    private func rankedGuesses(for token: String) -> [String] {
        let lower = token.lowercased()
        return checker.guesses(for: token)
            .prefix(8)
            .enumerated()
            .sorted { a, b in
                let costA = Self.singleEditKeyboardCost(
                    from: lower,
                    to: a.element.replacingOccurrences(of: "'", with: "").lowercased()
                ) ?? (2.0 + Double(abs(a.element.count - token.count)) * 0.3)
                let costB = Self.singleEditKeyboardCost(
                    from: lower,
                    to: b.element.replacingOccurrences(of: "'", with: "").lowercased()
                ) ?? (2.0 + Double(abs(b.element.count - token.count)) * 0.3)
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

    private static let keyCoordinates: [Character: (Double, Double)] = {
        var map: [Character: (Double, Double)] = [:]
        for (col, ch) in "qwertyuiop".enumerated() { map[ch] = (0, Double(col)) }
        for (col, ch) in "asdfghjkl".enumerated() { map[ch] = (1, Double(col) + 0.5) }
        for (col, ch) in "zxcvbnm".enumerated() { map[ch] = (2, Double(col) + 1.5) }
        return map
    }()

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
        "gpu", "cpu", "ram", "sdk", "typr", "hex", "wisp", "seer", "rune", "kit", "gonna",
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
}
