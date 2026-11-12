import Foundation

/// Immutable, snapshot-local prefix retrieval. Sorted spellings locate a prefix interval;
/// a range-maximum tree retrieves its best eight words without scanning that interval.
/// Personal unigram/keep completion idea: iikb Correction/TypingMemory.swift at
/// 09a2e9cdfbe851adff6c4646333c0a3f74ba8765 (MIT, © 2026 Bassim Shahidy).
/// The bounded index and stable source-order reranking are Typr's implementation.
nonisolated struct PersonalCompletionIndex: Sendable {
    static let capacity = 2_000
    static let resultLimit = 8
    struct Entry: Sendable {
        let word: String
        let kept: Bool
        let count: Int
    }
    let entries: [Entry]
    private let tree: [Int]
    private let base: Int

    init(kept: Set<String>, counts: [String: Int]) {
        entries = kept.union(counts.keys).sorted().prefix(Self.capacity).compactMap { word in
            guard word.utf8.count <= 256, (2...32).contains(word.count),
                  word.allSatisfy(\.isLetter), word == PersonalLexiconSnapshot.normalize(word),
                  kept.contains(word) || (counts[word] ?? 0) > 0 else { return nil }
            return Entry(word: word, kept: kept.contains(word), count: max(0, min(10_000, counts[word] ?? 0)))
        }
        var base = 1
        while base < entries.count { base *= 2 }
        self.base = base
        var tree = [Int](repeating: -1, count: base * 2)
        for index in entries.indices { tree[base + index] = index }
        if base > 1 {
            for node in (1..<base).reversed() {
                tree[node] = Self.best(tree[node * 2], tree[node * 2 + 1], entries: entries)
            }
        }
        self.tree = tree
    }

    private static func best(_ a: Int, _ b: Int, entries: [Entry]) -> Int {
        guard a >= 0 else { return b }
        guard b >= 0 else { return a }
        let lhs = entries[a], rhs = entries[b]
        if lhs.kept != rhs.kept { return lhs.kept ? a : b }
        if lhs.count != rhs.count { return lhs.count > rhs.count ? a : b }
        return min(a, b) // lexical tie, since entries are sorted
    }

    /// Element payload plus bounded UTF-8 bytes, not allocator overhead or RSS.
    var payloadBytes: Int {
        entries.count * MemoryLayout<Entry>.stride + tree.count * MemoryLayout<Int>.stride
            + entries.reduce(0) { $0 + $1.word.utf8.count }
    }

    func completions(for rawPrefix: String) -> [String] {
        guard rawPrefix.utf8.count <= 256 else { return [] }
        let prefix = PersonalLexiconSnapshot.normalize(rawPrefix)
        guard (2...31).contains(prefix.count), prefix.allSatisfy(\.isLetter) else { return [] }
        func boundary(upper: Bool) -> Int {
            var low = 0, high = entries.count
            while low < high {
                let middle = (low + high) / 2, word = entries[middle].word
                if word < prefix || (upper && word.hasPrefix(prefix)) { low = middle + 1 }
                else { high = middle }
            }
            return low
        }
        func winner(_ range: Range<Int>) -> Int {
            var low = range.lowerBound + base, high = range.upperBound + base, best = -1
            while low < high {
                if low % 2 == 1 { best = Self.best(best, tree[low], entries: entries); low += 1 }
                if high % 2 == 1 { high -= 1; best = Self.best(best, tree[high], entries: entries) }
                low /= 2; high /= 2
            }
            return best
        }
        var low = boundary(upper: false)
        let high = boundary(upper: true)
        if low < high, entries[low].word == prefix { low += 1 }
        guard low < high else { return [] }
        struct Interval { let range: Range<Int>; let best: Int }
        var pending = [Interval(range: low..<high, best: winner(low..<high))]
        var result: [String] = []
        // At most eight pops, 17 O(log 2,000) range queries, nine pending intervals.
        while result.count < Self.resultLimit, !pending.isEmpty {
            let next = pending.indices.min {
                Self.best(pending[$0].best, pending[$1].best, entries: entries) == pending[$0].best
            }!
            let interval = pending.remove(at: next), index = interval.best
            result.append(entries[index].word)
            for range in [interval.range.lowerBound..<index, (index + 1)..<interval.range.upperBound]
                where !range.isEmpty {
                pending.append(Interval(range: range, best: winner(range)))
            }
        }
        return result
    }
}

/// Display-only union, never an input to automatic replacement or touch labeling.
nonisolated enum KeyboardCompletionRanking {
    static let systemLimit = 64
    struct Input: Sendable {
        let token: String
        let system: [String]
        let allowsNoisyPrefix: Bool
        let corpusEnabled: Bool
    }
    struct Candidate: Sendable {
        let word: String
        let language: SpatialWordDecoder.Language?
        let isCompletion: Bool
    }
    struct Result: Sendable {
        let corpus: [SpatialPrefixSearch.Candidate]
        let system: [String]
        let ranked: [Candidate]
        let personalized: Bool
    }

    static func rank(_ input: Input, corpus: [SpatialPrefixSearch.Candidate],
                     personal: PersonalLexiconSnapshot) -> Result {
        var seen: Set<String> = []
        var candidates: [Candidate] = []
        func append(_ candidate: Candidate) {
            let key = PersonalLexiconSnapshot.normalize(candidate.word)
            guard seen.insert(key).inserted else { return }
            candidates.append(candidate)
        }
        for item in corpus { append(Candidate(word: item.word, language: item.language, isCompletion: item.isCompletion)) }
        for word in input.system.prefix(systemLimit) {
            append(Candidate(word: word, language: nil, isCompletion: true))
        }
        for word in personal.completionIndex.completions(for: input.token) {
            append(Candidate(word: word, language: nil, isCompletion: true))
        }
        func weight(_ candidate: Candidate) -> (Bool, Int) {
            guard candidate.isCompletion else { return (false, 0) }
            let key = PersonalLexiconSnapshot.normalize(candidate.word)
            return (personal.kept.contains(key), personal.counts[key] ?? 0)
        }
        let personalized = candidates.contains { let w = weight($0); return w.0 || w.1 > 0 }
        let ranked = candidates.enumerated().sorted { lhs, rhs in
            let a = weight(lhs.element), b = weight(rhs.element)
            if a.0 != b.0 { return a.0 }
            if a.1 != b.1 { return a.1 > b.1 }
            return lhs.offset < rhs.offset // preserve the exact baseline order on ties
        }.map(\.element)
        return Result(corpus: corpus, system: input.system, ranked: ranked, personalized: personalized)
    }
}
