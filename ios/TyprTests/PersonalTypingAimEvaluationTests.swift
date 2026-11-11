import Foundation
import XCTest
@testable import Typr

/// Public-word, seeded synthetic ablation. Not a system dictionary or physical hit-test benchmark.
@MainActor
final class PersonalTypingAimEvaluationTests: XCTestCase {
    private let grid = KeyboardLayout(width: 393)
    private let checkpoints = [0, 3, 12, 30, 60]

    private struct Noise {
        var state: UInt64 = 0x50375f41494d
        mutating func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / 9007199254740992
        }
        mutating func normal() -> Double { sqrt(-2 * log(uniform())) * cos(2 * Double.pi * uniform()) }
    }

    private func point(_ letter: Character, x: Double, y: Double) -> CGPoint {
        let frame = grid.key(.character(String(letter)))!.frame
        return CGPoint(x: frame.midX + x * (frame.width + grid.metrics.gap),
                       y: frame.midY + y * (frame.height + grid.metrics.rowGap))
    }

    private func offset(_ letter: Character, shifted: Bool, rotation: Bool) -> (Double, Double) {
        guard shifted else { return (0, 0) }
        let frame = grid.key(.character(String(letter)))!.frame
        let pitchX = Double(frame.width + grid.metrics.gap), pitchY = Double(frame.height + grid.metrics.rowGap)
        if rotation {
            // A small one-hand rotation about the middle of the letter plane, plus translation.
            let dx = Double(frame.midX) - 196.5, dy = Double(frame.midY) - 125
            return ((6 - 0.055 * dy) / pitchX, (4 + 0.055 * dx) / pitchY)
        }
        return (6 / pitchX, 4 / pitchY)
    }

    private func train(_ model: PersonalTypingModel, count: Int, shifted: Bool, rotation: Bool, start: Int = 0) {
        let letters = Array("etaoinshrdlucmfwypvbgkjqxz")
        for i in start..<(start + count) {
            let letter = letters[i % letters.count], shift = offset(letter, shifted: shifted, rotation: rotation)
            let x = shift.0 + Double(i % 5 - 2) * 0.035
            let y = shift.1 + Double(i % 3 - 1) * 0.035
            model.learn([TouchLabel(point: point(letter, x: x, y: y), letter: letter)], layout: grid, source: .manualPick)
        }
    }

    private func evidence(_ word: String, ordinal: Int, shifted: Bool, rotation: Bool, noisy: Bool = true) -> KeyboardTouchWord {
        let letters = Array(word.lowercased())
        var noise = Noise(state: 0x50375f41494d &+ UInt64(ordinal) &* 97)
        let samples = letters.enumerated().map { i, letter in
            let shift = offset(letter, shifted: shifted, rotation: rotation)
            let target = grid.key(.character(String(letter)))!
            // A fixed adjacent-symbol error separates word retrieval from static hit attribution.
            let typed: KeyboardKey
            if i == ordinal % letters.count {
                typed = grid.keys.filter { $0.character?.count == 1 && $0.character != String(letter)
                    && $0.character?.first?.isLetter == true }.min {
                    hypot($0.frame.midX - target.frame.midX, $0.frame.midY - target.frame.midY)
                        < hypot($1.frame.midX - target.frame.midX, $1.frame.midY - target.frame.midY)
                }!
            } else { typed = target }
            let sigma = noisy ? 0.22 : 0
            return KeyboardTouchWord.Sample(text: typed.character!,
                point: point(letter, x: shift.0 + sigma * noise.normal(), y: shift.1 + sigma * noise.normal()), key: typed)
        }
        return KeyboardTouchWord(layout: grid, samples: samples)
    }

    /// Exact old per-key threshold/shrinkage/diagonal contract, updated by the SAME labels.
    private func diagonal(_ state: PersonalTypingModel.State) -> SpatialTouchCalibration? {
        guard let layout = state.layouts[KeyboardLayoutSignature(grid).id] else { return nil }
        var keys: [Character: SpatialTouchCalibration.Key] = [:]
        for (letter, stats) in layout.keys where stats.n >= 20 {
            var key = stats.calibration; key.covarianceXY = 0
            keys[letter.first!] = key
        }
        return keys.isEmpty ? nil : SpatialTouchCalibration(keys: keys)
    }

    private func decoder() throws -> SpatialWordDecoder {
        var sources: [SpatialWordDecoder.Language: SpatialWordLexicon] = [:]
        for language in SpatialWordDecoder.Language.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(language.rawValue)", withExtension: "words", subdirectory: "WordData"))
            sources[language] = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url)))
        }
        return SpatialWordDecoder(lexicons: sources)
    }

    func testGripShiftAndReturnCurvesGermanEnglishMixed() throws {
        let decoder = try decoder()
        let groups = [("DE", Array(SpatialTypoEvaluationFixtures.german.prefix(20))),
                      ("EN", Array(SpatialTypoEvaluationFixtures.english.prefix(20))),
                      ("mixed", Array(zip(SpatialTypoEvaluationFixtures.german.prefix(10), SpatialTypoEvaluationFixtures.english.prefix(10))).flatMap { [$0, $1] })]
        var timings: [Double] = []
        for rotation in [false, true] {
            let model = PersonalTypingModel()
            train(model, count: 26 * 160, shifted: false, rotation: false)
            for shifted in [true, false] {
                var trained = 0
                var curves: [String: [String]] = [:]
                for taps in checkpoints {
                    train(model, count: taps - trained, shifted: shifted, rotation: rotation, start: trained)
                    trained = taps
                    let legacy = diagonal(model.state), adaptive = model.calibration(for: grid)
                    for (group, words) in groups {
                        var recalled = [0, 0], top3 = [0, 0], autoWrong = [0, 0], unavailable = [0, 0]
                        for (ordinal, word) in words.enumerated() {
                            let input = evidence(word, ordinal: ordinal, shifted: shifted, rotation: rotation)
                            for (variant, calibration) in [legacy, adaptive].enumerated() {
                                let start = ProcessInfo.processInfo.systemUptime
                                let decoded = decoder.decode(input, languages: [.german, .english], calibration: calibration)
                                timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                                guard let result = decoded else { unavailable[variant] += 1; continue }
                                XCTAssertTrue(result.complete)
                                if result.suggestions.first?.word == word { recalled[variant] += 1 }
                                if result.suggestions.prefix(3).contains(where: { $0.word == word }) { top3[variant] += 1 }
                                if case .replace(let candidate) = result.automaticDecision(literalIsValid: result.literalInLexicon), candidate.word != word {
                                    autoWrong[variant] += 1
                                }
                            }
                        }
                        XCTAssertLessThanOrEqual(autoWrong[1], autoWrong[0] + 1, "no more than one extra wrong typo auto per 20 synthetic words; valid-control bound is separately zero")
                        XCTAssertLessThanOrEqual(unavailable[1], 1)
                        // Wide CI-safe nonregression floor; these public fixtures are synthetic,
                        // not untouched held-out human typing or calibrated probabilities.
                        XCTAssertGreaterThanOrEqual(recalled[1], recalled[0] - 2)
                        XCTAssertGreaterThanOrEqual(top3[1], words.count - 2)
                        curves[group, default: []].append("\(taps):\(recalled[0])/\(recalled[1]):\(top3[0])/\(top3[1]):\(autoWrong[0])/\(autoWrong[1]):\(unavailable[0])/\(unavailable[1])")
                    }
                }
                for (group, _) in groups {
                    print("EVAL P7_grip group=\(group) shift=\(shifted ? "away" : "back") rotation=\(rotation) n=20 curve=taps:old/newRecall1:old/newRecall3:old/newWrongTypoAuto:old/newUnavailable \(curves[group]!.joined(separator: ","))")
                }
            }
        }
        timings.sort()
        let mean = timings.reduce(0, +) / Double(timings.count)
        let p95 = timings[Int(Double(timings.count - 1) * 0.95)]
        XCTAssertLessThan(timings.last!, 2000, "generous debug/CI bound, not an iPhone budget")
        print(String(format: "EVAL P7_latency calls=%d meanMs=%.3f p95Ms=%.3f maxMs=%.3f platform=local_debug_not_iPhone", timings.count, mean, p95, timings.last!))
    }

    private final class Checker: TextChecking {
        let valid: Set<String>
        init(_ words: [String]) { valid = Set(words.map { $0.lowercased() }) }
        func isWordValid(_ word: String) -> Bool { valid.contains(word.lowercased()) }
        func guesses(for word: String) -> [String] { [] }
        func completions(for prefix: String) -> [String] { [] }
    }

    func testAdversarialLabelsDoNotOverrideValidLiteralsOrSelfTrain() throws {
        let decoder = try decoder()
        let words = ["hallo", "hello", "haus", "house", "welt", "world", "Anna", "Siempelkamper", "Haustuersteuerung", "GitHub", "Swift", "keyboard", "kind", "gift"]
        let session = KeyboardLearningSession()
        train(session.model, count: 26 * 160, shifted: false, rotation: false)
        // Worst allowed independently supplied labels; silent automatic output still has
        // no API path to these updates. Influence stays bounded even under hostile labels.
        for _ in 0..<100 { session.learn(Array("abcdefghijklmnopqrstuvwxyz").map {
            TouchLabel(point: point($0, x: 0.7, y: 0.7), letter: $0)
        }, layout: grid, source: .manualPick) }
        let ac = AutocorrectEngine(checker: Checker(words), learning: session, spatialDecoder: decoder)
        ac.german = GermanAutocorrect(checker: Checker(words))
        let before = session.model.state
        var changes = 0
        for word in words {
            ac.touchInput.clear() // Keep hostile fast aim active while testing protection.
            var text = ""
            for letter in word {
                let key = grid.key(.character(String(letter).lowercased()))!
                let after = text + String(letter)
                ac.touchInput.append(text: String(letter), point: point(Character(String(letter).lowercased()), x: -0.2, y: 0.1), key: key,
                                     layout: grid, before: text, after: after)
                text = after
            }
            for _ in 0..<3 {
                _ = ac.suggestions(beforeInput: word, field: .text, autocorrectionType: .default)
                if ac.replacementOnSpace(beforeInput: word, field: .text, autocorrectionType: .default) != nil { changes += 1 }
            }
        }
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(session.model.state, before, "scoring and silent boundary decisions never train")
        let keys = try XCTUnwrap(session.calibration(for: grid)?.keys)
        XCTAssertTrue(keys.values.allSatisfy { abs($0.offsetX) <= 0.25 && abs($0.offsetY) <= 0.25 })
        print("EVAL P7_safety validControls=\(words.count) decisions=\(words.count * 3) unwantedAuto=\(changes) adversarialLabels=2600 selfTrainingUpdates=0")
    }
}
