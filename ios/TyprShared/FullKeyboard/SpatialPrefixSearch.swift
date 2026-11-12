import Foundation

/// Bounded best-first prefix enumeration over TSW1 max-descendant counts. Idea translated
/// from iikb Correction/Lexicon.swift:226–244, 09a2e9cdfbe851adff6c4646333c0a3f74ba8765
/// (MIT, © 2026 Bassim Shahidy). No upstream resources, binary format or automatic policy.
nonisolated enum SpatialPrefixSearch {
    static let maxVisits = 512
    static let maxGenerated = 2_048
    static let maxResults = 8
    static let maxLetters = 32

    struct Candidate: Equatable, Sendable {
        let word: String
        let language: SpatialWordDecoder.Language
        let isCompletion: Bool
    }
    struct Result: Sendable {
        var candidates: [Candidate] = []
        var visits = 0
        var generated = 0
        // This is display retrieval only, not the correction decoder's completeness proof.
        var truncated = false
    }
    private struct State {
        let source: Int
        let node: Int
        let spelling: String
        let depth: Int
        let spatial: Double
        let mismatches: Int
        let terminal: Bool
        let bound: Double
    }

    /// Payload ceiling for the arena, heap and bounded UTF-8 spellings (alphabet <=2 bytes).
    /// Excludes Swift allocator metadata/capacity rounding and shared mapped resources; NOT RSS.
    static var arenaPayloadByteBound: Int {
        maxGenerated * (MemoryLayout<State>.stride + MemoryLayout<Int>.stride + maxLetters * 2)
    }

    static func search(_ prefix: String, lexicons: [SpatialWordDecoder.Language: SpatialWordLexicon],
                       languages: Set<SpatialWordDecoder.Language>, evidence: KeyboardTouchWord? = nil,
                       calibration: SpatialTouchCalibration? = nil, budget: Int = maxVisits) -> Result {
        // Bound normalization/allocation before inspecting graphemes (NFD is accepted).
        guard prefix.utf8.count <= maxLetters * 4 else { return Result() }
        let literal = prefix.precomposedStringWithCanonicalMapping.lowercased()
        let letters = Array(literal)
        guard (2..<maxLetters).contains(letters.count), !languages.isEmpty,
              letters.allSatisfy({ SpatialWordLexicon.alphabet.contains($0) }) else { return Result() }
        let sources = SpatialWordDecoder.Language.allCases.filter { languages.contains($0) }
        // Missing one selected source never silently becomes English-only bilingual search.
        guard sources.allSatisfy({ lexicons[$0] != nil }) else { return Result() }
        let corpora = sources.compactMap { lexicons[$0] }
        let emissions = evidence.flatMap { word -> KeyboardLetterMap.Emissions? in
            guard word.samples.count == letters.count,
                  word.text.precomposedStringWithCanonicalMapping.lowercased() == literal else { return nil }
            return KeyboardLetterMap.emissions(for: word, calibration: calibration)
        }
        var states: [State] = []
        var heap: [Int] = []
        var result = Result()
        func precedes(_ a: Int, _ b: Int) -> Bool {
            let lhs = states[a], rhs = states[b]
            let x = (lhs.bound * 1e9).rounded(), y = (rhs.bound * 1e9).rounded()
            if x != y { return x > y }
            // A prefix sorts before its descendants: expand only lexically earlier tied
            // subtrees before emitting a terminal, not every equal-frequency subtree.
            if lhs.spelling != rhs.spelling { return lhs.spelling < rhs.spelling }
            if lhs.terminal != rhs.terminal { return lhs.terminal }
            return a < b
        }
        func push(_ state: State) {
            guard states.count < maxGenerated else { result.truncated = true; return }
            states.append(state)
            heap.append(states.count - 1)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard precedes(heap[child], heap[parent]) else { break }
                heap.swapAt(child, parent)
                child = parent
            }
        }
        func pop() -> State? {
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
        // Equal source weights and normalized per-language counts. Shared spellings keep
        // their best component; this ranking score is NOT a calibrated bilingual probability.
        let sourceWeight = log(1 / Double(sources.count))
        for source in corpora.indices {
            push(State(source: source, node: 0, spelling: "", depth: 0, spatial: 0,
                       mismatches: 0, terminal: false,
                       bound: 0.35 * corpora[source].bestLogPrior(at: 0) + sourceWeight))
        }
        var seen: Set<String> = []
        while !heap.isEmpty, result.candidates.count < maxResults {
            guard result.visits < max(0, min(budget, maxVisits)) else { result.truncated = true; break }
            guard let state = pop() else { break }
            result.visits += 1
            if state.terminal {
                guard seen.insert(state.spelling).inserted else { continue }
                result.candidates.append(Candidate(word: state.spelling, language: sources[state.source],
                                                   isCompletion: state.depth > letters.count))
                continue
            }
            let source = corpora[state.source]
            guard let node = source.node(state.node) else { return Result() }
            // Same-length holder alternatives are manual accent suggestions, not completions.
            if state.depth >= letters.count, node.count > 0, state.spelling != literal,
               state.depth > letters.count || state.mismatches == 0 {
                push(State(source: state.source, node: state.node, spelling: state.spelling, depth: state.depth,
                           spatial: state.spatial, mismatches: state.mismatches, terminal: true,
                           bound: state.spatial + 0.35 * log(node.count / source.total) + sourceWeight))
            }
            guard state.depth < maxLetters else { continue }
            for child in node.children {
                guard let item = source.node(child) else { return Result() }
                let letter = SpatialWordLexicon.alphabet[item.label]
                var spatial = state.spatial
                var mismatches = state.mismatches
                if state.depth < letters.count {
                    let matches = KeyboardLetterMap.holder(of: letter) == KeyboardLetterMap.holder(of: letters[state.depth])
                    // At most one noisy physical-key substitution. No structural edit or invented tap.
                    if !matches { mismatches += 1 }
                    guard mismatches <= (emissions == nil ? 0 : 1) else { continue }
                    if let emissions {
                        let value = emissions.likelihoods[state.depth][item.label]
                        guard value.isFinite else { continue }
                        // Relative density <=0 makes future unobserved suffix bounds admissible.
                        spatial += value - emissions.best[state.depth]
                    }
                }
                push(State(source: state.source, node: child, spelling: state.spelling + String(letter),
                           depth: state.depth + 1, spatial: spatial, mismatches: mismatches, terminal: false,
                           bound: spatial + 0.35 * source.bestLogPrior(at: child) + sourceWeight))
            }
        }
        result.generated = states.count
        return result
    }
}
