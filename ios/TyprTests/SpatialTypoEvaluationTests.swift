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

        var row: String {
            let sorted = milliseconds.sorted()
            let mean = milliseconds.reduce(0, +) / Double(max(1, count))
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            return "n=\(count) r@3=\(recalled)/\(count) autoOK=\(correctAuto) wrongAuto=\(wrongAuto) incomplete=\(incomplete) unavailable=\(unavailable) meanMs=\(String(format: "%.2f", mean)) p95Ms=\(String(format: "%.2f", p95))"
        }
    }
    private let seed: UInt64 = 0x545950525f503031 // "TYPR_P01", fixed, not system randomness.
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

    private func evidence(_ word: String, error: ErrorClass? = nil, ordinal: Int) throws -> KeyboardTouchWord {
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
            let x = frame.midX + CGFloat(random.normal() * 0.18) * (frame.width + grid.metrics.gap)
            let y = frame.midY + CGFloat(random.normal() * 0.18) * (frame.height + grid.metrics.rowGap)
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
        if !result.complete { metrics.incomplete += 1 }
        if result.candidates.prefix(3).contains(where: { $0.word == intended.lowercased() }) { metrics.recalled += 1 }
        // Deterministic proxy only: corpus membership, NOT UITextChecker/system validity.
        if case .replace(let candidate) = result.automaticDecision(literalIsValid: result.literalInLexicon) {
            if candidate.word == intended.lowercased() { metrics.correctAuto += 1 } else { metrics.wrongAuto += 1 }
        }
    }

    func testFixedGermanEnglishEvaluation() throws {
        var sources: [Decoder.Language: SpatialWordLexicon] = [:]
        for language in Decoder.Language.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "keyboard-\(language.rawValue)",
                                                    withExtension: "words", subdirectory: "WordData"))
            sources[language] = try XCTUnwrap(SpatialWordLexicon(data: Data(contentsOf: url)))
        }
        let decoder = Decoder(lexicons: sources)
        let groups: [(Decoder.Language, [String])] = [(.german, SpatialTypoEvaluationFixtures.german),
                                                      (.english, SpatialTypoEvaluationFixtures.english)]
        var lines = ["TYPR-EVAL seed=0x545950525f503031 sigma=0.18 pitch; portrait=393; personal=off",
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
            for error in ErrorClass.allCases {
                var a = Metrics(), b = Metrics()
                for word in words {
                    let samples = try evidence(word, error: error, ordinal: ordinal)
                    ordinal += 1
                    observe(samples, intended: word, decoder: decoder, edits: false, metrics: &a)
                    observe(samples, intended: word, decoder: decoder, edits: true, metrics: &b)
                }
                lines.append("TYPR-EVAL \(language.rawValue) \(error.rawValue) A \(a.row)")
                lines.append("TYPR-EVAL \(language.rawValue) \(error.rawValue) B \(b.row)")
                if [.missing, .extra, .transposition].contains(error) {
                    XCTAssertGreaterThanOrEqual(Double(b.recalled) / Double(max(1, b.count)), 0.5,
                                                "edit recall@3 floor: \(language.rawValue) \(error.rawValue)")
                }
            }
        }
        controls += SpatialTypoEvaluationFixtures.germanNouns.map { $0.lowercased() }
        controls += SpatialTypoEvaluationFixtures.short
        controls += SpatialTypoEvaluationFixtures.novel
        let outside = SpatialTypoEvaluationFixtures.novel.filter { word in
            sources.values.allSatisfy { $0.logPrior(for: word.lowercased()) == nil }
        }
        XCTAssertGreaterThanOrEqual(outside.count, 30, "at least 30 genuinely out-of-lexicon controls")
        lines.append("TYPR-EVAL controls=\(controls.count) novelOutside=\(outside.count); nouns typed lowercase; mixed EN/DE; short words; invented names/technical/acronym-like strings")
        XCTAssertGreaterThanOrEqual(controls.count, 150)
        for edits in [false, true] {
            var known = Metrics(), unknown = Metrics()
            for (index, word) in controls.enumerated() {
                let sample = try evidence(word, ordinal: 50_000 + index)
                let inLexicon = sources.values.contains { $0.logPrior(for: word.lowercased()) != nil }
                if inLexicon { observe(sample, intended: word, decoder: decoder, edits: edits, metrics: &known) }
                else { observe(sample, intended: word, decoder: decoder, edits: edits, metrics: &unknown) }
            }
            let variant = edits ? "B" : "A"
            lines.append("TYPR-EVAL controls inLexicon \(variant) \(known.row)")
            lines.append("TYPR-EVAL controls outside \(variant) \(unknown.row)")
            XCTAssertEqual(known.wrongAuto, 0, "no unwanted auto replacements on in-lexicon controls")
            let failed = known.incomplete + unknown.incomplete + known.unavailable + unknown.unavailable
            XCTAssertLessThanOrEqual(Double(failed) / Double(controls.count), 0.05, "control evidence/search availability")
        }
        let table = lines.joined(separator: "\n")
        print(table)
        let attachment = XCTAttachment(string: table)
        attachment.name = "Typr fixed DE-EN spatial evaluation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
