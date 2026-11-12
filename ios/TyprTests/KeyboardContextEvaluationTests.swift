import Foundation
import XCTest
@testable import Typr

final class KeyboardContextEvaluationTests: XCTestCase {
    func testSyntheticNextWordsMixtureLatencyAndPayload() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        // Independently authored synthetic sequences, not private text or a claim of
        // corpus-disjoint natural messaging. Predictions are measured before the target.
        let sets = [
            ("de", ["ich bin heute zu hause", "das ist ein guter tag", "wir haben keine zeit", "ich habe ein buch"]),
            ("en", ["i am going to the house", "this is a good day", "we have no time", "i have a book"]),
            ("mixed", ["ich habe ein meeting morgen", "i have a hund today", "das ist good", "this is gut"])
        ]
        var times: [Double] = []
        for (name, sentences) in sets {
            var hit1 = 0, hit3 = 0, baseline = 0, wrong = 0, naiveWrong = 0, pairs = 0
            var rr = 0.0
            for sentence in sentences {
                let words = sentence.split(separator: " ").map(String.init)
                var state = KeyboardContextModel.State()
                for i in 0..<(words.count - 1) {
                    state.consume(words[i], model: model)
                    let start = ContinuousClock.now
                    let got = model.suggestions(after: words[i], weightDE: state.weightDE,
                                                german: name != "en", english: name != "de")
                    let elapsed = start.duration(to: .now).components
                    times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                    let keys = got.map(\.key), target = words[i + 1]
                    if let rank = keys.firstIndex(of: target) { hit3 += 1; rr += 1 / Double(rank + 1); if rank == 0 { hit1 += 1 } }
                    let uni = model.suggestions(after: nil, weightDE: state.weightDE, german: name != "en", english: name != "de")
                    if uni.contains(where: { $0.key == target }) { baseline += 1 }
                    // D3b's fixed >=4:1 smoothed unigram language proxy, all slots denominator.
                    // Synthetic mixed targets use their own unambiguous corpus label.
                    let ratio = model.logRatio(target)
                    let gold = name == "de" ? 1 : name == "en" ? -1 : ratio >= log(4) ? 1 : ratio <= -log(4) ? -1 : 0
                    func isWrong(_ key: String) -> Bool {
                        let r = model.logRatio(key)
                        return gold == 1 ? r <= -log(4) : gold == -1 ? r >= log(4) : false
                    }
                    wrong += keys.filter(isWrong).count
                    naiveWrong += model.suggestions(after: words[i], weightDE: 0.5,
                                                    german: name != "en", english: name != "de").filter { isWrong($0.key) }.count
                    XCTAssertTrue(Set(keys).isDisjoint(with: KeyboardContextModel.suppressed))
                    pairs += 1
                }
            }
            print(String(format: "EVAL context_next_%@ pairs=%d recall1=%.4f recall3=%.4f mrr3=%.4f unigram_recall3=%.4f wrong_rate=%.4f naive_wrong_rate=%.4f", name, pairs, Double(hit1)/Double(pairs), Double(hit3)/Double(pairs), rr/Double(pairs), Double(baseline)/Double(pairs), Double(wrong)/Double(pairs*3), Double(naiveWrong)/Double(pairs*3)))
            if name != "mixed" { XCTAssertGreaterThanOrEqual(hit3, baseline) }
            if name == "mixed" { XCTAssertLessThanOrEqual(wrong, naiveWrong) }
        }
        times.sort()
        XCTAssertLessThan(times.last!, 500) // Debug Linux CI guard, not a phone latency promise.
        XCTAssertEqual(model.residentPayloadBytes, 694_793)
        XCTAssertLessThan(model.residentPayloadBytes, 1_048_576)
        print(String(format: "EVAL context_cost calls=%d mean_ms=%.4f p95_ms=%.4f max_ms=%.4f mapped_bytes=%d index_bytes=32000 resident_payload_bytes=%d max_seen_keys=16000 context_utf8_cap=2048", times.count, times.reduce(0,+)/Double(times.count), times[Int(Double(times.count-1)*0.95)], times.last!, model.residentPayloadBytes-32000, model.residentPayloadBytes))
    }

    func testCC0HeldoutNextWordEvaluation() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "context-heldout-cc0", withExtension: "json", subdirectory: "WordData"))
        struct Fixture: Decodable { let sentences: [String: [[String]]] }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        for language in ["de", "en"] {
            var n = 0, h1 = 0, h3 = 0, uni = 0, wrong = 0
            var rr = 0.0
            for words in try XCTUnwrap(fixture.sentences[language]) {
                var state = KeyboardContextModel.State()
                for i in 0..<(words.count - 1) {
                    let h = KeyboardContextModel.key(words[i]), w = KeyboardContextModel.key(words[i+1])
                    state.consume(h, model: model)
                    let got = model.suggestions(after: h, weightDE: state.weightDE,
                                                german: language == "de", english: language == "en")
                    if let rank = got.firstIndex(where: { $0.key == w }) {
                        h3 += 1; rr += 1 / Double(rank + 1); if rank == 0 { h1 += 1 }
                    }
                    if model.suggestions(after: nil, weightDE: state.weightDE, german: language == "de", english: language == "en").contains(where: { $0.key == w }) { uni += 1 }
                    wrong += got.filter { language == "de" ? model.logRatio($0.key) <= -log(4) : model.logRatio($0.key) >= log(4) }.count
                    n += 1
                }
            }
            print(String(format: "EVAL context_heldout_%@ sentences=64 pairs=%d recall1=%.4f recall3=%.4f mrr3=%.4f unigram_recall3=%.4f wrong_rate=%.4f source=CC0_CV_global_test_partition", language, n, Double(h1)/Double(n), Double(h3)/Double(n), rr/Double(n), Double(uni)/Double(n), Double(wrong)/Double(n*3)))
            XCTAssertGreaterThan(h3, uni)
            XCTAssertLessThan(Double(wrong)/Double(n*3), 0.2)
        }
    }

    @MainActor
    func testIntegratedNoisyTouchAndZeroAddedAutomaticChanges() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        var lexicons: [SpatialWordDecoder.Language: SpatialWordLexicon] = [:]
        for l in SpatialWordDecoder.Language.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(l.rawValue)", withExtension: "words", subdirectory: "WordData"))
            lexicons[l] = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url, options: .mappedIfSafe)))
        }
        let cases = [("de", "ich bin ", "heute"), ("de", "wir haben ", "arbeit"), ("de", "das ist ", "gut"),
                     ("en", "this is ", "good"), ("en", "i am ", "going"), ("en", "good ", "morning"),
                     ("mixed", "ich habe ein ", "meeting"), ("mixed", "i have a ", "hund"), ("mixed", "das ist ", "good")]
        let grid = KeyboardLayout(width: 393, orientation: .portrait, layer: .letters, field: .text, showsGlobe: false, showsStrip: true)
        for name in ["de", "en", "mixed"] {
            var counts = [[0, 0], [0, 0]], autos = [String?](), calls = 0
            for (_, context, intended) in cases.filter({ $0.0 == name }) {
                let letters = Array(intended)
                let first = grid.key(.character(String(letters[0])))!.frame
                let neighbor = grid.keys.filter { $0.character != nil && $0.kind != .character(String(letters[0])) }
                    .min { hypot($0.frame.midX-first.midX, $0.frame.midY-first.midY) < hypot($1.frame.midX-first.midX, $1.frame.midY-first.midY) }!
                let typo = neighbor.character! + String(intended.dropFirst())
                for variant in 0...1 {
                    let checker = Checker(valid: [intended], guesses: [intended])
                    let ac = AutocorrectEngine(checker: checker, spatialDecoder: SpatialWordDecoder(lexicons: lexicons),
                                               contextResources: KeyboardContextResources(model: variant == 1 ? model : nil))
                    ac.englishEnabled = name != "de"
                    if name != "en" { ac.german = GermanAutocorrect(checker: checker) }
                    var before = context
                    for (j, typed) in typo.enumerated() {
                        let frame = grid.key(.character(String(letters[j])))!.frame
                        let after = before + String(typed)
                        ac.touchInput.append(text: String(typed), point: CGPoint(x: frame.midX + 1.5, y: frame.midY - 1),
                                             key: grid.key(.character(String(typed)))!, layout: grid, before: before, after: after)
                        before = after
                    }
                    let suggestions = ac.suggestions(beforeInput: before, field: .text, autocorrectionType: .default)
                        .filter { $0.kind != .keepLiteral }.map { KeyboardContextModel.key($0.replacement) }
                    if suggestions.first == intended { counts[variant][0] += 1 }
                    if suggestions.prefix(3).contains(intended) { counts[variant][1] += 1 }
                    autos.append(ac.replacementOnSpace(beforeInput: before, field: .text, autocorrectionType: .default)?.replacement)
                }
                XCTAssertEqual(autos[autos.count-2], autos.last!)
                calls += 1
            }
            print("EVAL context_noisy_\(name) samples=\(calls) baseline_recall1=\(counts[0][0])/\(calls) context_recall1=\(counts[1][0])/\(calls) baseline_recall3=\(counts[0][1])/\(calls) context_recall3=\(counts[1][1])/\(calls) changed_auto_decisions=0")
            XCTAssertGreaterThanOrEqual(counts[1][1], counts[0][1])
        }
        let controls = ["im", "in", "am", "die", "war", "will", "also", "Gift", "Chef", "schon", "schön", "Straße", "Masse", "Maße", "Velqora", "OpenTelemetry", "WASM", "hausfenster", "meeting", "camelCase"]
        let checker = Checker(valid: Set(controls), guesses: [])
        let ac = AutocorrectEngine(checker: checker, spatialDecoder: SpatialWordDecoder(lexicons: lexicons), contextResources: .init(model: model))
        ac.german = GermanAutocorrect(checker: checker)
        for word in controls { XCTAssertNil(ac.replacementOnSpace(beforeInput: "ich habe \(word)", field: .text, autocorrectionType: .default)) }
        print("EVAL context_controls words=\(controls.count) unwanted_auto=0 added_auto=0 validity=injected_dictionary")
    }

    @MainActor
    func testEngineAfterSpaceAcceptAndSettings() throws {
        let model = try XCTUnwrap(KeyboardContextModelTests.model)
        let guessChecker = Checker(valid: [], guesses: ["hallo", "habe"])
        let ranked = AutocorrectEngine(checker: guessChecker, spatialDecoder: nil, contextResources: .init(model: model))
        ranked.englishEnabled = false; ranked.german = GermanAutocorrect(checker: guessChecker)
        let baseline = AutocorrectEngine(checker: guessChecker, spatialDecoder: nil, contextResources: .init(model: nil))
        baseline.englishEnabled = false; baseline.german = GermanAutocorrect(checker: guessChecker)
        XCTAssertEqual(baseline.suggestions(beforeInput: "ich ha", field: .text, autocorrectionType: .default)[1].replacement, "hallo")
        let promoted = ranked.suggestions(beforeInput: "ich ha", field: .text, autocorrectionType: .default)[1]
        XCTAssertEqual(promoted.replacement, "habe")
        XCTAssertTrue(promoted.isCompletion)
        XCTAssertFalse(promoted.willAutoReplace)
        XCTAssertNil(ranked.replacementOnSpace(beforeInput: "ich ha", field: .text, autocorrectionType: .default))
        let ac = AutocorrectEngine(checker: Checker(valid: [], guesses: []), spatialDecoder: nil, contextResources: .init(model: model))
        let target = FixtureTextTarget(text: "i am ")
        let engine = FullKeyboardEngine(target: target, autocorrect: ac)
        engine.configureForField()
        XCTAssertEqual(engine.suggestions.count, 3)
        XCTAssertTrue(engine.suggestions.allSatisfy { !$0.willAutoReplace && $0.kind != .keepLiteral })
        let first = try XCTUnwrap(engine.suggestions.first)
        engine.acceptSuggestion(first)
        XCTAssertEqual(target.text, "i am " + first.replacement + " ")
        XCTAssertTrue(ac.learning.model.lexicon.counts.isEmpty)
        XCTAssertEqual(ac.learning.diagnostics.acceptedLabels, 0)
        ac.isEnabled = false
        XCTAssertTrue(ac.suggestions(beforeInput: "i am ", field: .text, autocorrectionType: .default).isEmpty)
        ac.isEnabled = true; ac.englishEnabled = false
        XCTAssertTrue(ac.suggestions(beforeInput: "i am ", field: .text, autocorrectionType: .default).isEmpty)
        ac.englishEnabled = true
        for text: String? in [nil, "", "123 ", "https://example.com "] {
            XCTAssertTrue(ac.suggestions(beforeInput: text, field: .text, autocorrectionType: .default).isEmpty)
        }
        XCTAssertTrue(ac.suggestions(beforeInput: "i am ", field: .url, autocorrectionType: .default).isEmpty)
        XCTAssertTrue(ac.suggestions(beforeInput: "i am ", field: .text, autocorrectionType: .no).isEmpty)
    }

    @MainActor
    func testDetachedResourcePreparationAndReadinessCallback() async throws {
        let resources = KeyboardContextResources(bundle: Bundle.main)
        XCTAssertNil(resources.model)
        let start = ContinuousClock.now
        await withCheckedContinuation { continuation in
            resources.prepare { continuation.resume() }
        }
        XCTAssertEqual(resources.model?.residentPayloadBytes, 694_793)
        let elapsed = start.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        XCTAssertLessThan(milliseconds, 10_000)
        print(String(format: "EVAL context_prepare elapsed_ms=%.3f payload_bytes=694793 mapping=if_safe timing=Linux_debug", milliseconds))
    }

    @MainActor private final class Checker: TextChecking {
        let valid: Set<String>
        let answers: [String]
        init(valid: Set<String>, guesses: [String]) { self.valid = valid; answers = guesses }
        func isWordValid(_ word: String) -> Bool { valid.contains(word) }
        func guesses(for word: String) -> [String] { answers }
        func completions(for prefix: String) -> [String] { [] }
    }
}
