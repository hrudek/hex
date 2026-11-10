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
        XCTAssertEqual(decoder.decode(evidence("uello", aimedAt: "hello"), languages: [.english])?.confident?.word, "hello")
        XCTAssertEqual(decoder.decode(evidence("uello", aimedAt: "jello"), languages: [.english])?.confident?.word, "jello")
        XCTAssertNil(decoder.decode(evidence("uello", aimedAt: "uello"), languages: [.english])?.confident)
    }

    func testLanguageSelectionAndMissingResourceFallback() {
        let word = evidence("hslko", aimedAt: "hallo")
        XCTAssertEqual(decoder().decode(word, languages: [.german])?.confident?.word, "hallo")
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
        // No drawn ü/ß keys in today's QWERTY layout; these stay with the existing umlaut path.
        XCTAssertFalse(decoder().decode(evidence("strase", aimedAt: "strase"), languages: [.german])?.candidates.contains { $0.word == "straße" } ?? false)
    }

    func testDeterminismBudgetAndLengthBounds() {
        let decoder = self.decoder()
        let word = evidence("gello", aimedAt: "hello")
        let expected = decoder.decode(word, languages: [.german, .english])?.candidates.map(\.word)
        for _ in 0..<10 {
            XCTAssertEqual(decoder.decode(word, languages: [.english, .german])?.candidates.map(\.word), expected)
        }
        XCTAssertNil(decoder.decode(word, languages: [.english], budget: 1))
        XCTAssertNil(decoder.decode(evidence("hi", aimedAt: "hi"), languages: [.english]))
        let long = String(repeating: "a", count: 33)
        XCTAssertNil(decoder.decode(evidence(long, aimedAt: long), languages: [.english]))
    }

    func testGeometryUsesCapturedWidthAndStripOffset() {
        for width in [CGFloat(320), 393, 440] {
            for strip in [false, true] {
                let word = evidence("gello", aimedAt: "hello", layout: layout(width: width, strip: strip))
                XCTAssertEqual(decoder().decode(word, languages: [.english])?.confident?.word, "hello")
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
        if let bad = SpatialWordLexicon(data: bytes) {
            XCTAssertNil(SpatialWordDecoder(lexicons: [.english: bad]).decode(evidence("gello", aimedAt: "hello"), languages: [.english]))
        }
        var word = evidence("gello", aimedAt: "hello")
        let first = word.samples[0]
        word.samples[0] = .init(text: first.text, point: CGPoint(x: CGFloat.nan, y: 0), key: first.key)
        XCTAssertNil(decoder().decode(word, languages: [.english]))
    }

    private func engine(valid: Set<String> = ["hello", "jello"], germanGuesses: [String] = []) -> AutocorrectEngine {
        let checker = SpatialChecker(valid: valid)
        let engine = AutocorrectEngine(checker: checker, learnedWords: LearnedWordsStore(defaults: nil), spatialDecoder: decoder())
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
        XCTAssertNil(result?.confident)
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
        XCTAssertNil(manual.touchInput.evidence(beforeInput: manualTarget.text))
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
            XCTAssertNil(control?.confident, "centered control: \(intended)")
        }
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

@MainActor
private final class SpatialChecker: TextChecking {
    let valid: Set<String>
    let values: [String]
    init(valid: Set<String>, guesses: [String] = []) { self.valid = valid; self.values = guesses }
    func isWordValid(_ word: String) -> Bool { valid.contains(word) }
    func guesses(for word: String) -> [String] { values }
    func completions(for prefix: String) -> [String] { [] }
}
