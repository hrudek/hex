import Foundation
import XCTest
@testable import Typr

@MainActor
final class PersonalTypingBigramTests: XCTestCase {
    private final class Checker: TextChecking {
        var valid: Set<String> = ["hello", "world", "the", "next", "ich", "code", "swift", "morgen", "coffee", "please",
                                   "meine", "tastatur", "heute", "mittag", "guten", "daily", "review", "project", "update", "morning"]
        func isWordValid(_ word: String) -> Bool { valid.contains(word) }
        func guesses(for word: String) -> [String] { [] }
        func completions(for prefix: String) -> [String] { [] }
    }
    private func keyboard(_ session: KeyboardLearningSession? = nil, text: String = "") -> (FullKeyboardEngine, FixtureTextTarget) {
        let target = FixtureTextTarget(text: text)
        target.autocapitalizationType = .some(.none)
        let ac = AutocorrectEngine(checker: Checker(), learning: session, spatialDecoder: nil,
                                   contextResources: .init(model: nil))
        let engine = FullKeyboardEngine(target: target, autocorrect: ac)
        engine.width = 393
        engine.clock = { 100 }
        engine.configureForField()
        return (engine, target)
    }
    private func tap(_ kind: KeyKind, _ engine: FullKeyboardEngine) {
        guard let key = engine.layout.key(kind) else { XCTFail("Missing fixture key"); return }
        let p = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: 1, at: p); engine.touchEnded(id: 1, at: p)
    }
    private func type(_ text: String, _ engine: FullKeyboardEngine) {
        for ch in text { tap(ch == " " ? .space : .character(String(ch)), engine) }
    }
    private func word(_ n: Int) -> String {
        var value = n, s = "w"
        repeat { s.append(Character(UnicodeScalar(97 + value % 26)!)); value /= 26 } while value > 0
        return s
    }

    func testOnlyAdjacentIndependentlySettledWordsTeachPairs() {
        let (engine, _) = keyboard()
        type("hello world ", engine)
        XCTAssertEqual(engine.autocorrect.learning.personalBigrams.pairCount, 0)
        type("n", engine)
        XCTAssertEqual(engine.autocorrect.learning.personalBigrams.followers(after: "hello"), ["world": 1])
        // No pair is inferred from pre-existing field text, even if the words are valid.
        let (other, _) = keyboard(text: "hello ")
        type("world n", other)
        XCTAssertEqual(other.autocorrect.learning.personalBigrams.pairCount, 0)
    }

    func testAutomaticUndoneRetypedAndDiscontinuousWordsNeverTeachPairs() {
        for mode in ["auto", "undo", "retype", "field", "selection", "language", "doubleSpace", "return"] {
            let (engine, target) = keyboard()
            type("hello ", engine)
            if mode == "auto" || mode == "undo" {
                type("teh ", engine)
                if mode == "undo" { tap(.delete, engine); type(" ", engine) }
                type("world n", engine)
            } else if mode == "retype" {
                type("worla", engine); tap(.delete, engine); type("d next n", engine)
            } else {
                type("world", engine)
                switch mode {
                case "field": engine.configureForField()
                case "selection": engine.textDidChange()
                case "language": engine.autocorrect.englishEnabled = false; engine.autocorrect.englishEnabled = true
                case "doubleSpace": type("  ", engine)
                case "return": tap(.returnKey, engine)
                default: break
                }
                type(" next n", engine)
            }
            XCTAssertNil(engine.autocorrect.learning.personalBigrams.followers(after: "hello")["world"], mode)
            XCTAssertNil(engine.autocorrect.learning.personalBigrams.followers(after: "hello")["the"], mode)
            XCTAssertNil(engine.autocorrect.learning.personalBigrams.followers(after: "the")["world"], mode)
            if mode == "retype" {
                XCTAssertNil(engine.autocorrect.learning.personalBigrams.followers(after: "world")["next"])
            }
            XCTAssertFalse(target.text.isEmpty)
        }
    }

    func testManualChoiceWaitsForSettlementAndUndoBreaksSequence() async throws {
        for undo in [false, true] {
            let (engine, _) = keyboard()
            type("hello world", engine)
            await engine.waitForSuggestions()
            var chip = KeyboardSuggestion(displayText: "world", replacement: "world", kind: .keepLiteral)
            chip.ownership = engine.suggestions.first?.ownership
            engine.acceptSuggestion(chip)
            XCTAssertEqual(engine.autocorrect.learning.personalBigrams.pairCount, 0)
            if undo { tap(.delete, engine) }
            type(undo ? " n" : "n", engine)
            XCTAssertEqual(engine.autocorrect.learning.personalBigrams.followers(after: "hello")["world"], undo ? nil : 1)
        }
    }

    func testDeterministicCapsAgeingBytesAndNormalization() throws {
        var a = PersonalBigramModel(), b = PersonalBigramModel()
        for i in 0..<255 { a.record("WORLD", after: "Hello"); b.record("world", after: "hello"); XCTAssertEqual(a, b, "event \(i)") }
        XCTAssertEqual(a.followers(after: "hello")["world"], 255)
        a.record("world", after: "hello")
        XCTAssertEqual(a.updates, 0)
        XCTAssertEqual(a.followers(after: "hello")["world"], 128)
        a.record("Straße", after: "FU\u{308}R")
        XCTAssertEqual(a.followers(after: "für")["straße"], 1)
        XCTAssertTrue(a.followers(after: "fur").isEmpty)
        a.record("coffee", after: "morgen")
        XCTAssertEqual(a.followers(after: "morgen")["coffee"], 1)
        // Compare opposite insertion order under equal counts, below the ageing epoch.
        var x = PersonalBigramModel(), y = PersonalBigramModel()
        for i in 0..<20 { x.record(word(i), after: "context") }
        for i in (0..<20).reversed() { y.record(word(i), after: "context") }
        XCTAssertEqual(x, y)
        XCTAssertEqual(x.followers(after: "context").count, 8)
        // Seed a full, valid encoded fixture directly: no need to defeat intentional ageing.
        let rows = Dictionary(uniqueKeysWithValues: (0..<64).map { h in
            (word(h), Dictionary(uniqueKeysWithValues: (0..<8).map { (word(100 + $0), 10) }))
        })
        let fullData = try JSONSerialization.data(withJSONObject: ["following": rows, "updates": 0])
        var full = try JSONDecoder().decode(PersonalBigramModel.self, from: fullData)
        XCTAssertTrue(full.isValid)
        XCTAssertEqual(full.pairCount, 512)
        for i in 0..<40 { full.record(word(500 + i), after: word(1000 + i)); XCTAssertTrue(full.isValid) }
        XCTAssertLessThanOrEqual(full.pairCount, 512)
        let bytes = try JSONEncoder().encode(full).count
        XCTAssertLessThanOrEqual(bytes, full.encodedByteBound)
        XCTAssertLessThanOrEqual(full.encodedByteBound, PersonalBigramModel.maximumBytes)
        // Long Unicode words exercise the independent byte ceiling, not just edge capacity.
        var unicode = PersonalBigramModel()
        for i in 0..<200 { unicode.record(String(repeating: "界", count: 27) + word(i), after: String(repeating: "語", count: 27) + word(i)) }
        XCTAssertTrue(unicode.isValid)
        XCTAssertLessThan(unicode.pairCount, 200)
        print("EVAL P4_bounds pairs=\(full.pairCount) followersMax=8 encodedBytes=\(bytes) encodedBound=\(full.encodedByteBound) byteCap=65536 unicodePairs=\(unicode.pairCount) countCap=255 ageingInterval=256")
    }

    func testDiscountedBackoffAndPersonalTopThreeAgainstExhaustiveUnion() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        var personal = PersonalBigramModel()
        for _ in 0..<12 { personal.record("swift", after: "ich") }
        for _ in 0..<3 { personal.record("coffee", after: "ich") }
        let corpus = 0.2
        XCTAssertEqual(personal.probability("swift", after: "ich", corpus: corpus), (11.5 + 3 * corpus) / 17, accuracy: 1e-12)
        XCTAssertEqual(personal.probability("other", after: "unknown", corpus: corpus), corpus)
        let context = model.context(before: "ich ", currentToken: nil)
        let actual = model.suggestions(after: "ich", weightDE: context.state.weightDE, personal: personal)
        var keys = Set<String>()
        for pack in [model.de, model.en].compactMap({ $0 }) { for id in 1..<pack.wordCount { keys.insert(pack.word(id)) } }
        keys.formUnion(personal.followers(after: "ich").keys)
        let expected = keys.filter { !KeyboardContextModel.suppressed.contains($0) }.map { key in
            (key, personal.probability(key, after: "ich", corpus: model.probability(key, after: "ich", weightDE: context.state.weightDE, german: true, english: true)))
        }.sorted { $0.1 == $1.1 ? $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) : $0.1 > $1.1 }.prefix(3).map(\.0)
        XCTAssertEqual(actual.map(\.key), expected)
        XCTAssertEqual(actual.first?.key, "swift")
        let ranked = model.rerank(["unknown", "swift"], context: context, german: true, english: true, personal: personal)
        XCTAssertEqual(ranked.first, "swift")
        XCTAssertEqual(model.suggestions(after: "ich", weightDE: 0.5), model.suggestions(after: "ich", weightDE: 0.5, personal: .init()))
    }

    func testMigrationDeletionResetRaceAndLearningOffIsolation() throws {
        let defaults = UserDefaults(suiteName: "p4.\(UUID().uuidString)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardLearningStore(directory: directory, defaults: defaults)
        let session = KeyboardLearningSession(store: store, defaults: defaults)
        for (a, b) in [("hello", "world"), ("world", "next"), ("next", "hello"), ("ich", "code")] {
            session.model.recordPair(b, after: a)
        }
        session.recordWord("world"); session.flush()
        XCTAssertTrue(store.deleteLearnedEntry(.count("world")))
        session.flush() // Dirty/old writer must reload authoritative edited epoch.
        XCTAssertFalse(session.personalBigrams.words.contains("world"))
        XCTAssertEqual(session.personalBigrams.pairCount, 2)
        XCTAssertTrue(store.deleteLearnedEntry(.pairWord("hello")))
        session.refresh()
        XCTAssertFalse(session.personalBigrams.words.contains("hello"))
        defaults.set(false, forKey: "keyboard.personalLearning"); session.refresh()
        let retained = session.model.state.bigrams
        session.model.recordPair("world", after: "hello")
        session.settleTrustedWord("hello", beforeInput: "hello ")
        XCTAssertEqual(session.model.state.bigrams, retained)
        XCTAssertEqual(session.personalBigrams, .init())
        XCTAssertNil(session.previousTrustedWord)
        defaults.set(true, forKey: "keyboard.personalLearning"); session.refresh()
        XCTAssertEqual(session.personalBigrams.pairCount, 1)
        XCTAssertTrue(store.requestLearningReset()); session.flush()
        XCTAssertEqual(session.personalBigrams.pairCount, 0)
        XCTAssertEqual(store.load().0?.bigrams?.pairCount ?? 0, 0)
        var state = PersonalTypingModel.State()
        state.kept["hello"] = Date(timeIntervalSinceReferenceDate: 0)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        for version in [1, 2] {
            object["schemaVersion"] = version; object.removeValue(forKey: "bigrams")
            let decoded = try JSONDecoder().decode(PersonalTypingModel.State.self, from: JSONSerialization.data(withJSONObject: object))
            let migrated = try XCTUnwrap(decoded.validated())
            XCTAssertEqual(migrated.schemaVersion, 3)
            XCTAssertEqual(migrated.bigrams, .init())
            XCTAssertEqual(migrated.kept, state.kept)
        }
        state.schemaVersion = 4
        XCTAssertNil(state.validated())
        state.schemaVersion = 3; state.bigrams = nil
        XCTAssertNil(state.validated())
    }

    func testPermissionRevocationBreaksPendingSequenceAndUsesRAMOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var allowed = true
        let session = KeyboardLearningSession(store: .init(directory: directory, defaults: nil), allowsPersistence: { allowed })
        session.settleTrustedWord("hello", beforeInput: "hello ")
        allowed = false; session.refresh()
        XCTAssertFalse(session.isPersistent)
        XCTAssertNil(session.previousTrustedWord)
        session.settleTrustedWord("world", beforeInput: "hello world ")
        XCTAssertEqual(session.personalBigrams.pairCount, 0)
    }

    func testRepeatedSyntheticSessionsPredictionRecallAndTimings() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        let groups = [("de", [("meine", "tastatur"), ("heute", "mittag"), ("guten", "morgen")]),
                      ("en", [("daily", "review"), ("project", "update"), ("morning", "coffee")]),
                      ("mixed", [("meine", "coffee"), ("daily", "tastatur"), ("morgen", "review")])]
        var times: [Double] = []
        for (name, pairs) in groups {
            let session = KeyboardLearningSession()
            var before = 0, after1 = 0, after3 = 0
            for (h, w) in pairs {
                let context = model.context(before: h + " ", currentToken: nil)
                if model.suggestions(after: h, weightDE: context.state.weightDE, german: name != "en", english: name != "de").contains(where: { $0.key == w }) { before += 1 }
            }
            for _ in 0..<6 {
                for (h, w) in pairs {
                    let (engine, _) = keyboard(session)
                    type(h + " " + w + " n", engine)
                }
            }
            for (h, w) in pairs {
                XCTAssertEqual(session.personalBigrams.followers(after: h)[w], 6)
                let context = model.context(before: h + " ", currentToken: nil)
                let start = ContinuousClock.now
                let got = model.suggestions(after: h, weightDE: context.state.weightDE, german: name != "en", english: name != "de", personal: session.personalBigrams)
                let duration = start.duration(to: .now).components
                times.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
                if got.first?.key == w { after1 += 1 }
                if got.contains(where: { $0.key == w }) { after3 += 1 }
            }
            XCTAssertEqual(after1, pairs.count)
            XCTAssertEqual(after3, pairs.count)
            XCTAssertGreaterThanOrEqual(after3, before)
            print("EVAL P4_learning_\(name) pairs=\(pairs.count) repetitions=6 baselineRecall3=\(before) personalRecall1=\(after1) personalRecall3=\(after3) storedPairs=\(session.personalBigrams.pairCount) training=synthetic_touch_settlement")
        }
        let sorted = times.sorted()
        print(String(format: "EVAL P4_prediction_cost calls=%d meanMs=%.4f p95Ms=%.4f maxMs=%.4f timing=local_debug_not_iPhone maxAdditionalFollowers=8", sorted.count, sorted.reduce(0,+)/Double(sorted.count), sorted[Int(Double(sorted.count-1)*0.95)], sorted.last!))
    }

    func testNoisyTouchPersonalContextQualityAndZeroAutomaticChanges() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        var lexicons: [SpatialWordDecoder.Language: SpatialWordLexicon] = [:]
        for language in SpatialWordDecoder.Language.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(language.rawValue)", withExtension: "words", subdirectory: "WordData"))
            lexicons[language] = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url)))
        }
        let decoder = SpatialWordDecoder(lexicons: lexicons)
        let grid = KeyboardLayout(width: 393, orientation: .portrait, layer: .letters, field: .text, showsGlobe: false, showsStrip: true)
        let de = ["heute", "morgen", "arbeit", "tastatur", "schreiben", "hallo", "schreiben", "technik"]
        let en = ["morning", "keyboard", "world", "hello", "project", "review", "coffee", "writing"]
        var milliseconds = [Double]()
        for (name, words) in [("de", de), ("en", en), ("mixed", de + en)] {
            var hit1 = [0, 0], hit3 = [0, 0], unwanted = [0, 0], changed = 0, n = 0
            let checker = Checker()
            checker.valid.formUnion(words + ["Lena", "Donaudampfschiff", "WeChat", "codeSwitch"])
            for (i, intended) in words.enumerated() {
                let prefix = name == "en" ? "hello " : "ich "
                for error in [SpatialTypoEvaluationEvidence.ErrorClass.neighbour1, .neighbour2, nil] {
                    let evidence = try SpatialTypoEvaluationEvidence.evidence(intended, grid: grid, error: error, ordinal: i,
                                                                            seed: 0x5034, sigma: 0.18)
                    var autos: [String?] = []
                    for variant in 0...1 {
                        let session = KeyboardLearningSession()
                        if variant == 1 { for _ in 0..<6 { session.model.recordPair(intended, after: prefix.trimmingCharacters(in: .whitespaces)) } }
                        let ac = AutocorrectEngine(checker: checker, learning: session, spatialDecoder: decoder, contextResources: .init(model: model))
                        ac.englishEnabled = name != "de"
                        if name != "en" { ac.german = GermanAutocorrect(checker: checker) }
                        var before = prefix
                        for sample in evidence.samples {
                            let after = before + sample.text
                            ac.touchInput.append(text: sample.text, point: sample.point, key: sample.key, layout: grid, before: before, after: after)
                            before = after
                        }
                        let start = ContinuousClock.now
                        let chips = ac.suggestions(beforeInput: before, field: .text, autocorrectionType: .default)
                        let duration = start.duration(to: .now).components
                        milliseconds.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
                        if error != nil {
                            if chips.count > 1 && chips[1].replacement.lowercased() == intended { hit1[variant] += 1 }
                            if chips.contains(where: { $0.replacement.lowercased() == intended }) { hit3[variant] += 1 }
                        }
                        let auto = ac.replacementOnSpace(beforeInput: before, field: .text, autocorrectionType: .default)?.replacement
                        autos.append(auto)
                        if error == nil, let auto, auto.lowercased() != intended { unwanted[variant] += 1 }
                    }
                    if autos[0] != autos[1] { changed += 1 }
                    if error != nil { n += 1 }
                }
            }
            for literal in ["Lena", "Donaudampfschiff", "WeChat", "codeSwitch"] {
                let session = KeyboardLearningSession()
                for _ in 0..<6 { session.model.recordPair("world", after: "ich") }
                let ac = AutocorrectEngine(checker: checker, learning: session, spatialDecoder: decoder, contextResources: .init(model: model))
                XCTAssertNil(ac.replacementOnSpace(beforeInput: "ich " + literal, field: .text, autocorrectionType: .default))
            }
            XCTAssertEqual(changed, 0)
            XCTAssertEqual(unwanted, [0, 0])
            XCTAssertGreaterThanOrEqual(hit3[1], hit3[0])
            print("EVAL P4_noisy_\(name) typos=\(n) baselineRecall1=\(hit1[0]) personalRecall1=\(hit1[1]) baselineRecall3=\(hit3[0]) personalRecall3=\(hit3[1]) cleanControls=\(words.count+4) unwantedBaseline=\(unwanted[0]) unwantedPersonal=\(unwanted[1]) changedAuto=\(changed) validity=injected_not_Apple")
        }
        let sorted = milliseconds.sorted()
        print(String(format: "EVAL P4_noisy_cost calls=%d meanMs=%.4f p95Ms=%.4f maxMs=%.4f timing=local_debug_not_iPhone", sorted.count, sorted.reduce(0,+)/Double(sorted.count), sorted[Int(Double(sorted.count-1)*0.95)], sorted.last!))
    }

    func testPredictionPickSentenceCapitalizationAndGermanNounCasing() async throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        for (text, capitalizes) in [("done. ", true), ("done! ", true), ("done? ", true), ("hello ", false), ("", true)] {
            let (engine, target) = keyboard(text: text)
            target.autocapitalizationType = .sentences
            var chip = KeyboardSuggestion(displayText: "world", replacement: "world", kind: .primary(autoReplace: false), isCompletion: true)
            // Direct owned prediction fixture also covers a field-start pick without inventing a BOS history.
            chip.ownership = engine.suggestionOwnership
            engine.acceptSuggestion(chip)
            XCTAssertEqual(target.text, text + (capitalizes ? "World " : "world "))
            XCTAssertEqual(engine.autocorrect.learning.personalBigrams.pairCount, 0)
        }
        let checker = Checker(); checker.valid.insert("Tastatur")
        let ac = AutocorrectEngine(checker: checker, spatialDecoder: nil, contextResources: .init(model: model))
        ac.german = GermanAutocorrect(checker: checker)
        for _ in 0..<5 { ac.learning.model.recordPair("tastatur", after: "meine") }
        let chips = ac.suggestions(beforeInput: "meine ", field: .text, autocorrectionType: .default)
        XCTAssertTrue(chips.contains { $0.replacement == "Tastatur" })
        XCTAssertTrue(chips.allSatisfy { !$0.willAutoReplace })
    }
}
