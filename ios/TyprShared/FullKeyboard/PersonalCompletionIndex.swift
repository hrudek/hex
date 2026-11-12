import Foundation

/// Immutable prefix index over one personal snapshot's prepared scan list (≤2,000 words).
/// Sorted spellings locate a prefix interval by binary search; a range-maximum tree then
/// yields the best eight words of that interval without scanning it. Built once with the
/// snapshot (after a word is counted, kept or forgotten), never per keystroke.
/// Personal unigram/keep completion idea: iikb Correction/TypingMemory.swift at
/// 09a2e9cdfbe851adff6c4646333c0a3f74ba8765 (MIT, © 2026 Bassim Shahidy).
/// The bounded index and stable baseline-order reranking are Typr's implementation.
nonisolated struct PersonalCompletionIndex: Sendable {
    static let capacity = 2_000
    static let resultLimit = 8
    /// The same personal-word threshold as the decoder's scan list: kept, or counted twice.
    static let minimumCount = 2

    struct Entry: Sendable {
        let word: String
        let kept: Bool
        let count: Int
    }
    let entries: [Entry]
    private let tree: [Int32]
    private let base: Int

    /// `words` must be sorted, unique and normalized (the scan list already is).
    init(sortedWords words: [String], kept: Set<String>, counts: [String: Int]) {
        entries = words.prefix(Self.capacity).compactMap { word in
            let count = max(0, min(1_000_000, counts[word] ?? 0))
            let isKept = kept.contains(word)
            guard isKept || count >= Self.minimumCount else { return nil }
            return Entry(word: word, kept: isKept, count: count)
        }
        var base = 1
        while base < entries.count { base *= 2 }
        self.base = base
        var tree = [Int32](repeating: -1, count: base * 2)
        for index in entries.indices { tree[base + index] = Int32(index) }
        if base > 1 {
            for node in (1..<base).reversed() {
                tree[node] = Self.better(tree[node * 2], tree[node * 2 + 1], entries)
            }
        }
        self.tree = tree
    }

    /// Higher count first, then kept, then lexical (entries are sorted, so the lower index).
    private static func better(_ a: Int32, _ b: Int32, _ entries: [Entry]) -> Int32 {
        guard a >= 0 else { return b }
        guard b >= 0 else { return a }
        let lhs = entries[Int(a)], rhs = entries[Int(b)]
        if lhs.count != rhs.count { return lhs.count > rhs.count ? a : b }
        if lhs.kept != rhs.kept { return lhs.kept ? a : b }
        return min(a, b)
    }

    /// Element payload plus UTF-8 spelling bytes; not allocator overhead or RSS.
    var payloadBytes: Int {
        entries.count * MemoryLayout<Entry>.stride + tree.count * MemoryLayout<Int32>.stride
            + entries.reduce(0) { $0 + $1.word.utf8.count }
    }

    /// Strict extensions of `rawPrefix` (2–31 letters, case/NFC-insensitive), best first.
    /// At most eight pops, 17 O(log 2,000) range queries and nine pending intervals.
    func completions(for rawPrefix: String) -> [Entry] {
        guard !entries.isEmpty, rawPrefix.utf8.count <= 256 else { return [] }
        let prefix = PersonalLexiconSnapshot.normalize(rawPrefix)
        guard (2...31).contains(prefix.count), prefix.allSatisfy(\.isLetter) else { return [] }
        func boundary(upper: Bool) -> Int {
            var low = 0, high = entries.count
            while low < high {
                let middle = (low + high) / 2, word = entries[middle].word
                if word < prefix || (upper && word.hasPrefix(prefix)) { low = middle + 1 } else { high = middle }
            }
            return low
        }
        func winner(_ range: Range<Int>) -> Int32 {
            var low = range.lowerBound + base, high = range.upperBound + base
            var best: Int32 = -1
            while low < high {
                if low % 2 == 1 { best = Self.better(best, tree[low], entries); low += 1 }
                if high % 2 == 1 { high -= 1; best = Self.better(best, tree[high], entries) }
                low /= 2; high /= 2
            }
            return best
        }
        var low = boundary(upper: false)
        let high = boundary(upper: true)
        if low < high, entries[low].word == prefix { low += 1 }
        guard low < high else { return [] }
        var pending: [(range: Range<Int>, best: Int32)] = [(low..<high, winner(low..<high))]
        var result: [Entry] = []
        while result.count < Self.resultLimit, !pending.isEmpty {
            var next = 0
            for index in pending.indices.dropFirst()
            where Self.better(pending[index].best, pending[next].best, entries) == pending[index].best {
                next = index
            }
            let interval = pending.remove(at: next)
            let index = Int(interval.best)
            result.append(entries[index])
            for range in [interval.range.lowerBound..<index, (index + 1)..<interval.range.upperBound]
            where !range.isEmpty {
                pending.append((range, winner(range)))
            }
        }
        return result
    }
}

/// Display-only completion inputs, frozen on the main actor and retrieved on the suggestion
/// worker. Never an input to automatic replacement or touch labeling.
nonisolated struct KeyboardCompletionJob: Equatable, Sendable {
    let token: String
    let languages: Set<SpatialWordDecoder.Language>
    let resources: Int
    /// Intact taps for this token, if any; enables one noisy physical key in the prefix.
    let evidence: KeyboardTouchWord?
    let calibration: SpatialTouchCalibration?
    /// The prepared personal scan, or `nil` while Learn from my typing is off.
    let personal: PersonalLexiconSnapshot.ScanList?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token && lhs.languages == rhs.languages && lhs.resources == rhs.resources
            && lhs.evidence == rhs.evidence && lhs.calibration == rhs.calibration && lhs.personal === rhs.personal
    }
}

/// Bounded results of one job: ≤8 evidence-aware and ≤8 exact corpus candidates, ≤8 personal
/// prefix entries. Whether the literal is trusted needs the checker, so the main-actor finish
/// chooses between `corpus` and `exact`; the worker never calls the checker.
nonisolated struct KeyboardCompletionRetrieval: Sendable {
    let job: KeyboardCompletionJob
    let corpus: [SpatialPrefixSearch.Candidate]
    let exact: [SpatialPrefixSearch.Candidate]
    let personal: [PersonalCompletionIndex.Entry]

    init(_ job: KeyboardCompletionJob, lexicons: [SpatialWordDecoder.Language: SpatialWordLexicon]) {
        self.job = job
        let exact = SpatialPrefixSearch.search(job.token, lexicons: lexicons, languages: job.languages).candidates
        self.exact = exact
        corpus = job.evidence == nil ? exact
            : SpatialPrefixSearch.search(job.token, lexicons: lexicons, languages: job.languages,
                                         evidence: job.evidence, calibration: job.calibration).candidates
        personal = job.personal?.completions.completions(for: job.token) ?? []
    }
}

/// Stable personal reranking of displayed completions (issue #101). Candidates with no
/// personal weight are not returned; the caller keeps them in their original order.
nonisolated enum KeyboardCompletionRanking {
    /// System completions considered for promotion (the checker list is otherwise unbounded).
    static let systemLimit = 64

    struct Promotion: Equatable, Sendable {
        let word: String
        /// A personal word missing from the baseline lists; the caller supplies display casing.
        let isAddition: Bool
    }

    /// `baseline` is the shown order without personal influence (Typr corpus completions,
    /// then system completions). Higher count first, then kept, then baseline order; personal
    /// additions follow baseline words of equal weight. Bounded to `limit` results.
    static func promotions(token: String, baseline: [String], additions: [PersonalCompletionIndex.Entry],
                           personal: PersonalLexiconSnapshot,
                           limit: Int = PersonalCompletionIndex.resultLimit) -> [Promotion] {
        var seen: Set<String> = [PersonalLexiconSnapshot.normalize(token)]
        var ranked: [(promotion: Promotion, count: Int, kept: Bool, order: Int)] = []
        let candidates = baseline.prefix(systemLimit + SpatialPrefixSearch.maxResults).map { ($0, false) }
            + additions.prefix(PersonalCompletionIndex.resultLimit).map { ($0.word, true) }
        for (order, (word, isAddition)) in candidates.enumerated() {
            guard word.utf8.count <= 256 else { continue }
            let key = PersonalLexiconSnapshot.normalize(word)
            guard seen.insert(key).inserted else { continue }
            let count = personal.counts[key] ?? 0, kept = personal.kept.contains(key)
            guard kept || count >= PersonalCompletionIndex.minimumCount else { continue }
            ranked.append((Promotion(word: word, isAddition: isAddition), count, kept, order))
        }
        ranked.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.kept != rhs.kept { return lhs.kept }
            return lhs.order < rhs.order
        }
        return ranked.prefix(limit).map(\.promotion)
    }
}
