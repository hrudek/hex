import Foundation
import CoreGraphics

/// Static, bundled word counts. The TSW1 format is Typr's own, not iikb's ASCII HXL1 format.
/// See WordData/README.md and THIRD_PARTY_NOTICES.md for the separately licensed word data.
nonisolated struct SpatialWordLexicon: Sendable {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyzäöüß")
    static let maxBytes = 5_000_000
    let data: Data
    let nodeCount: Int
    let total: Double
    private var subtreeCounts: [UInt32] = []

    init?(data: Data) {
        guard data.count >= 36, data.count <= Self.maxBytes,
              Array(data.prefix(4)) == Array("TSW1".utf8) else { return nil }
        self.data = data
        let nodes = Int(Self.uint32(data, 4))
        let words = Int(Self.uint32(data, 8))
        let total = Double(Self.uint32(data, 16)) + Double(Self.uint32(data, 20)) * 4_294_967_296
        guard nodes > 0, nodes <= 400_000, data.count == 24 + nodes * 12,
              words > 0, words <= 50_000, total >= Double(words), total <= 1_000_000_000_000,
              Self.uint32(data, 12) == 0 else { return nil }
        self.nodeCount = nodes
        self.total = total
        guard node(0)?.label == 255 else { return nil }
        // TSW1 stores terminal counts, not subtree masses. Derive a max-count index
        // once, in reverse (edges are forward-only). Also establish the unique
        // spelling per node required by max-path state dominance below.
        subtreeCounts = [UInt32](repeating: 0, count: nodes)
        var parents = [Bool](repeating: false, count: nodes)
        for index in (0..<nodes).reversed() {
            guard let record = node(index) else { return nil }
            var maximum = UInt32(record.count)
            var labels: UInt32 = 0
            for child in record.children {
                // Forward children were already validated in this reverse pass.
                let label = Int(data[data.startIndex + 24 + child * 12])
                let bit = UInt32(1) << label
                guard !parents[child], labels & bit == 0 else { return nil }
                labels |= bit
                parents[child] = true
                maximum = max(maximum, subtreeCounts[child])
            }
            subtreeCounts[index] = maximum
        }
        guard parents.dropFirst().allSatisfy({ $0 }) else { return nil }
    }

    /// Upper bound on the terminal prior of any descendant (including this node).
    func bestLogPrior(at index: Int) -> Double {
        log(Double(subtreeCounts[index]) / total)
    }

    struct Node {
        let label: Int
        let children: Range<Int>
        let count: Double
    }

    /// Bounds-check every visited record, including forward-only edges. No unsafe pointer loads.
    func node(_ index: Int) -> Node? {
        guard index >= 0, index < nodeCount else { return nil }
        let offset = 24 + index * 12
        let label = Int(data[data.startIndex + offset])
        let children = Int(data[data.startIndex + offset + 1])
        let first = Int(Self.uint32(data, offset + 4))
        let count = Double(Self.uint32(data, offset + 8))
        guard (index == 0 ? label == 255 : label < Self.alphabet.count),
              children <= Self.alphabet.count, count <= total,
              data[data.startIndex + offset + 2] == 0, data[data.startIndex + offset + 3] == 0,
              children == 0 ? first == 0 : (first > index && first + children <= nodeCount) else { return nil }
        return Node(label: label, children: first..<(first + children), count: count)
    }

    func logPrior(for word: String) -> Double? {
        var index = 0
        for letter in word {
            guard let label = Self.alphabet.firstIndex(of: letter), let parent = node(index) else { return nil }
            var next: Int?
            for child in parent.children {
                guard let item = node(child) else { return nil }
                if item.label == label { next = child; break }
            }
            guard let next else { return nil }
            index = next
        }
        guard let count = node(index)?.count, count > 0 else { return nil }
        return log(count / total)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + offset + $1]) << ($1 * 8) }
    }
}

/// Frozen geometry and weak word priors. Max-path scoring, not alignment marginalisation.
// Best-first trie/edit/trail ideas adapted from AVGVSTVS96/iikb
// Packages/KeyboardModules/Sources/KeyboardCore/Correction/Decoder.swift (MIT),
// revision 08df5aa1e698d8587b6dcaef53f5e555ba1fac2a. TSW1 and policy are Typr's.
@MainActor
final class SpatialWordDecoder {
    nonisolated enum Language: String, CaseIterable, Sendable { case german = "de", english = "en" }
    nonisolated enum Edit: Equatable, Sendable {
        case none, missingLetter(at: Int), extraTap(at: Int), transposition(at: Int)
    }
    nonisolated struct Candidate: Equatable, Sendable {
        let word: String
        let language: Language?
        let score: Double
        let spatialScore: Double
        let edit: Edit
        /// Candidate letter -> observed tap; missing letters have no tap.
        let alignment: [Int?]
    }
    nonisolated enum Refusal: String, CaseIterable, Sendable {
        case incompleteSearch, noCandidate, belowMargin, ambiguous, editNeedsInvalidLiteral
    }
    nonisolated enum AutoDecision: Sendable { case replace(Candidate), refuse(Refusal) }
    nonisolated enum Unavailable: Equatable, Sendable { case evidence, resource }
    nonisolated enum Outcome: Equatable, Sendable { case result(Result), unavailable(Unavailable) }
    nonisolated struct Result: Equatable, Sendable {
        let candidates: [Candidate]
        let literalScore: Double
        let literalSpatialScore: Double
        let literalInLexicon: Bool
        let complete: Bool
        let visits: Int
        let generated: Int
        /// Suggestion-only structural alternatives scored BELOW the literal (at most
        /// `editSuggestionLimit`, within one edit penalty of it), retrieved only when the
        /// literal is absent from every selected corpus. Best effort from the remaining
        /// budget: NOT covered by `complete`, never part of `candidates`, and never used
        /// by `automaticDecision` or `geometryPrefersAlternative`.
        var editSuggestions: [Candidate] = []

        /// Display order: exact above-literal candidates, then best-effort edit suggestions.
        var suggestions: [Candidate] { candidates + editSuggestions }

        var geometryPrefersAlternative: Bool {
            candidates.contains { candidate in
                switch candidate.edit {
                case .none, .transposition: candidate.spatialScore >= literalSpatialScore
                case .missingLetter, .extraTap: false
                }
            }
        }

        /// Dictionary/casing, keeps, rejected pairs and field guards remain the caller's job.
        func automaticDecision(literalIsValid: Bool) -> AutoDecision {
            guard complete else { return .refuse(.incompleteSearch) }
            guard let best = candidates.first else { return .refuse(.noCandidate) }
            if best.edit != .none && literalIsValid { return .refuse(.editNeedsInvalidLiteral) }
            guard best.score - literalScore >= 3,
                  best.edit != .none || best.spatialScore - literalSpatialScore >= 2 else {
                return .refuse(.belowMargin)
            }
            guard candidates.count < 2 || best.score - candidates[1].score >= 1.6 else {
                return .refuse(.ambiguous)
            }
            return .replace(best)
        }
    }

    static let bundled = SpatialWordDecoder(bundle: .main)
    nonisolated static let searchBudget = 6_000
    nonisolated static let maxGenerated = 12_000
    nonisolated static let maxLetters = 32
    nonisolated static let editSuggestionLimit = 2
    private var lexicons: [Language: SpatialWordLexicon]
    private let bundle: Bundle?
    private var loadTask: Task<Void, Never>?
    private var ranking: SpatialWordRanking
    private(set) var isResourceLoading = false

    init(lexicons: [Language: SpatialWordLexicon]) {
        self.lexicons = lexicons
        self.ranking = SpatialWordRanking(lexicons: lexicons)
        self.bundle = nil
    }

    init(bundle: Bundle) {
        self.bundle = bundle
        self.lexicons = [:]
        self.ranking = SpatialWordRanking(lexicons: [:])
        isResourceLoading = true
    }

    /// Start at keyboard appearance, never on the first typing/decode path. Mapping,
    /// validation and subtree-index construction all happen off the main actor.
    func prepareResources() {
        guard isResourceLoading, loadTask == nil, let bundle else { return }
        let urls = Language.allCases.compactMap { language -> (Language, URL)? in
            bundle.url(forResource: "keyboard-\(language.rawValue)", withExtension: "words",
                       subdirectory: "WordData").map { (language, $0) }
        }
        loadTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                var lexicons: [Language: SpatialWordLexicon] = [:]
                for (language, url) in urls {
                    if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                       let lexicon = SpatialWordLexicon(data: data) { lexicons[language] = lexicon }
                }
                return lexicons
            }.value
            guard let self else { return }
            self.lexicons = loaded
            self.ranking = SpatialWordRanking(lexicons: loaded)
            self.resourceRevision &+= 1
            self.isResourceLoading = false
            self.loadTask = nil
        }
    }

    /// Immutable resources are shared copy-on-write, never the mutable ranking memos.
    var resourceSnapshot: [Language: SpatialWordLexicon] { lexicons }
    private(set) var resourceRevision = 0

    func decode(_ word: KeyboardTouchWord, languages: Set<Language>,
                budget: Int = SpatialWordDecoder.searchBudget,
                calibration: SpatialTouchCalibration? = nil,
                personal: PersonalLexiconSnapshot = .empty, allowsEdits: Bool = true) -> Result? {
        ranking.decode(word, languages: languages, budget: budget, calibration: calibration,
                       personal: personal, allowsEdits: allowsEdits)
    }

    func decodeDetailed(_ word: KeyboardTouchWord, languages: Set<Language>,
                        budget: Int = SpatialWordDecoder.searchBudget,
                        calibration: SpatialTouchCalibration? = nil,
                        personal: PersonalLexiconSnapshot = .empty, allowsEdits: Bool = true) -> Outcome {
        ranking.decodeDetailed(word, languages: languages, budget: budget, calibration: calibration,
                               personal: personal, allowsEdits: allowsEdits)
    }

    nonisolated static func align(word: String, taps: [Character]) -> [Int?]? {
        SpatialWordRanking.align(word: word, taps: taps)
    }
}
