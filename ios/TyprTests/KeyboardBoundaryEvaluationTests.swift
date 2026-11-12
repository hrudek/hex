import Foundation
import XCTest
@testable import Typr

extension KeyboardBoundaryDecoderTests {
    // Typr-authored public phrase fixtures, not upstream test data or collected text.
    private static let dePhrases = [
        "ich habe", "das ist", "kannst du", "es ist", "in der", "in die", "am ende", "zu dir",
        "du bist", "ich bin", "wir sind", "er hat", "sie hat", "ist das", "hast du", "ich will",
        "und ich", "mit dem", "auf die", "auf dem", "im haus", "so ist", "es war", "zu mir"
    ]
    private static let enPhrases = [
        "great day", "this is", "in the", "I am", "a day", "you are", "we are", "it is",
        "is the", "of the", "to the", "at home", "my friend", "can you", "do you", "for the",
        "and the", "on the", "I have", "he is", "as if", "by the", "go to", "with you"
    ]
    private static let mixedPhrases = [
        "ich have", "das is", "great tag", "in die", "am ende", "my haus", "du are", "wir have",
        "you bist", "the haus", "und the", "mit you", "mein friend", "guten day", "ein day", "a haus"
    ]

    private func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
    private func fmt(_ value: Double) -> String { String(format: "%.4f", value) }
    private func p95(_ values: [Double]) -> Double { values.sorted()[Int(Double(values.count - 1) * 0.95)] }

    func testEvaluationNoisyOmittedSpacesAgainstNoBoundaryBaseline() async throws {
        let sources = try resources()
        let modes: [(String, Set<Language>, [String])] = [
            ("DE", [.german], Self.dePhrases), ("EN", [.english], Self.enPhrases),
            ("mixed", [.german, .english], Self.mixedPhrases)
        ]
        for (name, languages, phrases) in modes {
            let ac = engine(sources, languages: languages)
            let worker = KeyboardSuggestionWorker()
            var n = 0, recall1 = 0, recall3 = 0, strip1 = 0, strip3 = 0, baseline3 = 0
            var autoSplits = 0, autoCorrect = 0, autoWrong = 0, wholeCorpus = 0, maxQueries = 0
            var times: [Double] = []
            for (ordinal, phrase) in phrases.enumerated() {
                let typed = phrase.replacingOccurrences(of: " ", with: "").lowercased()
                for seed: UInt64 in [0x50355f54554e45, 0x50355f484f4c44] {
                    let evidence = try SpatialTypoEvaluationEvidence.evidence(
                        typed, grid: grid, ordinal: ordinal, seed: seed, sigma: 0.18)
                    ac.discardEvidence()
                    var before = ""
                    for sample in evidence.samples {
                        let after = before + sample.text
                        ac.touchInput.append(text: sample.text, point: sample.point, key: sample.key,
                                             layout: grid, before: before, after: after)
                        before = after
                    }
                    let ownership = KeyboardSuggestionOwnership(
                        engine: UUID(), revision: 1, context: typed, token: typed, field: .text,
                        permitsCorrection: true, configuration: ac.suggestionConfiguration,
                        learning: ac.learning.generation, feedbackEpoch: ac.learning.feedbackEpoch,
                        resources: ac.spatialDecoder?.resourceRevision ?? -1, layout: grid)
                    let request = ac.suggestionRequest(ownership: ownership, evidence: evidence)
                    let job = try XCTUnwrap(request.boundary)
                    var completed: KeyboardSuggestionWorker.Result?
                    worker.submit(prepare: { request }, finish: { completed = $0 })
                    await worker.waitUntilIdle()
                    let result = try XCTUnwrap(completed)
                    let retrieval = try XCTUnwrap(result.boundary)
                    let start = ContinuousClock.now
                    let direct = Boundary.retrieve(job, lexicons: sources, whole: result.outcome)
                    times.append(ms(start.duration(to: .now)))
                    XCTAssertEqual(direct.candidates, retrieval.candidates, "Worker and synchronous retrieval")
                    maxQueries = max(maxQueries, retrieval.lexicalQueries)
                    let expected = phrase.lowercased()
                    let words = retrieval.candidates.map { $0.replacement.lowercased() }
                    n += 1
                    if words.first == expected { recall1 += 1 }
                    if words.prefix(3).contains(expected) { recall3 += 1 }
                    if languages.contains(where: { sources[$0]?.logPrior(for: typed) != nil }) { wholeCorpus += 1 }
                    // Keep corpus-validity outcomes separate: the deterministic checker regards
                    // ANY corpus entry as valid, even noisy source entries such as "inthe"/"iam".
                    let empty = Boundary.Retrieval(job: job, candidates: [], lexicalQueries: 0)
                    let baseline = ac.suggestions(beforeInput: typed, field: .text, autocorrectionType: .default,
                                                   boundaryRetrieval: empty).map { $0.replacement.lowercased() }
                    let strip = ac.finishSuggestions(result)
                    let alternatives = strip.filter { $0.kind != .keepLiteral }.map { $0.replacement.lowercased() }
                    if alternatives.first == expected { strip1 += 1 }
                    if alternatives.prefix(3).contains(expected) { strip3 += 1 }
                    if baseline.prefix(3).contains(expected) { baseline3 += 1 }
                    autoSplits += strip.filter { $0.boundary != nil && $0.willAutoReplace }.count
                    let automatic = ac.replacementOnSpace(beforeInput: typed, field: .text, autocorrectionType: .default)
                    if let replacement = automatic?.replacement, replacement.contains(" ") {
                        if replacement.lowercased() == expected { autoCorrect += 1 } else { autoWrong += 1 }
                    }
                }
            }
            XCTAssertGreaterThanOrEqual(Double(recall3) / Double(n), 0.70, name)
            XCTAssertGreaterThan(strip3, baseline3)
            XCTAssertEqual(autoSplits, 0)
            XCTAssertEqual(autoCorrect + autoWrong, 0)
            XCTAssertLessThanOrEqual(maxQueries, Boundary.maximumLexicalQueries)
            XCTAssertLessThan(times.reduce(0, +) / Double(n), 25, "Generous Linux debug budget, not iPhone")
            XCTAssertLessThan(times.max() ?? 0, 250)
            print("EVAL P5_omitted language=\(name) n=\(n) recall1=\(recall1) recall3=\(recall3) strip1=\(strip1) strip3=\(strip3) baseline_strip3=\(baseline3) corpus_whole=\(wholeCorpus) auto_correct=\(autoCorrect) auto_wrong=\(autoWrong) auto_recall=0 auto_precision=NA_suggestion_only queries_max=\(maxQueries) mean_ms=\(fmt(times.reduce(0,+)/Double(n))) p95_ms=\(fmt(p95(times))) max_ms=\(fmt(times.max() ?? 0)) validity=corpus_proxy NOT-iPhone")
        }
    }

    func testEvaluationValidCompoundsNamesIdentifiersAndCodeSwitchesHaveZeroFalseAutos() throws {
        let sources = try resources()
        let compounds = ["Haustür", "Kindergarten", "Bahnhof", "Fahrrad", "Haustürschlüssel", "Kindergartenplatz",
                         "Tastaturbelegung", "keyboard", "something", "somewhere", "doorframe", "rainjacket"]
        let identifiers = (0..<80).flatMap { ["greatday_\($0)", "ichhabe\($0)", "myValue\($0)"] }
        let controls = SpatialTypoEvaluationFixtures.absent + SpatialTypoEvaluationFixtures.novel + compounds + identifiers
        XCTAssertGreaterThanOrEqual(Set(controls).count, 300)
        let ac = engine(sources, trusted: Set(controls.map { $0.lowercased() }))
        var unwanted = 0, boundaryAuto = 0, splitChips = 0
        for (index, token) in controls.enumerated() {
            let context = (index % 2 == 0 ? "the " : "die ") + token
            let suggestions = strip(ac, context)
            splitChips += suggestions.filter { $0.boundary?.kind == .split }.count
            boundaryAuto += suggestions.filter { $0.boundary != nil && $0.willAutoReplace }.count
            if ac.replacementOnSpace(beforeInput: context, field: .text, autocorrectionType: .default) != nil { unwanted += 1 }
        }
        XCTAssertEqual(unwanted, 0)
        XCTAssertEqual(boundaryAuto, 0)
        XCTAssertEqual(splitChips, 0, "The checker accepts these synthetic valid literals")
        // OOV productive compounds cannot be reliably distinguished from omitted spaces.
        // Report those tempting suggestions separately, never pretend they are automatic precision.
        let unknown = engine(sources)
        var oovSplitSuggestions = 0
        for token in SpatialTypoEvaluationFixtures.absent {
            oovSplitSuggestions += strip(unknown, token).filter { $0.boundary?.kind == .split }.count
        }
        print("EVAL P5_controls n=\(controls.count) unique=\(Set(controls).count) unwanted=\(unwanted) boundary_auto=\(boundaryAuto) valid_split_chips=\(splitChips) oov_controls=\(SpatialTypoEvaluationFixtures.absent.count) oov_split_chips=\(oovSplitSuggestions) false_auto_bound=0 validity=synthetic_valid_checker NOT-iPhone")
    }

    func testEvaluationExactJoinsAndPlausiblePairAbstention() throws {
        let sources = try resources()
        let ac = engine(sources)
        let fixtures = [("Tasta tur", "tastatur"), ("Tast atur", "tastatur"), ("Tastat ur", "tastatur"),
                        ("keyb oard", "keyboard"), ("keybo ard", "keyboard"), ("keyboa rd", "keyboard")]
        var recall1 = 0, recall3 = 0, strip3 = 0, auto = 0
        var times: [Double] = []
        for (text, expected) in fixtures {
            let parts = text.split(separator: " ").map(String.init)
            let start = ContinuousClock.now
            let result = Boundary.retrieve(job(parts[1], previous: parts[0]), lexicons: sources)
            times.append(ms(start.duration(to: .now)))
            if result.candidates.first?.replacement == expected { recall1 += 1 }
            if result.candidates.prefix(3).contains(where: { $0.replacement == expected }) { recall3 += 1 }
            let chips = strip(ac, text)
            if chips.contains(where: { $0.replacement.lowercased() == expected }) { strip3 += 1 }
            auto += chips.filter { $0.boundary?.kind == .join && $0.willAutoReplace }.count
        }
        let pairs = ["some thing", "in side", "a bout", "an other", "key board", "the best", "ich habe",
                     "das ist", "in the", "am ende", "my haus", "und the"]
        let wrong = pairs.filter { text in strip(ac, text).contains { $0.boundary?.kind == .join } }.count
        XCTAssertGreaterThanOrEqual(recall3, 4)
        XCTAssertGreaterThanOrEqual(strip3, 4)
        XCTAssertEqual(auto, 0)
        XCTAssertEqual(wrong, 0)
        print("EVAL P5_join n=\(fixtures.count) recall1=\(recall1) recall3=\(recall3) strip3=\(strip3) auto=\(auto) plausible_pairs=\(pairs.count) unwanted_join_chips=\(wrong) mean_ms=\(fmt(times.reduce(0,+)/Double(times.count))) max_ms=\(fmt(times.max() ?? 0)) policy=exact_suggestion_only NOT-iPhone")
    }

    func testEvaluationBoundsAtMaximumPersonalCapacityAndAdversarialLengths() throws {
        let sources = try resources()
        var counts: [String: Int] = [:]
        for index in 0..<2_000 {
            var value = index
            var suffix = ""
            for _ in 0..<3 { suffix.append(Character(UnicodeScalar(97 + value % 26)!)); value /= 26 }
            counts["velq" + suffix] = 2
        }
        let personal = PersonalLexiconSnapshot(kept: [], counts: counts, rejected: [])
        var times: [Double] = []
        var maxQueries = 0
        for length in 1...64 {
            for token in [String(repeating: "a", count: length), String(repeating: "i", count: length)] {
                let start = ContinuousClock.now
                let result = Boundary.retrieve(job(token, previous: "the", personal: personal), lexicons: sources)
                times.append(ms(start.duration(to: .now)))
                maxQueries = max(maxQueries, result.lexicalQueries)
                XCTAssertLessThanOrEqual(result.candidates.count, Boundary.resultLimit)
                XCTAssertLessThanOrEqual(result.lexicalQueries, Boundary.maximumLexicalQueries)
                XCTAssertEqual(result.candidates, Boundary.retrieve(result.job, lexicons: sources).candidates)
            }
        }
        let pairBytes = AutocorrectEngine.boundaryRejectionLimit * (MemoryLayout<RejectedCorrection>.stride + 130)
        XCTAssertLessThan(Boundary.shortWordPayloadBytes, 1_024)
        XCTAssertLessThan(Boundary.maximumCandidatePayloadBytes, 2_048)
        XCTAssertLessThan(pairBytes, 16_384)
        XCTAssertLessThan(times.max() ?? 0, 250)
        print("EVAL P5_bounds calls=\(times.count) personal_words=\(personal.scan.entries.count) queries_max=\(maxQueries) query_cap=\(Boundary.maximumLexicalQueries) trie_edge_cap=\(Boundary.maximumTrieEdgeChecks) candidate_payload_bytes=\(Boundary.maximumCandidatePayloadBytes) short_word_payload_bytes=\(Boundary.shortWordPayloadBytes) letter_array_payload_bytes=\(Boundary.maxLetters * MemoryLayout<Character>.stride) session_pair_payload_bytes=\(pairBytes) mean_ms=\(fmt(times.reduce(0,+)/Double(times.count))) p95_ms=\(fmt(p95(times))) max_ms=\(fmt(times.max() ?? 0)) memory=element_payload_NOT_RSS NOT-iPhone")
    }
}
