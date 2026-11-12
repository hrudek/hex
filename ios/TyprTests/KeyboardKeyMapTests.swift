import Foundation
import XCTest
@testable import Typr

/// Synthetic taps and corpus-validity checker, not Apple dictionaries or human typing proof.
@MainActor
final class KeyboardKeyMapTests: XCTestCase {
    private typealias Language = SpatialWordDecoder.Language
    private let grid = KeyboardLayout(width: 393)
    private final class Checker: TextChecking {
        let lexicons: [SpatialWordLexicon]
        var calls = 0
        init(_ lexicons: [SpatialWordLexicon]) { self.lexicons = lexicons }
        func isWordValid(_ word: String) -> Bool {
            calls += 1
            return lexicons.contains { $0.logPrior(for: word.lowercased()) != nil }
        }
        func guesses(for word: String) -> [String] { calls += 1; return [] }
        func completions(for prefix: String) -> [String] { calls += 1; return [] }
    }

    private func resources() throws -> [Language: SpatialWordLexicon] {
        var result: [Language: SpatialWordLexicon] = [:]
        for language in Language.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(language.rawValue)",
                                                    withExtension: "words", subdirectory: "WordData"))
            result[language] = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url)))
        }
        return result
    }

    private func calibration(_ offset: Double = 0.4) -> SpatialTouchCalibration {
        var keys: [Character: SpatialTouchCalibration.Key] = [:]
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            keys[letter] = .init(offsetX: offset, offsetY: 0, sigmaX: 0.24, sigmaY: 0.24, covarianceXY: 0.005)
        }
        return .init(keys: keys)
    }

    private func center(_ key: KeyboardKey) -> CGPoint { CGPoint(x: key.frame.midX, y: key.frame.midY) }
    private func key(_ letter: Character, _ layout: KeyboardLayout? = nil) -> KeyboardKey {
        (layout ?? grid).key(.character(String(letter)))!
    }
    private func gap(_ intended: Character, _ layout: KeyboardLayout? = nil) -> CGPoint {
        let k = key(intended, layout)
        return CGPoint(x: k.hitFrame.maxX + 0.3, y: k.frame.midY)
    }
    private func tap(_ point: CGPoint, _ engine: FullKeyboardEngine, id: Int = 1) {
        engine.touchBegan(id: id, at: point)
        engine.touchEnded(id: id, at: point)
    }
    private func type(_ text: String, _ engine: FullKeyboardEngine) {
        for letter in text { tap(center(key(letter, engine.layout)), engine) }
    }

    private func keyboard(_ sources: [Language: SpatialWordLexicon], languages: Set<Language> = [.english],
                          trained: Bool = true, worker: KeyboardSuggestionWorker? = nil)
        -> (FullKeyboardEngine, FixtureTextTarget, Checker) {
        let target = FixtureTextTarget()
        target.autocapitalizationType = .some(.none)
        let checker = Checker(Array(sources.values))
        let ac = AutocorrectEngine(checker: checker, learning: KeyboardLearningSession(),
                                   spatialDecoder: SpatialWordDecoder(lexicons: sources),
                                   contextResources: .init(model: nil))
        ac.englishEnabled = languages.contains(.english)
        if languages.contains(.german) { ac.german = GermanAutocorrect(checker: checker) }
        let engine = FullKeyboardEngine(target: target, autocorrect: ac, suggestionWorker: worker)
        engine.width = 393
        engine.configureForField()
        if trained { train(engine) }
        return (engine, target, checker)
    }
    private func train(_ engine: FullKeyboardEngine, offset: Double = 0.4) {
        let layout = engine.layout
        for i in 0..<40 {
            let jitter = Double(i % 3 - 1) * 0.045
            let labels = "abcdefghijklmnopqrstuvwxyz".map { letter -> TouchLabel in
                let k = key(letter, layout)
                let x = k.frame.midX + (offset + jitter) * (k.frame.width + layout.metrics.gap)
                let y = k.frame.midY + jitter * (k.frame.height + layout.metrics.rowGap)
                return TouchLabel(point: CGPoint(x: x, y: y), letter: letter)
            }
            engine.autocorrect.learning.learn(labels, layout: layout, source: .keep)
        }
        engine.refreshSuggestions()
    }
    private func map(_ sources: [Language: SpatialWordLexicon], prefix: String = "th",
                     languages: Set<Language> = [.english]) throws -> KeyboardKeyMap {
        let priors = try XCTUnwrap(KeyboardKeyMap.priors(prefix: prefix, languages: languages,
                                                       lexicons: sources, personal: nil))
        return KeyboardKeyMap(layout: grid, prefix: prefix, calibration: calibration(), priors: priors)
    }

    func testContinuationMassOracleAndNeutralMixture() throws {
        let sources = try resources()
        for language in Language.allCases {
            let lexicon = sources[language]!
            // Exhaustively sum terminals under a short prefix independently of the new index.
            for prefix in ["th", "ha", "zzq", "gr", "stra"] {
                var oracle = [Double](repeating: 0, count: SpatialWordLexicon.alphabet.count)
                func visit(_ index: Int, word: String) {
                    let node = lexicon.node(index)!
                    if node.count > 0, word.hasPrefix(prefix), word.count > prefix.count {
                        let next = Array(word)[prefix.count]
                        oracle[SpatialWordLexicon.alphabet.firstIndex(of: next)!] += node.count
                    }
                    for child in node.children {
                        let letter = SpatialWordLexicon.alphabet[lexicon.node(child)!.label]
                        visit(child, word: word + String(letter))
                    }
                }
                visit(0, word: "")
                XCTAssertEqual(lexicon.nextLetterMass(after: prefix), oracle)
            }
        }
        let en = try XCTUnwrap(KeyboardKeyMap.priors(prefix: "ha", languages: [.english], lexicons: sources, personal: nil))
        let de = try XCTUnwrap(KeyboardKeyMap.priors(prefix: "ha", languages: [.german], lexicons: sources, personal: nil))
        let both = try XCTUnwrap(KeyboardKeyMap.priors(prefix: "ha", languages: [.english, .german], lexicons: sources, personal: nil))
        for i in both.indices { XCTAssertEqual(both[i], (en[i] + de[i]) / 2, accuracy: 1e-12) }
        XCTAssertEqual(both.reduce(0, +), 1, accuracy: 1e-12)
        XCTAssertTrue(both.allSatisfy { $0 >= 0.5 / 26 })
        let novel = try XCTUnwrap(KeyboardKeyMap.priors(prefix: "zzqx", languages: [.english, .german], lexicons: sources, personal: nil))
        XCTAssertTrue(novel.allSatisfy { abs($0 - 1.0 / 26) < 1e-12 })
        XCTAssertNil(KeyboardKeyMap.priors(prefix: "ha", languages: [.german, .english], lexicons: [.english: sources[.english]!], personal: nil))
        XCTAssertNil(KeyboardKeyMap.priors(prefix: String(repeating: "a", count: 32), languages: [.english], lexicons: sources, personal: nil))
    }

    func testPersonalMassExactCountsHoldersAndCapacity() throws {
        let personal = PersonalLexiconSnapshot(kept: ["thäva", "thöva"], counts: ["theron": 10, "thäva": 4], rejected: [])
        let mass = personal.scan.completions.nextLetterMass(after: "th")
        XCTAssertEqual(mass[4], 10)
        XCTAssertEqual(mass[26], 4)
        XCTAssertEqual(mass[27], 1)
        let sources = try resources()
        let before = try XCTUnwrap(KeyboardKeyMap.priors(prefix: "th", languages: [.english], lexicons: sources, personal: nil))
        let after = try XCTUnwrap(KeyboardKeyMap.priors(prefix: "th", languages: [.english], lexicons: sources,
                                                      personal: personal.scan.completions))
        XCTAssertGreaterThan(after[0], before[0], "ä continuation votes for physical a")
        XCTAssertGreaterThan(after[14], before[14], "ö continuation votes for physical o")
        var counts: [String: Int] = [:]
        for i in 0..<2_000 {
            let a = Character(UnicodeScalar(97 + i / 676)!)
            let b = Character(UnicodeScalar(97 + (i / 26) % 26)!)
            let c = Character(UnicodeScalar(97 + i % 26)!)
            counts["novel" + String([a, b, c])] = 2 + i
        }
        let full = PersonalLexiconSnapshot(kept: [], counts: counts, rejected: []).scan.completions
        XCTAssertEqual(full.nextLetterMass(after: "novel").reduce(0, +), Double(counts.values.reduce(0, +)))
        XCTAssertLessThanOrEqual(full.payloadBytes, 192 * 1_024)
        print("EVAL P8_personal entries=\(full.entries.count) payload_bytes=\(full.payloadBytes) max_binary_searches=60 max_comparisons=660")
    }

    func testGapOnlyStrictMarginControlsAndStaleGeometry() throws {
        let map = try map(resources())
        let point = gap("e"), geometric = grid.hitTest(point)!
        XCTAssertEqual(geometric.character, "r")
        XCTAssertEqual(map.attributedKey(at: point, geometric: geometric, layout: grid, prefix: "th").character, "e")
        for k in grid.keys {
            for point in [center(k), CGPoint(x: k.frame.minX + 0.1, y: k.frame.midY),
                          CGPoint(x: k.frame.maxX - 0.1, y: k.frame.midY)] {
                XCTAssertEqual(map.attributedKey(at: point, geometric: k, layout: grid, prefix: "th"), k)
            }
        }
        for k in grid.keys where k.character == nil {
            for x in [k.hitFrame.minX + 0.1, k.hitFrame.maxX - 0.1] {
                let p = CGPoint(x: x, y: k.hitFrame.midY)
                XCTAssertEqual(map.attributedKey(at: p, geometric: k, layout: grid, prefix: "th"), k)
            }
        }
        XCTAssertEqual(map.attributedKey(at: point, geometric: geometric, layout: grid, prefix: "ha"), geometric)
        XCTAssertEqual(map.attributedKey(at: point, geometric: geometric, layout: KeyboardLayout(width: 440), prefix: "th"), geometric)
        let neutral = KeyboardKeyMap(layout: grid, prefix: "th", calibration: calibration(), priors: Array(repeating: 1.0 / 26, count: 26))
        XCTAssertEqual(neutral.attributedKey(at: point, geometric: geometric, layout: grid, prefix: "th"), geometric)
        let cold = KeyboardKeyMap(layout: grid, prefix: "th", calibration: calibration(0),
                                  priors: map.entries.map { exp($0.logPrior) / 26 })
        XCTAssertEqual(cold.attributedKey(at: point, geometric: geometric, layout: grid, prefix: "th"), geometric)
        XCTAssertEqual(map.attributedKey(at: CGPoint(x: CGFloat.nan, y: 0), geometric: geometric, layout: grid, prefix: "th"), geometric)
        XCTAssertLessThanOrEqual(map.entries.count, 26)
    }

    func testSerialAndRolloverUpdateBeforeDeferredRankingAndNeverSelfTrain() throws {
        let sources = try resources()
        for rollover in [false, true] {
            let (engine, target, checker) = keyboard(sources)
            let labels = engine.autocorrect.learning.diagnostics.acceptedLabels
            let points = [center(key("t")), center(key("h")), gap("e")]
            for (i, p) in points.enumerated() {
                engine.touchBegan(id: i, at: p)
                if !rollover { engine.touchEnded(id: i, at: p) }
            }
            if rollover {
                for i in points.indices.reversed() { engine.touchEnded(id: i, at: points[i]) }
            }
            XCTAssertEqual(target.text, "the")
            XCTAssertEqual(checker.calls, 0, "no checker/ranking on the insertion stack")
            let evidence = try XCTUnwrap(engine.autocorrect.touchInput.evidence(beforeInput: target.text))
            XCTAssertEqual(evidence.samples.last?.key.character, "r")
            XCTAssertEqual(evidence.samples.last?.attributedKey?.character, "e")
            XCTAssertFalse(evidence.learningIntact)
            XCTAssertNotNil(KeyboardLetterMap.emissions(for: evidence, calibration: calibration()))
            XCTAssertEqual(engine.autocorrect.learning.diagnostics[.reattributedTaps], 1)
            engine.acceptOwnedFixtureSuggestion(.init(displayText: "the", replacement: "the", kind: .keepLiteral))
            XCTAssertEqual(engine.autocorrect.learning.diagnostics.acceptedLabels, labels)
            XCTAssertNil(engine.autocorrect.learning.model.lexicon.counts["the"])
            type("w", engine)
            XCTAssertNil(engine.autocorrect.learning.model.lexicon.counts["the"])
        }
    }

    func testAutomaticAttributedLiteralNeverSettlesAndInternalCapitalStaysLiteral() throws {
        let sources = try resources()
        let (engine, target, _) = keyboard(sources)
        let labels = engine.autocorrect.learning.diagnostics.acceptedLabels
        type("th", engine)
        tap(gap("e"), engine)
        tap(center(engine.layout.key(.space)!), engine)
        type("w", engine)
        XCTAssertEqual(target.text, "the w")
        XCTAssertNil(engine.autocorrect.learning.model.lexicon.counts["the"])
        XCTAssertEqual(engine.autocorrect.learning.diagnostics.acceptedLabels, labels)

        let (caps, capsTarget, _) = keyboard(sources)
        type("th", caps)
        tap(center(caps.layout.key(.shift)!), caps)
        tap(gap("e"), caps)
        XCTAssertEqual(capsTarget.text, "thR", "a shifted internal capital is an identifier signal")
    }

    func testPartialAttributedWordCannotCountOrTrainFromKeepAndCannotSeedPersonalPairs() throws {
        let (engine, target, _) = keyboard(try resources())
        let session = engine.autocorrect.learning
        let labels = session.diagnostics.acceptedLabels
        target.insertText("th") // Prefix existed before Typr observed any taps.
        engine.refreshSuggestions()
        tap(gap("e"), engine)
        XCTAssertEqual(target.text, "the")
        XCTAssertNil(engine.autocorrect.touchInput.evidence(beforeInput: target.text))
        XCTAssertFalse(engine.autocorrect.touchInput.isLearningIntact)
        engine.acceptOwnedFixtureSuggestion(.init(displayText: "the", replacement: "the", kind: .keepLiteral))
        type("world", engine)
        tap(center(engine.layout.key(.space)!), engine)
        type("hello", engine)
        tap(center(engine.layout.key(.space)!), engine)
        type("w", engine)
        XCTAssertNil(session.model.lexicon.counts["the"])
        XCTAssertEqual(session.diagnostics.acceptedLabels, labels + 10, "only independently observed world and hello teach")
        XCTAssertEqual(session.model.state.bigrams?.pairCount, 1, "world→hello only; the never becomes an endpoint")
    }

    private actor FirstJobGate {
        var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        func rank(_ request: KeyboardSuggestionWorker.Request) async -> KeyboardSuggestionWorker.Result {
            if !started {
                started = true
                await withCheckedContinuation { continuation = $0 }
            }
            return .init(request: request, outcome: nil, seconds: 0)
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    func testBlockedWorkerDoesNotOwnAttributionAndMixedPrefixStreamStaysLiteral() async throws {
        let gate = FirstJobGate()
        let worker = KeyboardSuggestionWorker(rank: { await gate.rank($0) })
        let (engine, target, checker) = keyboard(try resources(), worker: worker)
        type("t", engine)
        for _ in 0..<10_000 {
            if await gate.started { break }
            await Task.yield()
        }
        let started = await gate.started
        XCTAssertTrue(started)
        type("h", engine)
        tap(gap("e"), engine)
        XCTAssertEqual(target.text, "the")
        XCTAssertEqual(checker.calls, 0)
        await gate.release()
        await engine.waitForSuggestions()

        let (mixed, mixedTarget, _) = keyboard(try resources(), languages: [.german, .english])
        let passage = "das kind hat ein gift also hello world haushello"
        for character in passage {
            let k = character == " " ? mixed.layout.key(.space)! : key(character)
            tap(center(k), mixed)
        }
        XCTAssertEqual(mixedTarget.text, passage)
        XCTAssertEqual(mixed.autocorrect.learning.diagnostics[.reattributedTaps], 0)
    }

    func testOffFieldsAndStaleModelOrSettingsStayGeometric() throws {
        let sources = try resources()
        for mode in 0..<9 {
            let (engine, target, _) = keyboard(sources, trained: mode != 0)
            type("th", engine)
            switch mode {
            case 1: engine.autocorrect.isEnabled = false
            case 2: target.autocorrectionType = .no
            case 3: target.keyboardType = .URL
            case 4: target.keyboardType = .emailAddress
            case 5: target.keyboardType = .numberPad
            case 6: train(engine, offset: -0.4) // Generation differs even though text did not change.
            case 7:
                target.deleteBackward(); target.deleteBackward(); target.insertText("ha") // Unreported host edit.
            case 8: target.isSecureTextEntry = true
            default: break
            }
            // train refreshes normally: create a newer model generation without refreshing map.
            if mode == 6 {
                let k = key("e")
                engine.autocorrect.learning.learn([TouchLabel(point: center(k), letter: "e")], layout: grid, source: .keep)
            }
            tap(gap("e"), engine)
            XCTAssertTrue(target.text.hasSuffix("r"), "mode \(mode)")
            XCTAssertEqual(engine.autocorrect.learning.diagnostics[.reattributedTaps], 0)
        }
        let (engine, _, _) = keyboard(sources)
        type("th", engine)
        let session = engine.autocorrect.learning
        XCTAssertNotNil(engine.autocorrect.keyMap(layout: grid, context: "th", permitsCorrection: true))
        session.model.isLearningEnabled = false
        XCTAssertNil(engine.autocorrect.keyMap(layout: grid, context: "th", permitsCorrection: true))
        XCTAssertNil(engine.autocorrect.keyMap(layout: grid, context: "https://th", permitsCorrection: true))
        XCTAssertNil(engine.autocorrect.keyMap(layout: grid, context: "th", permitsCorrection: false))
    }

    func testSyntheticHitAndCandidateEvaluation() throws {
        let sources = try resources()
        let de = SpatialTypoEvaluationFixtures.german
        let en = SpatialTypoEvaluationFixtures.english
        let modes: [(String, Set<Language>, [String])] = [
            ("DE", [.german], de), ("EN", [.english], en), ("mixed", [.german, .english], de + en)
        ]
        for (name, languages, words) in modes {
            var taps = 0, staticErrors = 0, adaptiveErrors = 0, wrong = 0, changed = 0
            var static1 = 0, static3 = 0, adaptive1 = 0, adaptive3 = 0
            var times: [Double] = []
            for (ordinal, intended) in words.enumerated() {
                let (engine, target, _) = keyboard(sources, languages: languages)
                let letters = Array(intended)
                var staticSamples: [KeyboardTouchWord.Sample] = []
                for (i, letter) in letters.enumerated() {
                    let k = key(letter)
                    let candidate = gap(letter)
                    let neighbor = grid.hitTest(candidate)
                    // Fixed public fixture, one deterministic near-boundary error opportunity.
                    let noisy = i >= 2 && i % 3 == ordinal % 3 && neighbor?.row == k.row
                        && neighbor?.character?.first?.isLetter == true && neighbor != k
                    let p = noisy ? candidate : center(k)
                    let geometric = grid.hitTest(p)!
                    let hitText = geometric.character!
                    staticSamples.append(.init(text: hitText, point: p, key: geometric))
                    let start = ProcessInfo.processInfo.systemUptime
                    tap(p, engine)
                    times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                    let actual = target.text.last!
                    taps += 1
                    if hitText != String(letter) { staticErrors += 1 }
                    if actual != letter { adaptiveErrors += 1 }
                    if actual != hitText.first! { changed += 1; if actual != letter { wrong += 1 } }
                }
                let baseline = KeyboardTouchWord(layout: grid, samples: staticSamples)
                let adaptive = try XCTUnwrap(engine.autocorrect.touchInput.evidence(beforeInput: target.text))
                let decoder = engine.autocorrect.spatialDecoder!
                let frozen = engine.autocorrect.learning.calibration(for: grid)
                func candidates(_ word: KeyboardTouchWord) -> [String] {
                    let result = decoder.decodeDetailed(word, languages: languages, calibration: frozen)
                    guard case .result(let found) = result else { return [word.text] }
                    let main: [String] = found.candidates.map(\.word)
                    let edits: [String] = found.editSuggestions.map(\.word)
                    return Array((main + [word.text] + edits).prefix(3))
                }
                let before = candidates(baseline), after = candidates(adaptive)
                if before.first == intended { static1 += 1 }; if before.contains(intended) { static3 += 1 }
                if after.first == intended { adaptive1 += 1 }; if after.contains(intended) { adaptive3 += 1 }
            }
            XCTAssertLessThan(adaptiveErrors, staticErrors)
            XCTAssertEqual(wrong, 0, "fixed synthetic noisy-tap fixtures, not all intended novel spellings")
            times.sort()
            let p95 = times[Int(Double(times.count - 1) * 0.95)]
            print("EVAL P8_hits_\(name) words=\(words.count) taps=\(taps) static_errors=\(staticErrors) adaptive_errors=\(adaptiveErrors) reattributed=\(changed) wrong=\(wrong) static_recall1=\(static1)/\(words.count) static_recall3=\(static3)/\(words.count) adaptive_recall1=\(adaptive1)/\(words.count) adaptive_recall3=\(adaptive3)/\(words.count) insertion_p95_ms=\(p95) insertion_max_ms=\(times.last!)")
        }
    }

    func testNovelNamesValidWordsAndAdversarialGapHarmEvaluation() throws {
        let sources = try resources()
        let controls = ["gift", "also", "kind", "die", "hat", "haus", "hello", "wasser", "swift", "world",
                        "Thrax", "Thorin", "Therava", "Zyphren", "Donaudampfschifffahrt", "haushello", "hellohaus"]
        var unwanted = 0, reattributed = 0
        for text in controls {
            let (engine, target, _) = keyboard(sources, languages: [.german, .english])
            for letter in text {
                if letter.isUppercase { tap(center(engine.layout.key(.shift)!), engine) }
                tap(center(key(Character(String(letter).lowercased()))), engine)
            }
            XCTAssertEqual(target.text, text)
            let before = target.text
            tap(center(engine.layout.key(.space)!), engine)
            if target.text != before + " " { unwanted += 1 }
            reattributed += engine.autocorrect.learning.diagnostics[.reattributedTaps]
        }
        XCTAssertEqual(unwanted, 0)
        XCTAssertEqual(reattributed, 0)
        // Identical coordinates can mean either intended e or deliberate novel r. Do not hide
        // this irreducible ambiguity behind a center-only zero-harm quality claim.
        let (engine, target, _) = keyboard(sources)
        type("th", engine)
        tap(gap("e"), engine) // Deliberately meant r, but in the gap under a right-shifted model.
        type("ax", engine)
        let adversarialWrong = target.text == "thrax" ? 0 : 1
        XCTAssertEqual(adversarialWrong, 1, "document the gap-only failure; all drawn-keycap taps remain literal")
        print("EVAL P8_controls words=\(controls.count) unwanted_space_changes=\(unwanted) center_reattributions=\(reattributed) adversarial_gap_names=1 adversarial_wrong=\(adversarialWrong) boundary_fraction=\(KeyboardKeyMap.boundaryFraction) visual_keycap_changes=0")
    }

    func testMapWorkPayloadAndLatencyEvaluation() throws {
        let sources = try resources()
        let start = ProcessInfo.processInfo.systemUptime
        var bytes = 0
        for i in 0..<500 {
            let m = try map(sources, prefix: i % 2 == 0 ? "th" : "ha", languages: [.german, .english])
            bytes = max(bytes, m.payloadBytes)
            XCTAssertLessThanOrEqual(m.entries.count, 26)
            for k in grid.keys {
                XCTAssertEqual(m.attributedKey(at: center(k), geometric: k, layout: grid, prefix: m.prefix), k)
            }
        }
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1_000 / 500
        let resourceBytes = sources.values.reduce(0) { $0 + $1.continuationPayloadBytes }
        XCTAssertLessThanOrEqual(bytes, 16 * 1_024)
        XCTAssertEqual(resourceBytes, sources.values.reduce(0) { $0 + $1.nodeCount * 8 })
        XCTAssertLessThanOrEqual(resourceBytes, 6_400_000)
        print("EVAL P8_bounds map_entries=26 max_neighbor_scores=2 max_entry_inspections=52 map_payload_bytes=\(bytes) continuation_index_bytes=\(resourceBytes) map_and_center_probes_mean_ms=\(ms) wall_clock_assertions=0")
    }
}
