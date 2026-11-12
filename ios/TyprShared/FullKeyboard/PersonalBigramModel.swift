import Foundation

/// Owner-approved personal next-word layer: aggregate `previous → follower` counts only.
/// No sentence, sequence, timestamp, app/host identity or language guess is stored.
///
/// Follower counts and the discounted backoff are translated from AVGVSTVS96/iikb
/// `Correction/TypingMemory.swift` and `Correction/LanguageModel.swift` at 09a2e9c
/// (MIT, © 2026 Bassim Shahidy). Typr adds fixed caps, saturated counts, deterministic
/// event-count halving and all-reference deletion; trust/settlement lives in the session.
nonisolated struct PersonalBigramModel: Codable, Equatable, Sendable {
    /// Total `previous → follower` pair types.
    static let pairLimit = 512
    /// Followers retained per previous word.
    static let followerLimit = 8
    /// Conservative JSON bound of this section, inside the 256 KiB learning file.
    static let maximumBytes = 64 * 1024
    /// Every 256th valid pair event halves all counts first (integer division, zeros removed).
    static let ageingInterval = 256
    /// Counts saturate here, so one row can never dominate without bound.
    static let countLimit = 255
    /// A follower absent from every selected corpus pack (or a suppressed stock name) needs this
    /// many trusted observations before it may be offered or reranked: one sighting is chance.
    static let novelFollowerMinimum = 2
    /// Absolute discount and Witten–Bell trust, as in iikb's `LanguageModel`.
    static let discount = 0.5

    private(set) var following: [String: [String: Int]] = [:]
    /// Valid pair events since the last halving (0..<ageingInterval).
    private(set) var updates = 0

    /// Letters only (no apostrophes, digits or spaces), 1–32 characters, ≤128 UTF-8 bytes,
    /// lowercase NFC. ä/ö/ü/ß stay distinct from a/o/u/ss.
    static func validWord(_ word: String) -> Bool {
        (1...32).contains(word.count) && word.utf8.count <= 128 && word.allSatisfy(\.isLetter)
            && word == PersonalLexiconSnapshot.normalize(word)
    }

    var pairCount: Int { following.values.reduce(0) { $0 + $1.count } }
    /// Every word named by a pair (either side); for deletion UI, never the associations.
    var words: Set<String> { Set(following.keys).union(following.values.flatMap(\.keys)) }

    /// Conservative JSON bound: every UTF-8 byte may need a six-byte escape; quotes,
    /// separators, three-digit counts and the envelope included. Not allocator/RSS bytes.
    var encodedByteBound: Int {
        128 + following.reduce(0) { total, row in
            total + 6 * row.key.utf8.count + 8
                + row.value.reduce(0) { $0 + 6 * $1.key.utf8.count + 16 }
        }
    }

    var isValid: Bool {
        (0..<Self.ageingInterval).contains(updates) && pairCount <= Self.pairLimit
            && encodedByteBound <= Self.maximumBytes && following.allSatisfy { previous, row in
                Self.validWord(previous) && !row.isEmpty && row.count <= Self.followerLimit
                    && row.allSatisfy { Self.validWord($0.key) && (1...Self.countLimit).contains($0.value) }
            }
    }

    /// One trusted adjacent pair. Work per call is bounded: one halving pass over ≤512 edges
    /// at most every 256 events, then ≤3 evictions (one new row and edge) of ≤513-edge scans.
    mutating func record(_ word: String, after previous: String) {
        let word = PersonalLexiconSnapshot.normalize(word), previous = PersonalLexiconSnapshot.normalize(previous)
        guard Self.validWord(word), Self.validWord(previous) else { return }
        // Event-count ageing is deterministic across clocks, restarts and devices.
        // Keeps and rejected corrections are separate and never age.
        updates += 1
        if updates == Self.ageingInterval {
            updates = 0
            for context in following.keys.sorted() {
                let aged = following[context, default: [:]].compactMapValues { $0 / 2 > 0 ? $0 / 2 : nil }
                following[context] = aged.isEmpty ? nil : aged
            }
        }
        following[previous, default: [:]][word] = min(Self.countLimit, (following[previous]?[word] ?? 0) + 1)
        // The just-recorded pair is spared, so a recent follower can replace a stale one
        // instead of losing every tie forever to lexically earlier words.
        if let row = following[previous], row.count > Self.followerLimit,
           let victim = Self.weakest(row, sparing: word) {
            following[previous]?.removeValue(forKey: victim)
        }
        while pairCount > Self.pairLimit || encodedByteBound > Self.maximumBytes,
              dropWeakest(sparing: (previous, word)) {}
    }

    /// Lowest count, then lexically greatest follower.
    private static func weakest(_ row: [String: Int], sparing: String? = nil) -> String? {
        var victim: (word: String, count: Int)?
        for (word, count) in row where word != sparing {
            if let current = victim, count > current.count || (count == current.count && word < current.word) { continue }
            victim = (word, count)
        }
        return victim?.word
    }

    /// Removes the globally weakest edge: lowest count, then lexically greatest context,
    /// then lexically greatest follower. Empty rows disappear. Bounded by ≤513 edges.
    @discardableResult
    mutating func dropWeakest(sparing: (previous: String, word: String)? = nil) -> Bool {
        var victim: (previous: String, word: String, count: Int)?
        for (previous, row) in following {
            for (word, count) in row {
                if let sparing, sparing.previous == previous, sparing.word == word { continue }
                if let current = victim {
                    if count > current.count { continue }
                    if count == current.count {
                        if previous < current.previous { continue }
                        if previous == current.previous && word < current.word { continue }
                    }
                }
                victim = (previous, word, count)
            }
        }
        guard let victim else { return false }
        following[victim.previous]?.removeValue(forKey: victim.word)
        if following[victim.previous]?.isEmpty == true { following.removeValue(forKey: victim.previous) }
        return true
    }

    /// Deleting a word removes its outgoing row and every incoming reference.
    mutating func purge(_ word: String) {
        let word = PersonalLexiconSnapshot.normalize(word)
        following.removeValue(forKey: word)
        for context in following.keys.sorted() {
            following[context]?.removeValue(forKey: word)
            if following[context]?.isEmpty == true { following.removeValue(forKey: context) }
        }
    }

    func followers(after context: String?) -> [String: Int] {
        context.flatMap { following[PersonalLexiconSnapshot.normalize($0)] } ?? [:]
    }

    /// For a retained row with N total observations, T followers and count c:
    /// `P(w|h) = (max(c − .5, 0) + 1.5·T·P_corpus(w|h)) / (N + T)`.
    /// An unknown context returns the corpus probability exactly. No language partition,
    /// so genuine DE/EN code-switches keep their personal evidence.
    func probability(_ word: String, after context: String?, corpus: Double) -> Double {
        let row = followers(after: context)
        guard !row.isEmpty else { return corpus }
        let n = Double(row.values.reduce(0, +)), t = Double(row.count)
        let c = Double(row[PersonalLexiconSnapshot.normalize(word)] ?? 0)
        return (max(c - Self.discount, 0) + (1 + Self.discount) * t * corpus) / (n + t)
    }

    /// The multiplier `1.5·T/(N+T)` applied to every non-follower's corpus probability
    /// (1 for an unknown context). Exact top-k search scales its stopping bound by it.
    func backoffWeight(after context: String?) -> Double {
        let row = followers(after: context)
        guard !row.isEmpty else { return 1 }
        let n = Double(row.values.reduce(0, +)), t = Double(row.count)
        return (1 + Self.discount) * t / (n + t)
    }
}
