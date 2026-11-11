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
    enum Edit: Equatable {
        case none, missingLetter(at: Int), extraTap(at: Int), transposition(at: Int)
    }
    nonisolated struct Candidate {
        let word: String
        let language: Language?
        let score: Double
        let spatialScore: Double
        let edit: Edit
        /// Candidate letter -> observed tap; missing letters have no tap.
        let alignment: [Int?]
    }
    enum Refusal: String, CaseIterable {
        case incompleteSearch, noCandidate, belowMargin, ambiguous, editNeedsInvalidLiteral
    }
    enum AutoDecision { case replace(Candidate), refuse(Refusal) }
    enum Unavailable { case evidence, resource }
    enum Outcome { case result(Result), unavailable(Unavailable) }
    nonisolated struct Result {
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
    private static let priorWeight = 0.35
    private static let editPenalty = log(0.01)
    nonisolated static let editSuggestionLimit = 2
    // Conservatively cover rounding from regrouping <= 32 finite density terms.
    private static let boundSlack = 1e-10
    private var lexicons: [Language: SpatialWordLexicon]
    private let bundle: Bundle?
    private var loadTask: Task<Void, Never>?
    private var personalScan: PersonalLexiconSnapshot.ScanList?
    private var absentPersonalWords: [Set<Language>: [PersonalLexiconSnapshot.ScanList.Entry]] = [:]
    private var corpusAbsent: [Set<Language>: [String: Bool]] = [:]
    private static let corpusMemoLimit = 4_096
    private(set) var isResourceLoading = false

    init(lexicons: [Language: SpatialWordLexicon]) {
        self.lexicons = lexicons
        self.bundle = nil
    }

    init(bundle: Bundle) {
        self.bundle = bundle
        self.lexicons = [:]
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
            self.absentPersonalWords.removeAll()
            self.corpusAbsent.removeAll()
            self.isResourceLoading = false
            self.loadTask = nil
        }
    }

    private func lexicon(_ language: Language) -> SpatialWordLexicon? { lexicons[language] }

    /// The filtered entries track snapshot identity (including changed bonuses). Corpus absence
    /// depends only on installed resources and the language set, so its bounded RAM memo survives
    /// count changes. At most three nonempty language sets; installing resources clears both caches.
    private func personalWords(_ personal: PersonalLexiconSnapshot, languages: Set<Language>,
                               sources: [(Language, SpatialWordLexicon)]) -> [PersonalLexiconSnapshot.ScanList.Entry] {
        if personalScan !== personal.scan {
            personalScan = personal.scan
            absentPersonalWords.removeAll()
        }
        if let cached = absentPersonalWords[languages] { return cached }
        var memo = corpusAbsent.removeValue(forKey: languages) ?? [:]
        let words = personal.scan.entries.filter { entry in
            if let absent = memo[entry.word] { return absent }
            let absent = sources.allSatisfy { $0.1.logPrior(for: entry.word) == nil }
            if memo.count >= Self.corpusMemoLimit { memo.removeAll(keepingCapacity: true) }
            memo[entry.word] = absent
            return absent
        }
        corpusAbsent[languages] = memo
        absentPersonalWords[languages] = words
        return words
    }

    nonisolated private struct Trail {
        let parent: Int
        let label: Int
        let tap: Int?
    }
    nonisolated private struct State {
        let source: Int
        let node: Int
        let tap: Int
        let depth: Int
        let trail: Int
        let spatial: Double
        let penalty: Double
        let edit: Edit
        let bound: Double
    }
    /// Heap entries and parent trails are integer indices; no per-state strings or arrays.
    nonisolated private struct Frontier {
        var states: [State] = []
        var trails: [Trail] = []
        var heap: [Int] = []
        var best: [Int: Double] = [:]
        var capped = false

        private func key(_ state: State) -> Int {
            // At most two sources, 33 tap positions and two edit-used states.
            ((state.node * 33 + state.tap) * 2 + (state.edit == .none ? 0 : 1)) * 2 + state.source
        }
        func isDominated(_ state: State) -> Bool {
            state.spatial + state.penalty < (best[key(state)] ?? -.infinity)
        }

        func precedes(_ a: Int, _ b: Int) -> Bool {
            states[a].bound == states[b].bound ? a < b : states[a].bound > states[b].bound
        }
        mutating func push(_ state: State, letters: [(Int, Int?)], essential: Bool = true) {
            // A trie node fixes the spelling; future scores depend only on the tap
            // position and edit-used flag. Max-path scoring can discard worse or
            // equal readings, retaining the first deterministic alignment on ties.
            let key = key(state)
            let score = state.spatial + state.penalty
            guard score > (best[key] ?? -.infinity) else { return }
            // Cap both arenas. A transposition needs two spelling records. States below
            // the exact-search threshold only serve best-effort edit suggestions: they may
            // use at most half of each arena and their loss never voids `complete`.
            let limit = essential ? SpatialWordDecoder.maxGenerated : SpatialWordDecoder.maxGenerated / 2
            guard states.count < limit, trails.count + letters.count <= limit else {
                if essential { capped = true }
                return
            }
            best[key] = score
            var trail = state.trail
            for (label, tap) in letters {
                trails.append(Trail(parent: trail, label: label, tap: tap))
                trail = trails.count - 1
            }
            let index = states.count
            states.append(State(source: state.source, node: state.node, tap: state.tap, depth: state.depth,
                                trail: trail, spatial: state.spatial, penalty: state.penalty,
                                edit: state.edit, bound: state.bound))
            heap.append(index)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard precedes(heap[child], heap[parent]) else { break }
                heap.swapAt(child, parent)
                child = parent
            }
        }
        mutating func pop() -> State? {
            guard let first = heap.first, let last = heap.popLast() else { return nil }
            if !heap.isEmpty {
                heap[0] = last
                var parent = 0
                while parent * 2 + 1 < heap.count {
                    var child = parent * 2 + 1
                    if child + 1 < heap.count, precedes(heap[child + 1], heap[child]) { child += 1 }
                    guard precedes(heap[child], heap[parent]) else { break }
                    heap.swapAt(child, parent)
                    parent = child
                }
            }
            return states[first]
        }
        func spelling(_ trail: Int) -> (String, [Int?]) {
            var letters: [Character] = []
            var alignment: [Int?] = []
            var index = trail
            while index >= 0 {
                let entry = trails[index]
                letters.append(SpatialWordLexicon.alphabet[entry.label])
                alignment.append(entry.tap)
                index = entry.parent
            }
            return (String(letters.reversed()), Array(alignment.reversed()))
        }
    }

    func decode(_ word: KeyboardTouchWord, languages: Set<Language>,
                budget: Int = SpatialWordDecoder.searchBudget,
                calibration: SpatialTouchCalibration? = nil,
                personal: PersonalLexiconSnapshot = .empty, allowsEdits: Bool = true) -> Result? {
        if case .result(let result) = decodeDetailed(word, languages: languages, budget: budget,
                                                    calibration: calibration, personal: personal,
                                                    allowsEdits: allowsEdits) { return result }
        return nil
    }

    func decodeDetailed(_ word: KeyboardTouchWord, languages: Set<Language>,
                        budget: Int = SpatialWordDecoder.searchBudget,
                        calibration: SpatialTouchCalibration? = nil,
                        personal: PersonalLexiconSnapshot = .empty, allowsEdits: Bool = true) -> Outcome {
        let literal = word.text.lowercased()
        let count = word.samples.count
        guard (3...Self.maxLetters).contains(count), literal.count == count,
              word.layout.layer == .letters, word.layout.field == .text, !languages.isEmpty else {
            return .unavailable(.evidence)
        }
        // Never partially decode a bilingual request with missing data.
        var sources: [(Language, SpatialWordLexicon)] = []
        for language in Language.allCases where languages.contains(language) {
            guard let source = lexicon(language) else { return .unavailable(.resource) }
            sources.append((language, source))
        }
        let alphabet = SpatialWordLexicon.alphabet
        var frames: [Int: CGRect] = [:]
        for (index, letter) in alphabet.enumerated() {
            if let key = word.layout.key(.character(String(letter))) { frames[index] = key.frame }
        }
        var likelihoods: [[Double]] = []
        var bestScores: [Double] = []
        var literalSpatial = 0.0
        for sample in word.samples {
            guard sample.text.count == 1, sample.text.lowercased().count == 1,
                  sample.key == word.layout.key(sample.key.kind),
                  sample.key.character?.lowercased() == sample.text.lowercased(),
                  sample.point.x.isFinite, sample.point.y.isFinite,
                  let letter = sample.text.lowercased().first,
                  let label = alphabet.firstIndex(of: letter), frames[label] != nil else {
                return .unavailable(.evidence)
            }
            var scores = [Double](repeating: -.infinity, count: alphabet.count)
            for index in alphabet.indices {
                guard let frame = frames[index] else { continue }
                let width = Double(frame.width + word.layout.metrics.gap)
                let height = Double(frame.height + word.layout.metrics.rowGap)
                guard frame.width > 0, frame.height > 0, width.isFinite, height.isFinite,
                      width > 0, height > 0 else { return .unavailable(.evidence) }
                let key = calibration?.keys[alphabet[index]]
                let dx = Double(sample.point.x - frame.midX) / width - (key?.offsetX ?? 0)
                let dy = Double(sample.point.y - frame.midY) / height - (key?.offsetY ?? 0)
                let sx = key?.sigmaX ?? SpatialTouchCalibration.staticSigma
                let sy = key?.sigmaY ?? SpatialTouchCalibration.staticSigma
                // Density in pitch coordinates. The -log(2πσxσy) term is essential:
                // omitting it would reward broader personal distributions unfairly.
                if dx * dx + dy * dy <= 1.6 * 1.6 {
                    scores[index] = -0.5 * (dx * dx / (sx * sx) + dy * dy / (sy * sy))
                        - log(2 * Double.pi * sx * sy)
                }
            }
            guard scores[label].isFinite, let best = scores.max(), best.isFinite else {
                return .unavailable(.evidence)
            }
            // Literal is ungated by the relative six-log-unit candidate cutoff, and has no edits.
            literalSpatial += scores[label]
            bestScores.append(best)
            for index in scores.indices where scores[index] < best - 6 { scores[index] = -.infinity }
            likelihoods.append(scores)
        }
        let floorPrior = sources.map { log(1 / $0.1.total) }.max() ?? 0
        let literalInLexicon = sources.contains { $0.1.logPrior(for: literal) != nil }
        let literalPrior = sources.map { _, source in
            source.logPrior(for: literal) ?? log(1 / source.total)
        }.max() ?? 0
        let literalScore = literalSpatial + Self.priorWeight * literalPrior + personal.bonus(for: literal)
        // Stray density: the tap's best gated key density, without assigning a letter.
        // Thus an extra tap contributes bestScores[i] to spatialScore, plus log(.01)
        // to total score. It is deliberately not a free deletion.
        var suffix = [Double](repeating: 0, count: count + 1)
        for index in (0..<count).reversed() { suffix[index] = suffix[index + 1] + bestScores[index] }
        var found: [String: Candidate] = [:]
        var threshold = literalScore
        // Suggestion-only structural retrieval below an absent literal, down to one edit
        // penalty under it: "would beat the literal if the edit were free". Explored only
        // after the exact above-literal search is proven, from the same pop budget.
        let suggestsEdits = allowsEdits && !literalInLexicon
        var below: [String: Candidate] = [:]
        var belowThreshold = suggestsEdits ? literalScore + Self.editPenalty : Double.infinity
        func retainBelow(_ candidate: Candidate) {
            guard suggestsEdits, candidate.edit != .none, candidate.score >= belowThreshold,
                  found[candidate.word] == nil else { return }
            if let previous = below[candidate.word], !Self.precedes(candidate, previous) { return }
            below[candidate.word] = candidate
            if below.count > Self.editSuggestionLimit, let worst = below.values.sorted(by: Self.precedes).last {
                below.removeValue(forKey: worst.word)
            }
            if below.count == Self.editSuggestionLimit {
                belowThreshold = max(belowThreshold, (below.values.map(\.score).min() ?? belowThreshold) - Self.scoreQuantum)
            }
        }
        func retain(_ candidate: Candidate) {
            guard candidate.word != literal else { return }
            guard candidate.score > literalScore else { retainBelow(candidate); return }
            below.removeValue(forKey: candidate.word)
            if let previous = found[candidate.word], !Self.precedes(candidate, previous) { return }
            found[candidate.word] = candidate
            if found.count > 8, let worst = found.values.sorted(by: Self.precedes).last {
                found.removeValue(forKey: worst.word)
            }
            if found.count == 8 { threshold = (found.values.map(\.score).min() ?? literalScore) - Self.scoreQuantum }
        }
        // Personal scan is bounded independently of trie states; only normalized alphabet words
        // absent from ALL selected corpora participate. A one-edit fixed-word DP scores them.
        let personalComplete = personal.scan.complete
        for entry in personalWords(personal, languages: languages, sources: sources) {
            let labels = entry.labels
            guard abs(labels.count - count) <= (allowsEdits ? 1 : 0) else { continue }
            // First letter can use tap 0, tap 1 (extra/transposition), or be missing.
            if !allowsEdits && !likelihoods[0][labels[0]].isFinite { continue }
            if allowsEdits && !likelihoods[0][labels[0]].isFinite && !likelihoods[1][labels[0]].isFinite
                && (labels.count < 2 || !likelihoods[0][labels[1]].isFinite) { continue }
            guard let reading = Self.reading(labels: labels, likelihoods: likelihoods,
                                            stray: bestScores, allowsEdits: allowsEdits) else { continue }
            retain(Candidate(word: entry.word, language: nil,
                             score: reading.spatial + reading.penalty + Self.priorWeight * floorPrior + entry.bonus,
                             spatialScore: reading.spatial, edit: reading.edit, alignment: reading.alignment))
        }
        var frontier = Frontier()
        // A subtree's best terminal prior and the snapshot's largest bonus tighten
        // the bound without changing the objective. Remaining tap densities include
        // stray taps and may be POSITIVE; future edit penalties are nonpositive.
        let maxBonus = personal.scan.maxBonus
        for source in sources.indices {
            let bound = suffix[0] + Self.priorWeight * sources[source].1.bestLogPrior(at: 0) + maxBonus + Self.boundSlack
            frontier.push(State(source: source, node: 0, tap: 0, depth: 0, trail: -1,
                                spatial: 0, penalty: 0, edit: .none, bound: bound),
                          letters: [], essential: bound >= threshold)
        }
        var visits = 0
        var proven = false
        while let first = frontier.heap.first {
            // Bounds never increase along a path, so once the best frontier bound drops
            // below `threshold` the above-literal top eight are final (proof); the loop
            // only continues for best-effort below-literal edit suggestions.
            let top = frontier.states[first].bound
            if top < threshold { proven = true }
            if top < min(threshold, belowThreshold) { break }
            guard visits < max(0, min(budget, Self.searchBudget)), !frontier.capped else { break }
            guard let state = frontier.pop() else { break }
            visits += 1
            if frontier.isDominated(state) { continue }
            // After the proof only edit suggestions remain; an unedited path must still pay one penalty.
            if proven, state.edit == .none, state.bound + Self.editPenalty < belowThreshold { continue }
            let (language, source) = sources[state.source]
            guard let node = source.node(state.node) else { return .unavailable(.resource) }
            if state.tap == count, node.count > 0 {
                let (spelling, alignment) = frontier.spelling(state.trail)
                retain(Candidate(word: spelling, language: language,
                                 score: state.spatial + state.penalty + Self.priorWeight * log(node.count / source.total)
                                    + personal.bonus(for: spelling),
                                 spatialScore: state.spatial, edit: state.edit, alignment: alignment))
            }
            let canEdit = allowsEdits && state.edit == .none
            func enqueue(node: Int, tap: Int, letters: [(Int, Int?)], spatial: Double, edit: Edit) {
                let depth = state.depth + letters.count
                guard depth <= Self.maxLetters else { return }
                let penalty = edit == .none ? 0 : Self.editPenalty
                let bound = spatial + penalty + suffix[tap] + Self.priorWeight * source.bestLogPrior(at: node)
                    + maxBonus + Self.boundSlack
                let essential = bound >= threshold
                guard essential || bound + (edit == .none ? Self.editPenalty : 0) >= belowThreshold else { return }
                frontier.push(State(source: state.source, node: node, tap: tap, depth: depth,
                                    trail: state.trail, spatial: spatial, penalty: penalty,
                                    edit: edit, bound: bound), letters: letters, essential: essential)
            }
            if canEdit, state.tap < count {
                enqueue(node: state.node, tap: state.tap + 1, letters: [],
                        spatial: state.spatial + bestScores[state.tap], edit: .extraTap(at: state.tap))
            }
            guard state.depth < Self.maxLetters else { continue }
            var labels: Set<Int> = []
            for child in node.children {
                guard let item = source.node(child), labels.insert(item.label).inserted else { return .unavailable(.resource) }
                if state.tap < count {
                    let spatial = likelihoods[state.tap][item.label]
                    if spatial.isFinite {
                        enqueue(node: child, tap: state.tap + 1, letters: [(item.label, state.tap)],
                                spatial: state.spatial + spatial, edit: state.edit)
                    }
                }
                if canEdit {
                    enqueue(node: child, tap: state.tap, letters: [(item.label, nil)],
                            spatial: state.spatial, edit: .missingLetter(at: state.depth))
                }
                if canEdit, state.tap + 1 < count, state.depth + 2 <= Self.maxLetters,
                   likelihoods[state.tap + 1][item.label].isFinite {
                    var grandLabels: Set<Int> = []
                    for grandchild in item.children {
                        guard let next = source.node(grandchild), grandLabels.insert(next.label).inserted else {
                            return .unavailable(.resource)
                        }
                        guard next.label != item.label, likelihoods[state.tap][next.label].isFinite else { continue }
                        enqueue(node: grandchild, tap: state.tap + 2,
                                letters: [(item.label, state.tap + 1), (next.label, state.tap)],
                                spatial: state.spatial + likelihoods[state.tap + 1][item.label] + likelihoods[state.tap][next.label],
                                edit: .transposition(at: state.depth))
                    }
                }
            }
        }
        // Exact top-eight DISTINCT spellings above literal under frozen max-path scoring
        // when complete: all eligible personal words scanned and frontier exhausted/bounded.
        // Any essential arena truncation conservatively makes the proof incomplete.
        return .result(Result(candidates: found.values.sorted(by: Self.precedes), literalScore: literalScore,
                              literalSpatialScore: literalSpatial, literalInLexicon: literalInLexicon,
                              complete: personalComplete && !frontier.capped && (proven || frontier.heap.isEmpty),
                              visits: visits, generated: frontier.states.count,
                              editSuggestions: below.values.filter { found[$0.word] == nil }.sorted(by: Self.precedes)))
    }

    nonisolated private struct Reading {
        let spatial: Double
        let penalty: Double
        let edit: Edit
        let alignment: [Int?]
    }

    /// Fixed-word one-edit alignment DP, expanded into its O(n) possible edit locations.
    /// Spatial substitutions remain allowed at every aligned position, as in the trie.
    private static func reading(labels: [Int], likelihoods: [[Double]], stray: [Double],
                                allowsEdits: Bool) -> Reading? {
        let n = labels.count
        let m = likelihoods.count
        var best: Reading?
        func consider(_ alignment: [Int?], _ edit: Edit, extra: Int? = nil) {
            var spatial = extra.map { stray[$0] } ?? 0
            for index in labels.indices {
                if let tap = alignment[index] { spatial += likelihoods[tap][labels[index]] }
            }
            guard spatial.isFinite else { return }
            let penalty = edit == .none ? 0 : Self.editPenalty
            if let current = best, current.spatial + current.penalty >= spatial + penalty { return }
            best = Reading(spatial: spatial, penalty: penalty, edit: edit, alignment: alignment)
        }
        if n == m {
            consider((0..<n).map { Optional($0) }, .none)
            if allowsEdits {
                for index in 0..<(n - 1) where labels[index] != labels[index + 1] {
                    var alignment = (0..<n).map { Optional($0) }
                    alignment.swapAt(index, index + 1)
                    consider(alignment, .transposition(at: index))
                }
            }
        } else if allowsEdits, n == m + 1 {
            for missing in 0..<n {
                consider((0..<n).map { $0 == missing ? nil : ($0 < missing ? $0 : $0 - 1) }, .missingLetter(at: missing))
            }
        } else if allowsEdits, m == n + 1 {
            for extra in 0..<m {
                consider((0..<n).map { $0 < extra ? $0 : $0 + 1 }, .extraTap(at: extra), extra: extra)
            }
        }
        return best
    }

    /// Conservative text-only learning labels: at most one unit-cost spelling edit.
    /// Repeated-letter optimal alignments are merged, dropping only ambiguous positions;
    /// a transposed pair is always dropped. No spatial evidence is guessed here.
    static func align(word: String, taps: [Character]) -> [Int?]? {
        let letters = Array(word.lowercased())
        let typed = taps.map { Character(String($0).lowercased()) }
        let n = letters.count
        let m = typed.count
        guard n > 0, n <= maxLetters, m > 0, m <= maxLetters, abs(n - m) <= 1 else { return nil }
        var readings: [[Int?]] = []
        if n == m {
            let mismatches = (0..<n).filter { letters[$0] != typed[$0] }
            if mismatches.count <= 1 { return (0..<n).map { $0 } }
            if mismatches.count == 2, let first = mismatches.first, mismatches[1] == first + 1,
               letters[first] == typed[first + 1], letters[first + 1] == typed[first] {
                return (0..<n).map { $0 == first || $0 == first + 1 ? nil : $0 }
            }
            return nil
        }
        if n == m + 1 {
            for missing in 0..<n {
                let alignment: [Int?] = (0..<n).map { $0 == missing ? nil : ($0 < missing ? $0 : $0 - 1) }
                if letters.indices.allSatisfy({ i in alignment[i].map { letters[i] == typed[$0] } ?? true }) {
                    readings.append(alignment)
                }
            }
        } else {
            for extra in 0..<m {
                let alignment = (0..<n).map { Optional($0 < extra ? $0 : $0 + 1) }
                if letters.indices.allSatisfy({ i in alignment[i].map { letters[i] == typed[$0] } ?? false }) {
                    readings.append(alignment)
                }
            }
        }
        guard var result = readings.first else { return nil }
        for reading in readings.dropFirst() {
            for index in result.indices where result[index] != reading[index] { result[index] = nil }
        }
        return result
    }

    // Integer-sized score buckets give a transitive ordering (unlike pairwise epsilon
    // comparisons). Sub-nanolog rounding from key centres/libm/sum regrouping is a tie.
    private static let scoreQuantum = 1e-9
    private static func precedes(_ a: Candidate, _ b: Candidate) -> Bool {
        let aScore = (a.score / scoreQuantum).rounded()
        let bScore = (b.score / scoreQuantum).rounded()
        if aScore != bScore { return aScore > bScore }
        if a.word != b.word { return a.word < b.word }
        return (a.language?.rawValue ?? "") < (b.language?.rawValue ?? "")
    }
}
