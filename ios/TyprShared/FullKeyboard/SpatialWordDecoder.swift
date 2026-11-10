import Foundation
import CoreGraphics

/// Static, bundled word counts. The TSW1 format is Typr's own, not iikb's ASCII HXL1 format.
/// See WordData/README.md and THIRD_PARTY_NOTICES.md for the separately licensed word data.
nonisolated struct SpatialWordLexicon {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyzäöüß")
    static let maxBytes = 5_000_000
    let data: Data
    let nodeCount: Int
    let total: Double

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

/// Geometry + a weak unigram prior, with no learned offsets, context, state updates or word cache.
/// The bounded trie-search idea is adapted from AVGVSTVS96/iikb's Decoder/Lexicon (MIT),
/// revision 9c74e51f0218a814e2e99756087d3f38ef003614; the fixed model and format are Typr's.
@MainActor
final class SpatialWordDecoder {
    enum Language: String, CaseIterable { case german = "de", english = "en" }
    struct Candidate {
        let word: String
        let language: Language
        let score: Double
        let spatialScore: Double
    }
    struct Result {
        let candidates: [Candidate]
        let literalScore: Double
        let literalSpatialScore: Double

        var confident: Candidate? {
            guard let best = candidates.first,
                  best.score - literalScore >= 3.0,
                  best.spatialScore - literalSpatialScore >= 2.0,
                  candidates.count < 2 || best.score - candidates[1].score >= 1.6 else { return nil }
            return best
        }
    }

    static let bundled = SpatialWordDecoder(bundle: .main)
    static let searchBudget = 6_000
    static let maxLetters = 32
    private static let priorWeight = 0.35
    private var lexicons: [Language: SpatialWordLexicon]
    private var attempted: Set<Language> = []
    private let bundle: Bundle?

    init(lexicons: [Language: SpatialWordLexicon]) {
        self.lexicons = lexicons
        self.bundle = nil
    }

    private init(bundle: Bundle) {
        self.bundle = bundle
        self.lexicons = [:]
    }

    private func lexicon(_ language: Language) -> SpatialWordLexicon? {
        if let existing = lexicons[language] { return existing }
        guard let bundle, attempted.insert(language).inserted,
              let url = bundle.url(forResource: "keyboard-\(language.rawValue)", withExtension: "words", subdirectory: "WordData"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let loaded = SpatialWordLexicon(data: data) else { return nil }
        lexicons[language] = loaded
        return loaded
    }

    func decode(_ word: KeyboardTouchWord, languages: Set<Language>,
                budget: Int = SpatialWordDecoder.searchBudget) -> Result? {
        let literal = word.text.lowercased()
        guard (3...Self.maxLetters).contains(word.samples.count), literal.count == word.samples.count,
              word.layout.layer == .letters, word.layout.field == .text, !languages.isEmpty else { return nil }
        // Do not partially decode a bilingual request if one resource is missing/corrupt.
        var sources: [(Language, SpatialWordLexicon)] = []
        for language in Language.allCases where languages.contains(language) {
            guard let lexicon = lexicon(language) else { return nil }
            sources.append((language, lexicon))
        }
        let alphabet = SpatialWordLexicon.alphabet
        var frames: [Int: CGRect] = [:]
        for (index, letter) in alphabet.enumerated() {
            if let key = word.layout.key(.character(String(letter))) { frames[index] = key.frame }
        }
        var likelihoods: [[Double]] = []
        var literalSpatial = 0.0
        for sample in word.samples {
            guard sample.text.count == 1, sample.text.lowercased().count == 1,
                  sample.key == word.layout.key(sample.key.kind),
                  sample.point.x.isFinite, sample.point.y.isFinite,
                  let letter = sample.text.lowercased().first,
                  let label = alphabet.firstIndex(of: letter),
                  let observedFrame = frames[label], observedFrame.width > 0, observedFrame.height > 0 else { return nil }
            var scores = [Double](repeating: -.infinity, count: alphabet.count)
            for (index, frame) in frames {
                // Use a key pitch, not the tiled edge hit target (which can be unusually wide).
                let width = Double(frame.width + word.layout.metrics.gap)
                let height = Double(frame.height + word.layout.metrics.rowGap)
                guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
                let dx = Double(sample.point.x - frame.midX) / width
                let dy = Double(sample.point.y - frame.midY) / height
                let distance = dx * dx + dy * dy
                if distance <= 1.6 * 1.6 { scores[index] = -distance / (2 * 0.35 * 0.35) }
            }
            guard scores[label].isFinite, let best = scores.max(), best.isFinite else { return nil }
            literalSpatial += scores[label]
            for index in scores.indices where scores[index] < best - 6 { scores[index] = -.infinity }
            likelihoods.append(scores)
        }
        let literalPrior = sources.map { _, lexicon in
            lexicon.logPrior(for: literal) ?? log(1 / lexicon.total)
        }.max() ?? 0
        var visits = 0
        var found: [String: Candidate] = [:]
        for (language, lexicon) in sources {
            // Depth <= 32; children ordered by spatial likelihood, then alphabet, for deterministic budgets.
            func walk(_ index: Int, _ position: Int, _ spelling: String, _ spatial: Double) -> Bool {
                visits += 1
                guard visits <= budget, let node = lexicon.node(index) else { return false }
                if position == word.samples.count {
                    if node.count > 0, spelling != literal {
                        let item = Candidate(word: spelling, language: language,
                                             score: spatial + Self.priorWeight * log(node.count / lexicon.total),
                                             spatialScore: spatial)
                        if found[spelling].map({ item.score > $0.score }) ?? true { found[spelling] = item }
                        // Keep only the best eight; they include the runner-up needed for confidence.
                        if found.count > 8, let worst = found.values.sorted(by: Self.precedes).last {
                            found.removeValue(forKey: worst.word)
                        }
                    }
                    return true
                }
                var children: [(Int, Int, Double)] = []
                var labels: Set<Int> = []
                for child in node.children {
                    guard let item = lexicon.node(child), labels.insert(item.label).inserted else { return false }
                    let score = likelihoods[position][item.label]
                    if score.isFinite { children.append((child, item.label, score)) }
                }
                children.sort { $0.2 == $1.2 ? $0.1 < $1.1 : $0.2 > $1.2 }
                for (child, label, score) in children {
                    if !walk(child, position + 1, spelling + String(alphabet[label]), spatial + score) { return false }
                }
                return true
            }
            // Exhaustion is not a trustworthy top-two result; discard it, rather than auto-correcting a partial search.
            guard walk(0, 0, "", 0) else { return nil }
        }
        let literalScore = literalSpatial + Self.priorWeight * literalPrior
        // Do not displace a correctly typed word's usual completions with worse spatial alternatives.
        return Result(candidates: found.values.filter { $0.score > literalScore }.sorted(by: Self.precedes),
                      literalScore: literalScore, literalSpatialScore: literalSpatial)
    }

    private static func precedes(_ a: Candidate, _ b: Candidate) -> Bool {
        a.score == b.score ? a.word < b.word : a.score > b.score
    }
}
