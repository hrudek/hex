import Foundation
import XCTest
@testable import Typr

/// Non-personal, fixed synthetic regression evaluation, NOT measured typing accuracy.
/// Timing is simulator timing when run by the iOS test target, never iPhone proof.
@MainActor
final class SpatialTypoEvaluationTests: XCTestCase {
    private typealias Decoder = SpatialWordDecoder
    private enum ErrorClass: String, CaseIterable {
        case neighbour1, neighbour2, missing, extra, transposition
    }
    private struct SplitMix64 {
        var state: UInt64
        mutating func uniform() -> Double {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            value ^= value >> 31
            return (Double(value >> 11) + 0.5) / 9_007_199_254_740_992
        }
        mutating func normal() -> Double {
            sqrt(-2 * log(uniform())) * cos(2 * Double.pi * uniform())
        }
    }
    private struct Metrics {
        var count = 0
        var recalled = 0
        var correctAuto = 0
        var wrongAuto = 0
        var incomplete = 0
        var unavailable = 0
        var milliseconds: [Double] = []
        var visits: [Double] = []
        var generated: [Double] = []

        private func work(_ values: [Double]) -> String {
            let sorted = values.sorted()
            let mean = values.reduce(0, +) / Double(max(1, values.count))
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            return "\(String(format: "%.1f", mean))/\(Int(p95))/\(Int(values.max() ?? 0))"
        }

        var row: String {
            let sorted = milliseconds.sorted()
            let mean = milliseconds.reduce(0, +) / Double(max(1, count))
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            return "n=\(count) r@3=\(recalled)/\(count) autoOK=\(correctAuto) wrongAuto=\(wrongAuto) incomplete=\(incomplete) unavailable=\(unavailable) meanMs=\(String(format: "%.2f", mean)) p95Ms=\(String(format: "%.2f", p95)) visits(mean/p95/max)=\(work(visits)) generated(mean/p95/max)=\(work(generated))"
        }
    }
    private let grid = KeyboardLayout(width: 393, orientation: .portrait, layer: .letters, field: .text,
                                      showsGlobe: false, showsStrip: true)

    private func neighbour(_ letter: Character) throws -> Character {
        let frame = try XCTUnwrap(grid.key(.character(String(letter)))).frame
        let pitchX = frame.width + grid.metrics.gap
        let pitchY = frame.height + grid.metrics.rowGap
        let candidates = Array("abcdefghijklmnopqrstuvwxyz").filter { $0 != letter }
        let sorted = candidates.sorted { a, b in
            func distance(_ c: Character) -> CGFloat {
                guard let other = grid.key(.character(String(c)))?.frame else { return .infinity }
                let dx = (frame.midX - other.midX) / pitchX
                let dy = (frame.midY - other.midY) / pitchY
                return dx * dx + dy * dy
            }
            let da = distance(a), db = distance(b)
            return da == db ? a < b : da < db
        }
        return try XCTUnwrap(sorted.first)
    }

    private func evidence(_ word: String, error: ErrorClass? = nil, ordinal: Int,
                          seed: UInt64, sigma: Double) throws -> KeyboardTouchWord {
        var typed = Array(word.lowercased())
        var aimed = typed
        let index = ordinal % typed.count
        switch error {
        case .neighbour1, .neighbour2:
            typed[index] = try neighbour(typed[index])
            if error == .neighbour2 {
                let other = (index + max(1, typed.count / 2)) % typed.count
                typed[other] = try neighbour(typed[other])
            }
        case .missing:
            typed.remove(at: index)
            aimed.remove(at: index)
        case .extra:
            let extra = try neighbour(typed[index])
            typed.insert(extra, at: index)
            aimed.insert(extra, at: index)
        case .transposition:
            // Every fixture has a distinct adjacent pair; repeated equal pairs are not errors.
            let pairs = (0..<(typed.count - 1)).filter { typed[$0] != typed[$0 + 1] }
            let position = pairs[ordinal % pairs.count]
            typed.swapAt(position, position + 1)
            aimed.swapAt(position, position + 1)
        case nil: break
        }
        // Each case has a stable local RNG, so variants A and B receive identical samples.
        let classIndex = error.flatMap { ErrorClass.allCases.firstIndex(of: $0) } ?? 5
        var random = SplitMix64(state: seed &+ UInt64(ordinal) &* 97 &+ UInt64(classIndex) &* 1_000_003)
        let samples = try zip(typed, aimed).map { typed, aimed in
            let key = try XCTUnwrap(grid.key(.character(String(typed))))
            let frame = try XCTUnwrap(grid.key(.character(String(aimed)))).frame
            let x = frame.midX + CGFloat(random.normal() * sigma) * (frame.width + grid.metrics.gap)
            let y = frame.midY + CGFloat(random.normal() * sigma) * (frame.height + grid.metrics.rowGap)
            return KeyboardTouchWord.Sample(text: String(typed), point: CGPoint(x: x, y: y), key: key)
        }
        return KeyboardTouchWord(layout: grid, samples: samples)
    }

    private func observe(_ evidence: KeyboardTouchWord, intended: String, decoder: Decoder,
                         edits: Bool, metrics: inout Metrics) {
        let start = ProcessInfo.processInfo.systemUptime
        // Both languages in the same queue, also for the monolingual fixture groups.
        let result = decoder.decode(evidence, languages: [.german, .english], allowsEdits: edits)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        metrics.count += 1
        metrics.milliseconds.append(elapsed)
        guard let result else { metrics.unavailable += 1; return }
        metrics.visits.append(Double(result.visits))
        metrics.generated.append(Double(result.generated))
        if !result.complete { metrics.incomplete += 1 }
        // Display list: exact above-literal candidates, then best-effort edit suggestions.
        if result.suggestions.prefix(3).contains(where: { $0.word == intended.lowercased() }) { metrics.recalled += 1 }
        // Deterministic proxy only: corpus membership, NOT UITextChecker/system validity.
        if case .replace(let candidate) = result.automaticDecision(literalIsValid: result.literalInLexicon) {
            if candidate.word == intended.lowercased() { metrics.correctAuto += 1 } else { metrics.wrongAuto += 1 }
        }
    }

    /// TUNE half: even fixture indices. Structural calibration was selected on this half only.
    func testFixedGermanEnglishEvaluation() throws {
        try evaluate(seed: 0x545950525f503031, sigma: 0.18, half: 0)
    }

    /// HOLDOUT half: odd fixture indices with a different seed and sigma; never used for tuning.
    func testHeldOutNoiseEvaluation() throws {
        try evaluate(seed: 0x545950525f503032, sigma: 0.22, half: 1)
    }

    private func evaluate(seed: UInt64, sigma: Double, half: Int) throws {
        var sources: [Decoder.Language: SpatialWordLexicon] = [:]
        for language in Decoder.Language.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(language.rawValue)",
                                                    withExtension: "words", subdirectory: "WordData"))
            sources[language] = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url)))
        }
        let decoder = Decoder(lexicons: sources)
        let groups: [(Decoder.Language, [String])] = [(.german, SpatialTypoEvaluationFixtures.german),
                                                      (.english, SpatialTypoEvaluationFixtures.english)]
        var lines = ["TYPR-EVAL seed=0x\(String(seed, radix: 16)) sigma=\(sigma) pitch; portrait=393; personal=off; typos=\(half == 0 ? "tune (even" : "holdout (odd") fixture indices); controls=all",
                     "TYPR-EVAL A=static same-length; B=edits; both languages interleaved; validity=corpus membership (not system checker)",
                     "TYPR-EVAL times=simulator timing, not iPhone; controls wrongAuto=unwanted auto replacements"]
        var controls: [String] = []
        var ordinal = 0
        for (language, fixed) in groups {
            let source = try XCTUnwrap(sources[language])
            let words = fixed.filter { source.logPrior(for: $0) != nil }
            let skips = fixed.count - words.count
            lines.append("TYPR-EVAL \(language.rawValue) fixed=\(fixed.count) absentSkips=\(skips)")
            XCTAssertGreaterThanOrEqual(words.count, 120, "fixed common-word coverage")
            controls.append(contentsOf: words)
            var structuralRecalled = 0, structuralCount = 0
            for error in ErrorClass.allCases {
                var a = Metrics(), b = Metrics()
                for (position, word) in words.enumerated() {
                    // Ordinals run over the full list, so each half keeps its words' samples.
                    defer { ordinal += 1 }
                    guard position % 2 == half else { continue }
                    let samples = try evidence(word, error: error, ordinal: ordinal, seed: seed, sigma: sigma)
                    observe(samples, intended: word, decoder: decoder, edits: false, metrics: &a)
                    observe(samples, intended: word, decoder: decoder, edits: true, metrics: &b)
                }
                lines.append("TYPR-EVAL \(language.rawValue) \(error.rawValue) A \(a.row)")
                lines.append("TYPR-EVAL \(language.rawValue) \(error.rawValue) B \(b.row)")
                XCTAssertEqual(a.wrongAuto, 0, "same-length wrong auto: \(language.rawValue) \(error.rawValue)")
                XCTAssertEqual(b.wrongAuto, 0, "edit-aware wrong auto: \(language.rawValue) \(error.rawValue)")
                if [.missing, .extra, .transposition].contains(error) {
                    structuralRecalled += b.recalled
                    structuralCount += b.count
                    // Linux display-only retrieval: 53-100% per class/half; floor keeps a wide margin.
                    XCTAssertGreaterThanOrEqual(Double(b.recalled) / Double(max(1, b.count)), 0.40,
                                                "structural recall@3 floor: \(language.rawValue) \(error.rawValue)")
                } else {
                    XCTAssertGreaterThanOrEqual(Double(b.recalled) / Double(max(1, b.count)), 0.95,
                                                "neighbour recall@3 floor: \(language.rawValue) \(error.rawValue)")
                }
            }
            // Centred structural typos rarely beat the literal under log(.01) and the 0.35
            // prior weight, so recall comes from the best-effort below-literal edit
            // suggestions (absent literals only). Measured Linux pooled recall: 82-90%
            // per language and half with display-only retrieval, versus 2-5% above-literal only.
            // This is a regression floor, not an accuracy claim; structural auto stays ~0 by design.
            XCTAssertGreaterThanOrEqual(Double(structuralRecalled) / Double(max(1, structuralCount)), 0.70,
                                        "pooled structural recall@3 floor: \(language.rawValue)")
        }
        controls += SpatialTypoEvaluationFixtures.germanNouns.map { $0.lowercased() }
        controls += SpatialTypoEvaluationFixtures.short
        controls += SpatialTypoEvaluationFixtures.novel
        // Appended after the original controls, so their ordinals and samples are unchanged.
        controls += SpatialTypoEvaluationFixtures.absent
        controls += SpatialTypoEvaluationFixtures.rare
        let outside = (SpatialTypoEvaluationFixtures.novel + SpatialTypoEvaluationFixtures.absent).filter { word in
            sources.values.allSatisfy { $0.logPrior(for: word.lowercased()) == nil }
        }
        let rare = SpatialTypoEvaluationFixtures.rare.filter { word in
            sources.values.contains { $0.logPrior(for: word) != nil }
        }
        XCTAssertGreaterThanOrEqual(outside.count, 200, "at least 200 genuinely out-of-lexicon controls")
        XCTAssertGreaterThanOrEqual(rare.count, 100, "at least 100 rare in-lexicon controls")
        lines.append("TYPR-EVAL controls=\(controls.count) outside=\(outside.count) rarePresent=\(rare.count); nouns typed lowercase; mixed EN/DE; short words; names/technical/product/abbreviation/compound/unusual-spelling strings")
        XCTAssertGreaterThanOrEqual(controls.count, 600)
        for edits in [false, true] {
            var known = Metrics(), unknown = Metrics()
            for (index, word) in controls.enumerated() {
                let sample = try evidence(word, ordinal: 50_000 + index, seed: seed, sigma: sigma)
                let inLexicon = sources.values.contains { $0.logPrior(for: word.lowercased()) != nil }
                if inLexicon { observe(sample, intended: word, decoder: decoder, edits: edits, metrics: &known) }
                else { observe(sample, intended: word, decoder: decoder, edits: edits, metrics: &unknown) }
            }
            let variant = edits ? "B" : "A"
            lines.append("TYPR-EVAL controls inLexicon \(variant) \(known.row)")
            lines.append("TYPR-EVAL controls outside \(variant) \(unknown.row)")
            XCTAssertEqual(known.wrongAuto, 0, "no unwanted auto replacements on in-lexicon controls")
            XCTAssertEqual(unknown.wrongAuto, 0, "no unwanted auto replacements on out-of-lexicon controls")
            let failed = known.incomplete + unknown.incomplete + known.unavailable + unknown.unavailable
            XCTAssertLessThanOrEqual(Double(failed) / Double(controls.count), 0.05, "control evidence/search availability")
        }
        // Per-keystroke-like calls on every prefix of the 256 fixed DE/EN words.
        // Full-word evidence uses the same generator; no edits or private input.
        for edits in [false, true] {
            var prefixes = Metrics()
            for (index, word) in controls.prefix(256).enumerated() {
                let full = try evidence(word, ordinal: 90_000 + index, seed: seed, sigma: sigma)
                for length in 3...full.samples.count {
                    let prefix = KeyboardTouchWord(layout: grid, samples: Array(full.samples.prefix(length)))
                    observe(prefix, intended: String(word.prefix(length)), decoder: decoder,
                            edits: edits, metrics: &prefixes)
                }
            }
            lines.append("TYPR-EVAL prefixes \(edits ? "B" : "A") \(prefixes.row)")
        }
        let table = lines.joined(separator: "\n")
        print(table)
        let attachment = XCTAttachment(string: table)
        attachment.name = "Typr fixed DE-EN spatial evaluation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
