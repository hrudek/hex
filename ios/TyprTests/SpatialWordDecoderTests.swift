import UIKit
import XCTest
@testable import Typr

@MainActor
final class SpatialWordDecoderTests: XCTestCase {
    private func layout(width: CGFloat = 393, strip: Bool = true) -> KeyboardLayout {
        KeyboardLayout(width: width, orientation: .portrait, layer: .letters, field: .text,
                       showsGlobe: false, showsStrip: strip)
    }

    private func evidence(_ text: String, aimedAt: String, layout: KeyboardLayout? = nil) -> KeyboardTouchWord {
        let grid = layout ?? self.layout()
        let samples = zip(text, aimedAt).map { typed, aimed in
            let key = grid.key(.character(String(typed).lowercased()))!
            let destination = grid.key(.character(String(aimed).lowercased()))!.frame
            return KeyboardTouchWord.Sample(text: String(typed),
                                            point: CGPoint(x: destination.midX, y: destination.midY), key: key)
        }
        return KeyboardTouchWord(layout: grid, samples: samples)
    }

    // Small TSW1 fixture writer, independent of the production Python compiler.
    private func lexicon(_ words: [(String, UInt32)]) -> SpatialWordLexicon {
        final class Node {
            var children: [Int: Node] = [:]
            var count: UInt32 = 0
        }
        let root = Node()
        for (word, count) in words {
            var node = root
            for letter in word {
                let label = SpatialWordLexicon.alphabet.firstIndex(of: letter)!
                if node.children[label] == nil { node.children[label] = Node() }
                node = node.children[label]!
            }
            node.count += count
        }
        var nodes = [(255, root)]
        var records = Data()
        func append(_ value: UInt32, to data: inout Data) {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        var index = 0
        while index < nodes.count {
            let (label, node) = nodes[index]
            let children = node.children.sorted { $0.key < $1.key }
            let first = children.isEmpty ? 0 : nodes.count
            records.append(contentsOf: [UInt8(label), UInt8(children.count), 0, 0])
            append(UInt32(first), to: &records)
            append(node.count, to: &records)
            nodes.append(contentsOf: children.map { ($0.key, $0.value) })
            index += 1
        }
        var bytes = Data("TSW1".utf8)
        append(UInt32(nodes.count), to: &bytes)
        append(UInt32(words.count), to: &bytes)
        append(0, to: &bytes)
        append(words.reduce(0) { $0 + $1.1 }, to: &bytes)
        append(0, to: &bytes)
        bytes.append(records)
        return SpatialWordLexicon(data: bytes)!
    }

    private func decoder() -> SpatialWordDecoder {
        SpatialWordDecoder(lexicons: [
            .english: lexicon([("hello", 100), ("jello", 100), ("world", 100), ("house", 100)]),
            .german: lexicon([("hallo", 100), ("hause", 100), ("straße", 100), ("grüße", 100)])
        ])
    }

    func testSameLiteralDifferentPointsProduceDifferentWords() {
        let decoder = self.decoder()
        XCTAssertEqual(decoder.decode(evidence("uello", aimedAt: "hello"), languages: [.english])?.automaticCandidate?.word, "hello")
        XCTAssertEqual(decoder.decode(evidence("uello", aimedAt: "jello"), languages: [.english])?.automaticCandidate?.word, "jello")
        XCTAssertNil(decoder.decode(evidence("uello", aimedAt: "uello"), languages: [.english])?.automaticCandidate)
    }

    func testLanguageSelectionAndMissingResourceFallback() {
        let word = evidence("hslko", aimedAt: "hallo")
        XCTAssertEqual(decoder().decode(word, languages: [.german])?.automaticCandidate?.word, "hallo")
        XCTAssertFalse(decoder().decode(word, languages: [.english])?.candidates.contains { $0.word == "hallo" } ?? false)
        XCTAssertNil(decoder().decode(word, languages: []))
        let onlyEnglish = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 100)])])
        XCTAssertNil(onlyEnglish.decode(word, languages: [.english, .german]))
    }

    func testUmlautsArePreservedNotASCIIExpanded() {
        let source = lexicon([("straße", 10), ("grüße", 20), ("für", 30)])
        XCTAssertNotNil(source.logPrior(for: "straße"))
        XCTAssertNotNil(source.logPrior(for: "grüße"))
        XCTAssertNil(source.logPrior(for: "strasse"))
        // No drawn ü/ß centres: a positional substitution cannot invent these letters.
        XCTAssertFalse(decoder().decode(evidence("strase", aimedAt: "strase"), languages: [.german])?.candidates.contains { $0.word == "straße" } ?? false)
    }

    func testDeterminismBudgetAndLengthBounds() {
        let decoder = self.decoder()
        let word = evidence("gello", aimedAt: "hello")
        let expected = decoder.decode(word, languages: [.german, .english])?.candidates.map(\.word)
        for _ in 0..<10 {
            XCTAssertEqual(decoder.decode(word, languages: [.english, .german])?.candidates.map(\.word), expected)
        }
        let truncated = decoder.decode(word, languages: [.english], budget: 1)
        XCTAssertEqual(truncated?.complete, false)
        XCTAssertNil(truncated?.automaticCandidate)
        XCTAssertEqual(truncated?.visits, 1)
        XCTAssertNil(decoder.decode(evidence("hi", aimedAt: "hi"), languages: [.english]))
        let long = String(repeating: "a", count: 33)
        XCTAssertNil(decoder.decode(evidence(long, aimedAt: long), languages: [.english]))
    }

    func testGeometryUsesCapturedWidthAndStripOffset() {
        for width in [CGFloat(320), 393, 440] {
            for strip in [false, true] {
                let word = evidence("gello", aimedAt: "hello", layout: layout(width: width, strip: strip))
                XCTAssertEqual(decoder().decode(word, languages: [.english])?.automaticCandidate?.word, "hello")
            }
        }
    }

    func testMalformedResourcesAndNonfiniteEvidenceFallBack() {
        XCTAssertNil(SpatialWordLexicon(data: Data()))
        var bytes = lexicon([("hello", 100)]).data
        bytes.removeLast()
        XCTAssertNil(SpatialWordLexicon(data: bytes))
        bytes = lexicon([("hello", 100)]).data
        bytes[28] = 255 // invalid first-child index in root
        XCTAssertNil(SpatialWordLexicon(data: bytes))
        var word = evidence("gello", aimedAt: "hello")
        let first = word.samples[0]
        word.samples[0] = .init(text: first.text, point: CGPoint(x: CGFloat.nan, y: 0), key: first.key)
        XCTAssertNil(decoder().decode(word, languages: [.english]))
    }

    private func engine(valid: Set<String> = ["hello", "jello"], germanGuesses: [String] = []) -> AutocorrectEngine {
        let checker = SpatialChecker(valid: valid)
        let engine = AutocorrectEngine(checker: checker, learning: KeyboardLearningSession(), spatialDecoder: decoder())
        if !germanGuesses.isEmpty {
            engine.german = GermanAutocorrect(checker: SpatialChecker(valid: Set(germanGuesses), guesses: germanGuesses))
        }
        return engine
    }

    private func track(_ word: KeyboardTouchWord, in engine: AutocorrectEngine) {
        var before = ""
        for sample in word.samples {
            let after = before + sample.text
            engine.touchInput.append(text: sample.text, point: sample.point, key: sample.key,
                                     layout: word.layout, before: before, after: after)
            before = after
        }
    }

    private func replacement(_ engine: AutocorrectEngine, _ token: String = "gello") -> String? {
        engine.replacementOnSpace(beforeInput: token, field: .text, autocorrectionType: .default)?.replacement
    }

    func testIntegrationSlotsSpaceAndNoEvidenceFallback() {
        let engine = self.engine()
        XCTAssertNil(replacement(engine))
        track(evidence("gello", aimedAt: "hello"), in: engine)
        let slots = engine.suggestions(beforeInput: "gello", field: .text, autocorrectionType: .default)
        XCTAssertEqual(slots.first?.replacement, "gello")
        XCTAssertEqual(slots.dropFirst().first?.replacement, "hello")
        XCTAssertTrue(slots.dropFirst().first?.willAutoReplace ?? false)
        XCTAssertEqual(replacement(engine), "hello")
        engine.touchInput.clear()
        XCTAssertNil(replacement(engine))
    }

    func testValidLiteralKeepAndLanguageOffBlockAutomaticReplacement() {
        let valid = engine(valid: ["gello", "hello", "jello"])
        track(evidence("gello", aimedAt: "hello"), in: valid)
        XCTAssertNil(replacement(valid))
        let kept = engine()
        track(evidence("gello", aimedAt: "hello"), in: kept)
        kept.suppressAndKeep("gello")
        XCTAssertNil(replacement(kept))
        let disabled = engine()
        track(evidence("gello", aimedAt: "hello"), in: disabled)
        disabled.englishEnabled = false
        XCTAssertNil(replacement(disabled))
        disabled.englishEnabled = true
        disabled.isEnabled = false
        XCTAssertNil(replacement(disabled))
        disabled.isEnabled = true
        XCTAssertNil(disabled.replacementOnSpace(beforeInput: "gello", field: .email, autocorrectionType: .default))
        XCTAssertNil(disabled.replacementOnSpace(beforeInput: "gello", field: .text, autocorrectionType: .no))
    }

    func testGermanRequiresCanonicalSpellingForAutomaticReplacement() {
        let engine = self.engine(germanGuesses: ["Hallo"])
        engine.englishEnabled = false
        track(evidence("hslko", aimedAt: "hallo"), in: engine)
        XCTAssertEqual(replacement(engine, "hslko"), "Hallo")
        engine.german = GermanAutocorrect(checker: SpatialChecker(valid: ["hallo"]))
        XCTAssertNil(replacement(engine, "hslko"), "lowercase frequency entry alone cannot establish noun casing")
    }

    func testAmbiguityAndAcronymsNeverBecomeNewAutomaticFixes() {
        let decoder = self.decoder()
        var word = evidence("uello", aimedAt: "hello")
        let h = word.layout.key(.character("h"))!.frame
        let j = word.layout.key(.character("j"))!.frame
        let sample = word.samples[0]
        word.samples[0] = .init(text: sample.text, point: CGPoint(x: (h.midX + j.midX) / 2, y: h.midY), key: sample.key)
        let result = decoder.decode(word, languages: [.english])
        XCTAssertEqual(result?.candidates.prefix(2).map(\.word), ["hello", "jello"])
        XCTAssertNil(result?.automaticCandidate)
        let engine = self.engine()
        track(word, in: engine)
        XCTAssertNil(replacement(engine, "uello"))
        engine.touchInput.clear()
        track(evidence("GELLO", aimedAt: "hello"), in: engine)
        XCTAssertNil(replacement(engine, "GELLO"))
    }

    func testSpaceUndoAndManualSuggestionKeepExistingLifecycle() throws {
        let ac = engine()
        let target = FixtureTextTarget(text: "gello")
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let keyboard = FullKeyboardEngine(target: target, autocorrect: ac)
        keyboard.width = 393
        keyboard.configureForField()
        track(evidence("gello", aimedAt: "hello", layout: keyboard.layout), in: ac)
        keyboard.typeSpaceFromTyprKey()
        XCTAssertEqual(target.text, "hello ")
        XCTAssertNil(ac.touchInput.evidence(beforeInput: target.text))
        let delete = try XCTUnwrap(keyboard.layout.key(.delete)).frame
        let point = CGPoint(x: delete.midX, y: delete.midY)
        keyboard.touchBegan(id: 1, at: point)
        keyboard.touchEnded(id: 1, at: point)
        XCTAssertEqual(target.text, "gello")
        XCTAssertEqual(ac.learning.diagnostics[.undoSpatial], 1)
        XCTAssertTrue(ac.learning.model.lexicon.isKept("gello"))
        XCTAssertTrue(ac.learning.model.lexicon.isRejected(typed: "gello", replacement: "hello"))
        // The synthetic `g` tap sits on `h`'s centre: the model drops it as a > 1 pitch outlier.
        XCTAssertEqual(ac.learning.model.summary.acceptedBySource["undo"], 4)
        XCTAssertEqual(ac.learning.model.summary.rejectedByReason["outlier"], 1)
        XCTAssertNil(replacement(ac), "undo suppresses a repeated automatic replacement")

        let manual = engine()
        let manualTarget = FixtureTextTarget(text: "gello")
        let manualKeyboard = FullKeyboardEngine(target: manualTarget, autocorrect: manual)
        manualKeyboard.width = 393
        manualKeyboard.configureForField()
        track(evidence("gello", aimedAt: "hello", layout: manualKeyboard.layout), in: manual)
        manualKeyboard.refreshSuggestions()
        let suggestion = try XCTUnwrap(manualKeyboard.suggestions.first { $0.replacement == "hello" })
        manualKeyboard.acceptSuggestion(suggestion)
        XCTAssertEqual(manualTarget.text, "hello ")
        XCTAssertEqual(manual.learning.diagnostics[.manualAlternativePick], 1)
        XCTAssertEqual(manual.learning.model.lexicon.counts["hello"], 1)
        XCTAssertEqual(manual.learning.model.summary.acceptedBySource["manualPick"], 5)
        XCTAssertNil(manual.touchInput.evidence(beforeInput: manualTarget.text))
    }

    func testPriorPromotedGeometricallyWorseNeighbourDoesNotVetoSpellingFallback() throws {
        let source = SpatialWordDecoder(lexicons: [.english: lexicon([("help", 10_000_000), ("hello", 1)])])
        let word = evidence("helo", aimedAt: "helo")
        let result = try XCTUnwrap(source.decode(word, languages: [.english]))
        XCTAssertEqual(result.candidates.first?.word, "help")
        XCTAssertFalse(result.geometryPrefersAlternative)
        XCTAssertNil(result.automaticCandidate)
        let ac = AutocorrectEngine(checker: SpatialChecker(valid: ["hello", "help"], guesses: ["hello"]),
                                   spatialDecoder: source)
        track(word, in: ac)
        XCTAssertEqual(replacement(ac, "helo"), "hello")
        XCTAssertEqual(ac.learning.diagnostics[.autoSpellingFallback], 1)
    }

    func testEditAutomaticCandidatePrecedesDifferentSpellingGuess() throws {
        let source = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 4_000_000_000), ("world", 1)])])
        for typed in ["helo", "helllo", "hlelo"] {
            var word = evidence(typed, aimedAt: typed)
            if typed == "helllo" {
                // A stray tap away from the key centre; no real/user samples.
                let sample = word.samples[2]
                let frame = sample.key.frame
                let pitchX = frame.width + word.layout.metrics.gap
                let pitchY = frame.height + word.layout.metrics.rowGap
                word.samples[2] = .init(text: sample.text,
                    point: CGPoint(x: frame.midX + pitchX * 0.45, y: frame.midY + pitchY * 0.45), key: sample.key)
            }
            let result = try XCTUnwrap(source.decode(word, languages: [.english]))
            XCTAssertEqual(result.automaticCandidate?.word, "hello", typed)
            let ac = AutocorrectEngine(checker: SpatialChecker(valid: ["hello", "help"], guesses: ["help"]),
                                       spatialDecoder: source)
            track(word, in: ac)
            XCTAssertEqual(replacement(ac, typed), "hello", typed)
            XCTAssertEqual(ac.learning.diagnostics[.autoSpatialEdit], 1, typed)
            ac.settleFeedback(beforeInput: "hello ")
            XCTAssertTrue(ac.learning.model.lexicon.counts.isEmpty)
            XCTAssertEqual(ac.learning.model.summary.acceptedLabels, 0)
        }
    }

    func testSuggestionDecodeCacheAndBoundaryLatencyAreIndependent() {
        let ac = engine()
        track(evidence("gello", aimedAt: "hello"), in: ac)
        for _ in 0..<5 {
            _ = ac.suggestions(beforeInput: "gello", field: .text, autocorrectionType: .default)
        }
        XCTAssertEqual(ac.learning.diagnostics[.suggestionDecodes], 1)
        XCTAssertEqual(ac.learning.diagnostics.suggestionMs.reduce(0, +), 1)
        XCTAssertEqual(ac.learning.diagnostics[.boundaries], 0)
        XCTAssertEqual(replacement(ac), "hello")
        XCTAssertEqual(ac.learning.diagnostics[.suggestionDecodes], 1, "Boundary must reuse the decode")
        XCTAssertEqual(ac.learning.diagnostics.boundaryMs.reduce(0, +), 1)
        ac.touchInput.clear()
        _ = ac.suggestions(beforeInput: "other", field: .text, autocorrectionType: .default)
        track(evidence("gello", aimedAt: "hello"), in: ac)
        _ = ac.suggestions(beforeInput: "gello", field: .text, autocorrectionType: .default)
        XCTAssertEqual(ac.learning.diagnostics[.suggestionDecodes], 2)
    }

    private func editSuggestionEngine(valid: Set<String> = ["hello"]) -> AutocorrectEngine {
        // The large German corpus keeps the English absent-word floor as the literal's prior.
        let source = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 10_000), ("world", 1)]),
                                                   .german: lexicon([("morgen", 1_000_000)])])
        return AutocorrectEngine(checker: SpatialChecker(valid: valid), spatialDecoder: source)
    }

    func testEditSuggestionsFillTheStripButNeverReplaceAutomatically() throws {
        let ac = editSuggestionEngine()
        let word = evidence("helo", aimedAt: "helo")
        let result = try XCTUnwrap(ac.spatialDecoder?.decode(word, languages: [.english]))
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.editSuggestions.map(\.word), ["hello"])
        track(word, in: ac)
        let slots = ac.suggestions(beforeInput: "helo", field: .text, autocorrectionType: .default)
        XCTAssertEqual(slots.map(\.replacement), ["helo", "hello"])
        XCTAssertFalse(slots[1].willAutoReplace)
        XCTAssertFalse(slots[1].isCompletion)
        XCTAssertNil(replacement(ac, "helo"), "edit suggestions are never automatic")
        XCTAssertEqual(ac.learning.diagnostics[.refusedBelowMargin], 1)
    }

    func testEditSuggestionsAreSuppressedForTrustedLiterals() {
        func secondSlot(_ ac: AutocorrectEngine) -> String? {
            track(evidence("helo", aimedAt: "helo"), in: ac)
            return ac.suggestions(beforeInput: "helo", field: .text, autocorrectionType: .default)
                .dropFirst().first?.replacement
        }
        XCTAssertEqual(secondSlot(editSuggestionEngine()), "hello")
        XCTAssertEqual(secondSlot(editSuggestionEngine(valid: ["hello", "helo"])), "helo", "system-valid literal")
        let kept = editSuggestionEngine()
        kept.suppressAndKeep("helo")
        XCTAssertEqual(secondSlot(kept), "helo", "explicitly kept literal")
        let retainedKeep = editSuggestionEngine()
        retainedKeep.learning.keep("helo")
        XCTAssertEqual(secondSlot(retainedKeep), "helo", "personal lexicon protection without session suppression")
        let rejected = editSuggestionEngine()
        rejected.learning.rejectCorrection(typed: "helo", replacement: "hello")
        XCTAssertEqual(secondSlot(rejected), "helo", "rejected edit pair")
        let contact = editSuggestionEngine()
        contact.loadLexiconEntries([("Helo", "Helo")])
        XCTAssertEqual(secondSlot(contact), "helo", "Contacts/lexicon term")
        let bilingual = editSuggestionEngine()
        bilingual.german = GermanAutocorrect(checker: SpatialChecker(valid: []))
        XCTAssertEqual(secondSlot(bilingual), "hello", "both languages selected")
        let noun = editSuggestionEngine()
        noun.german = GermanAutocorrect(checker: SpatialChecker(valid: ["Helo"]))
        XCTAssertEqual(secondSlot(noun), "helo", "lowercase-typed German noun")
    }

    func testProtectedEditSuggestionsLeaveRoomForNormalCompletions() {
        let source = editSuggestionEngine().spatialDecoder
        let checker = SpatialChecker(valid: ["helo", "hello"], completions: ["helos"])
        let ac = AutocorrectEngine(checker: checker, spatialDecoder: source)
        track(evidence("helo", aimedAt: "helo"), in: ac)
        let slots = ac.suggestions(beforeInput: "helo", field: .text, autocorrectionType: .default)
        XCTAssertEqual(slots.map(\.replacement), ["helo", "helos"])
        XCTAssertTrue(slots[1].isCompletion)

        // A disabled dictionary must not protect the literal in the enabled language.
        let englishOff = editSuggestionEngine(valid: ["helo"])
        englishOff.englishEnabled = false
        englishOff.german = GermanAutocorrect(checker: SpatialChecker(valid: []))
        XCTAssertFalse(englishOff.literalIsValid("helo"))
    }

    func testAboveLiteralStructuralCandidatesAlsoRespectProtections() throws {
        let source = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 4_000_000_000), ("world", 1)])])
        let word = evidence("helo", aimedAt: "helo")
        let result = try XCTUnwrap(source.decode(word, languages: [.english]))
        XCTAssertEqual(result.candidates.first?.word, "hello")
        XCTAssertNotEqual(result.candidates.first?.edit, SpatialWordDecoder.Edit.none)
        let ac = AutocorrectEngine(checker: SpatialChecker(valid: ["helo", "hello"], completions: ["helos"]),
                                   spatialDecoder: source)
        track(word, in: ac)
        let slots = ac.suggestions(beforeInput: "helo", field: .text, autocorrectionType: .default)
        XCTAssertEqual(slots.map(\.replacement), ["helo", "helos"])
        XCTAssertTrue(slots[1].isCompletion)
        XCTAssertNil(replacement(ac, "helo"))
    }

    func testLowercaseGermanNounIsProtectedWithoutSpatialResources() {
        let ac = AutocorrectEngine(checker: SpatialChecker(valid: [], guesses: ["hello"]), spatialDecoder: nil)
        ac.german = GermanAutocorrect(checker: SpatialChecker(valid: ["Helo"], guesses: ["Hello"]))
        XCTAssertTrue(ac.literalIsValid("helo"))
        XCTAssertNil(replacement(ac, "helo"))
        XCTAssertEqual(ac.learning.diagnostics[.refusedLiteralValid], 1)
        XCTAssertEqual(ac.learning.diagnostics[.autoSpellingFallback], 0)
    }

    func testManualEditSuggestionPickLearnsOnlyAlignedLabels() throws {
        let ac = editSuggestionEngine()
        let target = FixtureTextTarget(text: "helo")
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let keyboard = FullKeyboardEngine(target: target, autocorrect: ac)
        keyboard.width = 393
        keyboard.configureForField()
        track(evidence("helo", aimedAt: "helo", layout: keyboard.layout), in: ac)
        keyboard.refreshSuggestions()
        let suggestion = try XCTUnwrap(keyboard.suggestions.first { $0.replacement == "hello" })
        keyboard.acceptSuggestion(suggestion)
        XCTAssertEqual(target.text, "hello ")
        XCTAssertEqual(ac.learning.diagnostics[.manualAlternativePick], 1)
        XCTAssertEqual(ac.learning.diagnostics[.manualCompletionPick], 0)
        XCTAssertEqual(ac.learning.model.lexicon.counts["hello"], 1)
        // `align` drops the ambiguous repeated `l`; h, e and o stay uniquely aligned.
        XCTAssertEqual(ac.learning.model.summary.acceptedBySource["manualPick"], 3)
        XCTAssertEqual(ac.learning.model.summary.rejectedByReason["ambiguousAlignment"], 1)
        XCTAssertFalse(ac.learning.model.lexicon.isKept("helo"))
    }

    func testPickingTheRepeatedLiteralIsNotAnAlternativePick() throws {
        let ac = editSuggestionEngine(valid: ["hello", "helo"])
        let target = FixtureTextTarget(text: "helo")
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let keyboard = FullKeyboardEngine(target: target, autocorrect: ac)
        keyboard.width = 393
        keyboard.configureForField()
        track(evidence("helo", aimedAt: "helo", layout: keyboard.layout), in: ac)
        keyboard.refreshSuggestions()
        let primary = try XCTUnwrap(keyboard.suggestions.dropFirst().first)
        XCTAssertEqual(primary.replacement, "helo")
        keyboard.acceptSuggestion(primary)
        XCTAssertEqual(target.text, "helo ")
        XCTAssertEqual(ac.learning.diagnostics[.manualAlternativePick], 0)
        XCTAssertEqual(ac.learning.model.summary.acceptedLabels, 0)
        XCTAssertTrue(ac.learning.model.lexicon.counts.isEmpty)
    }

    func testProtectionAppliesBeforeSpatialAndSpelling() {
        for token in ["gello", "GELLO", "gEllo", "Gello"] {
            let ac = engine()
            ac.loadLexiconEntries([(token, token)]) // Includes unknown proper-name/contact spellings.
            track(evidence(token, aimedAt: "hello"), in: ac)
            XCTAssertNil(replacement(ac, token))
            XCTAssertEqual(ac.learning.diagnostics[.refusedProtected], 1)
        }
        let ac = engine()
        ac.learning.rejectCorrection(typed: "gello", replacement: "hello")
        track(evidence("gello", aimedAt: "hello"), in: ac)
        XCTAssertNil(replacement(ac))
        XCTAssertEqual(ac.learning.diagnostics[.refusedProtected], 1)
        ac.loadLexiconEntries([("gello", "Explicit replacement")])
        XCTAssertEqual(replacement(ac), "Explicit replacement", "Explicit replacement outranks inferred protections")
    }

    func testDeterministicRuleAndCapsGuardsPrecedeSpatialDecoding() {
        let rule = engine(valid: ["the"])
        track(evidence("teh", aimedAt: "teh"), in: rule)
        XCTAssertEqual(replacement(rule, "teh"), "the")
        XCTAssertEqual(rule.learning.diagnostics[.autoRule], 1)
        XCTAssertEqual(rule.learning.diagnostics[.autoSpatialSameLength], 0)
        for token in ["GELLO", "gEllo"] { // Acronym and internal capital, no lexicon entry.
            let ac = engine()
            track(evidence(token, aimedAt: "hello"), in: ac)
            XCTAssertNil(replacement(ac, token), token)
            XCTAssertEqual(ac.learning.diagnostics[.refusedProtected], 1, token)
        }
    }

    func testMissingSelectedLanguageResourceFallsBackWithDiagnostic() {
        let source = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 100)])])
        let ac = AutocorrectEngine(checker: SpatialChecker(valid: ["hello"], guesses: ["hello"]), spatialDecoder: source)
        ac.german = GermanAutocorrect(checker: SpatialChecker(valid: []))
        track(evidence("gello", aimedAt: "hello"), in: ac)
        XCTAssertEqual(replacement(ac), "hello")
        XCTAssertEqual(ac.learning.diagnostics[.refusedMissingResource], 1)
        XCTAssertEqual(ac.learning.diagnostics[.autoSpellingFallback], 1)
    }

    func testIncompleteSearchCannotUseSpellingFallback() throws {
        let entries: [(String, UInt32)] = (0..<4_096).map { value in
            (String((0..<12).map { value & (1 << $0) == 0 ? Character("g") : Character("h") }), 1)
        }
        let source = SpatialWordDecoder(lexicons: [.english: lexicon(entries + [("world", 1_000_000_000)])])
        let token = String(repeating: "g", count: 12)
        var word = evidence(token, aimedAt: token)
        let g = try XCTUnwrap(word.layout.key(.character("g"))).frame
        let h = try XCTUnwrap(word.layout.key(.character("h"))).frame
        word.samples = word.samples.map {
            .init(text: $0.text, point: CGPoint(x: (g.midX + h.midX) / 2, y: g.midY), key: $0.key)
        }
        let guess = String(repeating: "g", count: 11) + "h"
        let ac = AutocorrectEngine(checker: SpatialChecker(valid: [guess], guesses: [guess]), spatialDecoder: source)
        XCTAssertFalse(try XCTUnwrap(source.decode(word, languages: [.english])).complete)
        track(word, in: ac)
        XCTAssertNil(replacement(ac, token))
        XCTAssertEqual(ac.learning.diagnostics[.refusedIncompleteSearch], 1)
        XCTAssertEqual(ac.learning.diagnostics[.autoSpellingFallback], 0)
    }

    func testCanonicalGermanGuessesAreCachedPerTokenForVisibleCandidates() {
        let checker = SpatialChecker(valid: ["Hallo"], guesses: ["Hallo"])
        let ac = engine()
        ac.englishEnabled = false
        ac.german = GermanAutocorrect(checker: checker)
        track(evidence("hslko", aimedAt: "hallo"), in: ac)
        for _ in 0..<5 {
            let slots = ac.suggestions(beforeInput: "hslko", field: .text, autocorrectionType: .default)
            XCTAssertEqual(slots.dropFirst().first?.replacement, "Hallo")
        }
        XCTAssertEqual(replacement(ac, "hslko"), "Hallo")
        XCTAssertEqual(checker.guessCalls, 1)
    }

    func testLearningOffDoesNotSupplyCalibrationOrWordPriors() throws {
        let name = "Spatial-learning-off-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = KeyboardLearningSession(defaults: defaults)
        let grid = layout()
        let frame = try XCTUnwrap(grid.key(.character("h"))).frame
        for _ in 0..<24 {
            session.learn([TouchLabel(point: CGPoint(x: frame.midX + 4, y: frame.midY), letter: "h")],
                          layout: grid, source: .keep)
        }
        session.recordWord("hello")
        XCTAssertNotNil(session.model.calibration(for: grid))
        defaults.set(false, forKey: "keyboard.personalLearning")
        let ac = AutocorrectEngine(checker: SpatialChecker(valid: ["hello"]), learning: session, spatialDecoder: decoder())
        ac.syncLearning()
        XCTAssertNil(session.model.calibration(for: grid))
        XCTAssertTrue(session.model.lexicon.counts.isEmpty)
        let state = session.model.state
        track(evidence("gello", aimedAt: "hello"), in: ac)
        XCTAssertEqual(replacement(ac), "hello")
        XCTAssertEqual(session.model.state, state)
    }

    func testFixedPublicWordFixturesWithBundledData() {
        // Synthetic points are an algorithm regression set, not real-iPhone accuracy measurements.
        let cases: [(String, String, SpatialWordDecoder.Language)] = [
            ("gello", "hello", .english), ("eorld", "world", .english),
            ("jeyboars", "keyboard", .english), ("gouse", "house", .english),
            ("hslko", "hallo", .german), ("dsnkr", "danke", .german),
            ("norgem", "morgen", .german), ("hrutr", "heute", .german),
        ]
        for (typed, intended, language) in cases {
            let result = SpatialWordDecoder.bundled.decode(evidence(typed, aimedAt: intended), languages: [language])
            XCTAssertTrue(result?.candidates.contains { $0.word == intended } ?? false, "candidate recall: \(typed) -> \(intended)")
            let control = SpatialWordDecoder.bundled.decode(evidence(intended, aimedAt: intended), languages: [language])
            XCTAssertNotNil(control, "a control should complete within budget")
            XCTAssertNil(control?.automaticCandidate, "centered control: \(intended)")
        }
    }

    func testStructuralEditAlignmentsAndNoCompletions() throws {
        let decoder = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 1_000_000), ("help", 1)])])
        let missing = try XCTUnwrap(decoder.decode(evidence("helo", aimedAt: "helo"), languages: [.english]))
        let inserted = try XCTUnwrap(missing.candidates.first { $0.word == "hello" })
        if case .missingLetter = inserted.edit {} else { XCTFail("expected one missing letter") }
        XCTAssertEqual(inserted.alignment.count, 5)
        XCTAssertEqual(inserted.alignment.compactMap { $0 }, [0, 1, 2, 3])
        let extra = try XCTUnwrap(decoder.decode(evidence("heallo", aimedAt: "heallo"), languages: [.english]))
        XCTAssertEqual(extra.candidates.first?.edit, .extraTap(at: 2))
        XCTAssertEqual(extra.candidates.first?.alignment, [0, 1, 3, 4, 5])
        let transpose = try XCTUnwrap(decoder.decode(evidence("hlelo", aimedAt: "hlelo"), languages: [.english]))
        XCTAssertEqual(transpose.candidates.first?.edit, .transposition(at: 1))
        XCTAssertEqual(transpose.candidates.first?.alignment, [0, 2, 1, 3, 4])
        for text in ["helo", "heallo", "hlelo"] {
            let staticResult = decoder.decode(evidence(text, aimedAt: text), languages: [.english], allowsEdits: false)
            XCTAssertFalse(staticResult?.candidates.contains { $0.word == "hello" } ?? false)
        }
        let completion = SpatialWordDecoder(lexicons: [.english: lexicon([("helping", 100)])])
        XCTAssertTrue(completion.decode(evidence("help", aimedAt: "help"), languages: [.english])?.candidates.isEmpty ?? false)
    }

    func testStructuralCandidatesStillNeedToBeatTheLiteral() throws {
        // A centred missing-letter typo has no geometric gain over the literal.
        // Realistic prior ratios do not pay for log(.01); this is not search failure.
        let word = evidence("helo", aimedAt: "helo")
        let conservative = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 10_000), ("world", 1)])])
        let result = try XCTUnwrap(conservative.decode(word, languages: [.english]))
        XCTAssertTrue(result.complete)
        XCTAssertTrue(result.candidates.isEmpty)
        // Absent literal: the structural word is still offered, below the literal and
        // only as a suggestion. It never feeds the automatic or geometry decisions.
        XCTAssertEqual(result.editSuggestions.map(\.word), ["hello"])
        XCTAssertEqual(result.suggestions.map(\.word), ["hello"])
        XCTAssertLessThan(try XCTUnwrap(result.editSuggestions.first).score, result.literalScore)
        XCTAssertNil(result.automaticCandidate)
        XCTAssertFalse(result.geometryPrefersAlternative)
        let staticResult = try XCTUnwrap(conservative.decode(word, languages: [.english], allowsEdits: false))
        XCTAssertTrue(staticResult.editSuggestions.isEmpty)
        let valid = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 10_000), ("helo", 1)])])
        XCTAssertTrue(try XCTUnwrap(valid.decode(word, languages: [.english])).editSuggestions.isEmpty,
                      "a corpus-valid literal gets no below-literal edit suggestions")
        let several = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 10_000), ("helio", 5_000),
                                                                       ("helot", 2_000), ("world", 1)])])
        XCTAssertEqual(try XCTUnwrap(several.decode(word, languages: [.english])).editSuggestions.map(\.word),
                       ["hello", "helio"], "at most editSuggestionLimit, best first")
        // Window: more than one edit penalty below the literal (small German corpus sets the floor).
        let distant = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 1), ("world", 1_000_000)]),
                                                    .german: lexicon([("hallo", 10)])])
        XCTAssertTrue(try XCTUnwrap(distant.decode(word, languages: [.english, .german])).editSuggestions.isEmpty)
        let stronger = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 1_000_000), ("world", 1)])])
        let suggested = try XCTUnwrap(stronger.decode(word, languages: [.english]))
        XCTAssertTrue(suggested.complete)
        XCTAssertEqual(suggested.candidates.first?.word, "hello")
        XCTAssertNil(suggested.automaticCandidate, "beating literal is still not the 3-unit auto margin")
    }

    func testSubtreePriorIndexRequiresUniqueSpellingsPerNode() throws {
        let source = lexicon([("cat", 2), ("car", 30), ("dog", 7)])
        XCTAssertEqual(source.bestLogPrior(at: 0), log(30.0 / 39), accuracy: 1e-12)
        let root = try XCTUnwrap(source.node(0))
        let c = root.children.lowerBound, d = c + 1
        let cNode = try XCTUnwrap(source.node(c))
        XCTAssertEqual(source.bestLogPrior(at: c), log(30.0 / 39), accuracy: 1e-12)
        XCTAssertEqual(source.bestLogPrior(at: d), log(7.0 / 39), accuracy: 1e-12)
        // Sharing a child would make a node's spelling ambiguous and invalidate
        // dominance. Such forward-only DAGs must not be accepted as tries.
        var shared = source.data
        let offset = 24 + d * 12 + 4
        for shift in 0..<4 { shared[offset + shift] = UInt8(truncatingIfNeeded: cNode.children.lowerBound >> (shift * 8)) }
        XCTAssertNil(SpatialWordLexicon(data: shared))
        var duplicate = source.data
        duplicate[24 + d * 12] = UInt8(try XCTUnwrap(source.node(c)).label)
        XCTAssertNil(SpatialWordLexicon(data: duplicate))
    }

    func testPolicyRefusalsAndGeometryOnlyVeto() {
        typealias Decoder = SpatialWordDecoder
        func candidate(_ word: String, score: Double, spatial: Double, edit: Decoder.Edit = .none) -> Decoder.Candidate {
            .init(word: word, language: .english, score: score, spatialScore: spatial,
                  edit: edit, alignment: [0, 1, 2, 3])
        }
        func result(_ candidates: [Decoder.Candidate], complete: Bool = true) -> Decoder.Result {
            .init(candidates: candidates, literalScore: 0, literalSpatialScore: 0,
                  literalInLexicon: false, complete: complete, visits: 1, generated: 1)
        }
        func refusal(_ result: Decoder.Result, valid: Bool = false) -> Decoder.Refusal? {
            if case .refuse(let reason) = result.automaticDecision(literalIsValid: valid) { return reason }
            return nil
        }
        let strong = candidate("hello", score: 4, spatial: 3)
        XCTAssertEqual(refusal(result([strong], complete: false)), .incompleteSearch)
        XCTAssertEqual(refusal(result([])), .noCandidate)
        XCTAssertEqual(refusal(result([candidate("hello", score: 2.9, spatial: 3)])), .belowMargin)
        XCTAssertEqual(refusal(result([candidate("hello", score: 4, spatial: 1.9)])), .belowMargin)
        XCTAssertEqual(refusal(result([strong, candidate("jello", score: 2.5, spatial: 3)])), .ambiguous)
        XCTAssertNil(refusal(result([strong, candidate("jello", score: 2.4, spatial: 3)])))
        let suggestionOnly = Decoder.Result(candidates: [], literalScore: 0, literalSpatialScore: 0,
                                            literalInLexicon: false, complete: true, visits: 1, generated: 1,
                                            editSuggestions: [candidate("hello", score: -1, spatial: 0, edit: .missingLetter(at: 1))])
        XCTAssertEqual(refusal(suggestionOnly), .noCandidate)
        XCTAssertFalse(suggestionOnly.geometryPrefersAlternative)
        let edited = candidate("hello", score: 4, spatial: -1, edit: .transposition(at: 1))
        XCTAssertEqual(refusal(result([edited]), valid: true), .editNeedsInvalidLiteral)
        XCTAssertNil(refusal(result([edited])))
        XCTAssertFalse(result([candidate("hello", score: 4, spatial: -0.01)]).geometryPrefersAlternative)
        XCTAssertTrue(result([candidate("hello", score: 4, spatial: 0)]).geometryPrefersAlternative)
    }

    func testPersonalCandidatesPriorAndCalibrationNormalization() throws {
        let decoder = SpatialWordDecoder(lexicons: [.english: lexicon([("hello", 1_000_000), ("world", 1)])])
        let personal = PersonalLexiconSnapshot(kept: ["zello"], counts: ["zello": 4, "xello": 1], rejected: [])
        let word = evidence("xello", aimedAt: "zello")
        let result = try XCTUnwrap(decoder.decode(word, languages: [.english], personal: personal))
        let candidate = try XCTUnwrap(result.candidates.first { $0.word == "zello" })
        XCTAssertNil(candidate.language)
        XCTAssertEqual(candidate.edit, .none)
        XCTAssertEqual(candidate.alignment, [0, 1, 2, 3, 4])
        let without = decoder.decode(word, languages: [.english])
        XCTAssertFalse(without?.candidates.contains { $0.word == "zello" } ?? false)
        let centered = evidence("hello", aimedAt: "hello")
        let baseline = try XCTUnwrap(decoder.decode(centered, languages: [.english]))
        let narrow = SpatialTouchCalibration(keys: ["h": .init(offsetX: 0, offsetY: 0, sigmaX: 0.22, sigmaY: 0.22)])
        let broad = SpatialTouchCalibration(keys: ["h": .init(offsetX: 0, offsetY: 0, sigmaX: 0.5, sigmaY: 0.5)])
        let n = try XCTUnwrap(decoder.decode(centered, languages: [.english], calibration: narrow))
        let b = try XCTUnwrap(decoder.decode(centered, languages: [.english], calibration: broad))
        XCTAssertEqual(n.literalSpatialScore - b.literalSpatialScore, 2 * log(0.5 / 0.22), accuracy: 1e-10)
        let withBonus = try XCTUnwrap(decoder.decode(centered, languages: [.english], personal:
            .init(kept: [], counts: ["hello": 10_000], rejected: [])))
        XCTAssertEqual(withBonus.literalScore - baseline.literalScore, 1, accuracy: 1e-10)
        XCTAssertEqual(withBonus.literalSpatialScore, baseline.literalSpatialScore)
        var shifted = centered
        let first = shifted.samples[0]
        let pitch = first.key.frame.width + shifted.layout.metrics.gap
        shifted.samples[0] = .init(text: first.text, point: CGPoint(x: first.point.x + 0.25 * pitch, y: first.point.y), key: first.key)
        let offset = SpatialTouchCalibration(keys: ["h": .init(offsetX: 0.25, offsetY: 0, sigmaX: 0.35, sigmaY: 0.35)])
        let calibrated = try XCTUnwrap(decoder.decode(shifted, languages: [.english], calibration: offset))
        let staticResult = try XCTUnwrap(decoder.decode(shifted, languages: [.english]))
        XCTAssertEqual(calibrated.literalSpatialScore - staticResult.literalSpatialScore,
                       0.25 * 0.25 / (2 * 0.35 * 0.35), accuracy: 1e-10)
    }

    func testLearningAlignmentDropsAmbiguousAndTransposedLabels() {
        XCTAssertEqual(SpatialWordDecoder.align(word: "hello", taps: Array("hello")), [0, 1, 2, 3, 4])
        XCTAssertEqual(SpatialWordDecoder.align(word: "hello", taps: Array("helo")), [0, 1, nil, nil, 3])
        XCTAssertEqual(SpatialWordDecoder.align(word: "hello", taps: Array("heallo")), [0, 1, 3, 4, 5])
        XCTAssertEqual(SpatialWordDecoder.align(word: "hello", taps: Array("helllo")), [0, 1, nil, nil, 5])
        XCTAssertEqual(SpatialWordDecoder.align(word: "hello", taps: Array("hlelo")), [0, nil, nil, 3, 4])
        XCTAssertEqual(SpatialWordDecoder.align(word: "hello", taps: Array("gello")), [0, 1, 2, 3, 4])
        XCTAssertNil(SpatialWordDecoder.align(word: "hello", taps: Array("xxllo")))
        XCTAssertNil(SpatialWordDecoder.align(word: "hello", taps: Array("heo")))
    }

    func testCompleteSearchMatchesExhaustiveFrozenScoreDP() throws {
        let english: [(String, UInt32)] = [("hello", 500_000), ("jello", 100_000), ("hell", 2_000), ("heallo", 1_000), ("help", 4_000)]
        let german: [(String, UInt32)] = [("hallo", 600_000), ("hello", 700_000), ("helgo", 10_000)]
        let sources = [(SpatialWordDecoder.Language.english, english), (.german, german)]
        let decoder = SpatialWordDecoder(lexicons: [.english: lexicon(english), .german: lexicon(german)])
        for (typed, aimed) in [("gello", "hello"), ("helo", "helo"), ("heallo", "heallo"), ("hlelo", "hlelo")] {
            let word = evidence(typed, aimedAt: aimed)
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            var scores: [[Character: Double]] = []
            for sample in word.samples {
                var row: [Character: Double] = [:]
                for letter in letters {
                    let frame = try XCTUnwrap(word.layout.key(.character(String(letter)))).frame
                    let dx = Double(sample.point.x - frame.midX) / Double(frame.width + word.layout.metrics.gap)
                    let dy = Double(sample.point.y - frame.midY) / Double(frame.height + word.layout.metrics.rowGap)
                    if dx * dx + dy * dy <= 1.6 * 1.6 {
                        row[letter] = -(dx * dx + dy * dy) / (2 * 0.35 * 0.35) - log(2 * Double.pi * 0.35 * 0.35)
                    }
                }
                let best = try XCTUnwrap(row.values.max())
                scores.append(row.filter { $0.value >= best - 6 })
            }
            for edits in [false, true] {
                let result = try XCTUnwrap(decoder.decode(word, languages: [.english, .german], allowsEdits: edits))
                XCTAssertTrue(result.complete)
                var expected: [String: Double] = [:]
                var structural: [String: Double] = [:]
                for (_, entries) in sources {
                    let total = Double(entries.reduce(UInt32(0)) { $0 + $1.1 })
                    for (spelling, count) in entries where spelling != typed {
                        let intended = Array(spelling)
                        let n = intended.count, m = scores.count
                        // Independent full matrix oracle, rather than the production trie/trails.
                        var dp = Array(repeating: Array(repeating: [-Double.infinity, -Double.infinity], count: m + 1), count: n + 1)
                        dp[0][0][0] = 0
                        for i in 0...n {
                            for j in 0...m {
                                for used in 0...1 where dp[i][j][used].isFinite {
                                    let value = dp[i][j][used]
                                    if i < n, j < m, let score = scores[j][intended[i]] {
                                        dp[i + 1][j + 1][used] = max(dp[i + 1][j + 1][used], value + score)
                                    }
                                    if edits && used == 0 {
                                        if i < n { dp[i + 1][j][1] = max(dp[i + 1][j][1], value + log(0.01)) }
                                        if j < m {
                                            let stray = scores[j].values.max() ?? -.infinity
                                            dp[i][j + 1][1] = max(dp[i][j + 1][1], value + stray + log(0.01))
                                        }
                                        if i + 1 < n, j + 1 < m, intended[i] != intended[i + 1],
                                           let a = scores[j + 1][intended[i]], let b = scores[j][intended[i + 1]] {
                                            dp[i + 2][j + 2][1] = max(dp[i + 2][j + 2][1], value + a + b + log(0.01))
                                        }
                                    }
                                }
                            }
                        }
                        let prior = 0.35 * log(Double(count) / total)
                        let score = max(dp[n][m][0], dp[n][m][1]) + prior
                        if score > result.literalScore { expected[spelling] = max(expected[spelling] ?? -.infinity, score) }
                        if dp[n][m][1].isFinite {
                            structural[spelling] = max(structural[spelling] ?? -.infinity, dp[n][m][1] + prior)
                        }
                    }
                }
                let ordered = expected.keys.sorted { expected[$0] == expected[$1] ? $0 < $1 : (expected[$0] ?? 0) > (expected[$1] ?? 0) }
                XCTAssertEqual(result.candidates.map(\.word), Array(ordered.prefix(8)))
                for candidate in result.candidates {
                    XCTAssertEqual(candidate.score, try XCTUnwrap(expected[candidate.word]), accuracy: 1e-10)
                }
                // Below-literal edit suggestions: best structural reading within one edit penalty.
                let window = structural.filter { word, score in
                    expected[word] == nil && score <= result.literalScore && score >= result.literalScore + log(0.01)
                }
                let below = window.keys.sorted { window[$0] == window[$1] ? $0 < $1 : (window[$0] ?? 0) > (window[$1] ?? 0) }
                let suggestsEdits = edits && !result.literalInLexicon
                XCTAssertEqual(result.editSuggestions.map(\.word),
                               suggestsEdits ? Array(below.prefix(SpatialWordDecoder.editSuggestionLimit)) : [])
                for candidate in result.editSuggestions {
                    XCTAssertNotEqual(candidate.edit, SpatialWordDecoder.Edit.none)
                    XCTAssertEqual(candidate.score, try XCTUnwrap(window[candidate.word]), accuracy: 1e-10)
                }
            }
        }
    }

    func testExactTopEightUsesDeterministicSpellingTies() throws {
        let entries: [(String, UInt32)] = (0..<16).map { value in
            (String((0..<4).map { value & (1 << $0) == 0 ? Character("g") : Character("h") }), 1)
        }
        let decoder = SpatialWordDecoder(lexicons: [.english: lexicon(entries)])
        var word = evidence("jjjj", aimedAt: "hhhh")
        let g = try XCTUnwrap(word.layout.key(.character("g"))).frame
        let h = try XCTUnwrap(word.layout.key(.character("h"))).frame
        word.samples = word.samples.map { .init(text: $0.text, point: CGPoint(x: (g.midX + h.midX) / 2, y: g.midY), key: $0.key) }
        let result = try XCTUnwrap(decoder.decode(word, languages: [.english]))
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.candidates.map(\.word), Array(entries.map { $0.0 }.sorted().prefix(8)))
    }

    func testGeneratedArenaCapRefusesAutomaticReplacement() throws {
        // Four equidistant letters on a pitch-coordinate circle. Other keys are
        // closer, so the remaining-tap bound stays loose despite exact subtree priors.
        // Four-way branching exercises the arena independently of the pop budget.
        let letters = Array("ghtu")
        let entries: [(String, UInt32)] = (0..<16_384).map { value in
            var digits = value
            let spelling = (0..<7).map { _ -> Character in
                let letter = letters[digits % 4]
                digits /= 4
                return letter
            }
            return (String(spelling), 1)
        }
        let decoder = SpatialWordDecoder(lexicons: [.english: lexicon(entries + [("world", 1_000_000_000)])])
        var word = evidence(String(repeating: "g", count: 7), aimedAt: String(repeating: "g", count: 7))
        let g = try XCTUnwrap(word.layout.key(.character("g"))).frame
        let h = try XCTUnwrap(word.layout.key(.character("h"))).frame
        let y = try XCTUnwrap(word.layout.key(.character("y"))).frame
        let point = CGPoint(x: (g.midX + h.midX) / 2,
                            y: y.midY + 0.125 * (g.height + word.layout.metrics.rowGap))
        word.samples = word.samples.map { .init(text: $0.text, point: point, key: $0.key) }
        let result = try XCTUnwrap(decoder.decode(word, languages: [.english]))
        XCTAssertFalse(result.complete)
        XCTAssertLessThanOrEqual(result.generated, 12_000)
        XCTAssertLessThan(result.visits, 6_000, "an arena cap, not the pop budget, stops this fixture")
        XCTAssertNil(result.automaticCandidate)
    }

    func testDetailedUnavailableAndHardLimits() throws {
        let missing = SpatialWordDecoder(lexicons: [:])
        if case .unavailable(.resource) = missing.decodeDetailed(evidence("hello", aimedAt: "hello"), languages: [.english]) {} else {
            XCTFail("missing selected resource must be diagnosed")
        }
        if case .unavailable(.evidence) = missing.decodeDetailed(evidence("hi", aimedAt: "hi"), languages: [.english]) {} else {
            XCTFail("short evidence must be diagnosed")
        }
        let word = evidence("gello", aimedAt: "hello")
        let zero = try XCTUnwrap(decoder().decode(word, languages: [.english, .german], budget: 0))
        XCTAssertFalse(zero.complete)
        XCTAssertEqual(zero.visits, 0)
        XCTAssertEqual(zero.generated, 2, "both languages enter the same queue before any pops")
        let result = try XCTUnwrap(decoder().decode(word, languages: [.english, .german]))
        XCTAssertTrue(result.complete)
        XCTAssertLessThanOrEqual(result.visits, SpatialWordDecoder.searchBudget)
        XCTAssertLessThanOrEqual(result.generated, SpatialWordDecoder.maxGenerated)
    }

    func testBundledWordDataLoadsInAppAndHasExpectedUnicodeWords() throws {
        for (language, word) in [("de", "straße"), ("en", "keyboard")] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(language)", withExtension: "words", subdirectory: "WordData"))
            let source = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url)))
            XCTAssertNotNil(source.logPrior(for: word))
        }
        XCTAssertTrue(SpatialWordDecoder.bundled.decode(evidence("gello", aimedAt: "hello"), languages: [.english])?.candidates.contains { $0.word == "hello" } ?? false)
    }
}

private extension SpatialWordDecoder.Result {
    var automaticCandidate: SpatialWordDecoder.Candidate? {
        if case .replace(let candidate) = automaticDecision(literalIsValid: false) { return candidate }
        return nil
    }
}

@MainActor
private final class SpatialChecker: TextChecking {
    let valid: Set<String>
    let values: [String]
    let prefixes: [String]
    private(set) var guessCalls = 0
    init(valid: Set<String>, guesses: [String] = [], completions: [String] = []) {
        self.valid = valid
        values = guesses
        prefixes = completions
    }
    func isWordValid(_ word: String) -> Bool { valid.contains(word) }
    func guesses(for word: String) -> [String] { guessCalls += 1; return values }
    func completions(for prefix: String) -> [String] { prefixes }
}
