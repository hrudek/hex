import Foundation

/// Aggregate word pairs only, not a sequence, app history or language posterior.
/// Follower counts / discounted backoff translated from AVGVSTVS96/iikb
/// Correction/{TypingMemory,LanguageModel}.swift at 09a2e9c (MIT, © 2026 Bassim Shahidy).
nonisolated struct PersonalBigramModel: Codable, Equatable, Sendable {
    static let pairLimit = 512
    static let followerLimit = 8
    static let maximumBytes = 64 * 1024
    static let ageingInterval = 256
    static let countLimit = 255
    private(set) var following: [String: [String: Int]] = [:]
    private(set) var updates = 0

    static func validWord(_ word: String) -> Bool {
        (1...32).contains(word.count) && word.utf8.count <= 128 && word.allSatisfy(\.isLetter)
            && word == PersonalLexiconSnapshot.normalize(word)
    }
    var pairCount: Int { following.values.reduce(0) { $0 + $1.count } }
    var words: Set<String> { Set(following.keys).union(following.values.flatMap(\.keys)) }
    /// Conservative JSON bound: every UTF-8 byte may require six escape bytes;
    /// punctuation, counts, keys and epoch overhead included. Not allocator/RSS bytes.
    var encodedByteBound: Int {
        128 + following.reduce(0) { total, row in
            total + 6 * row.key.utf8.count + 8
                + row.value.reduce(0) { $0 + 6 * $1.key.utf8.count + 16 }
        }
    }
    var isValid: Bool {
        (0..<Self.ageingInterval).contains(updates) && pairCount <= Self.pairLimit
            && encodedByteBound <= Self.maximumBytes && following.allSatisfy { h, row in
                Self.validWord(h) && !row.isEmpty && row.count <= Self.followerLimit
                    && row.allSatisfy { Self.validWord($0.key) && (1...Self.countLimit).contains($0.value) }
            }
    }

    mutating func record(_ word: String, after previous: String) {
        let word = PersonalLexiconSnapshot.normalize(word), previous = PersonalLexiconSnapshot.normalize(previous)
        guard Self.validWord(word), Self.validWord(previous) else { return }
        // Event-count ageing is deterministic across clocks/restarts; keeps/rejections never age.
        updates += 1
        if updates == Self.ageingInterval {
            updates = 0
            for h in following.keys.sorted() {
                following[h] = following[h]?.compactMapValues { $0 / 2 > 0 ? $0 / 2 : nil }
                if following[h]?.isEmpty == true { following.removeValue(forKey: h) }
            }
        }
        following[previous, default: [:]][word] = min(Self.countLimit, (following[previous]?[word] ?? 0) + 1)
        if let row = following[previous], row.count > Self.followerLimit,
           let victim = Self.rarest(row) { following[previous]?.removeValue(forKey: victim) }
        // At most 513 edges; each bounded scan removes one edge (including empty rows).
        while pairCount > Self.pairLimit || encodedByteBound > Self.maximumBytes { dropRarest() }
    }

    private static func rarest(_ row: [String: Int]) -> String? {
        row.keys.min { row[$0] == row[$1] ? $0 > $1 : row[$0]! < row[$1]! }
    }
    @discardableResult
    mutating func dropRarest() -> Bool {
        var victim: (h: String, w: String, n: Int)?
        for (h, row) in following {
            for (w, n) in row {
                if victim == nil || n < victim!.n || (n == victim!.n && (h > victim!.h || (h == victim!.h && w > victim!.w))) {
                    victim = (h, w, n)
                }
            }
        }
        guard let victim else { return false }
        following[victim.h]?.removeValue(forKey: victim.w)
        if following[victim.h]?.isEmpty == true { following.removeValue(forKey: victim.h) }
        return true
    }
    mutating func purge(_ word: String) {
        let word = PersonalLexiconSnapshot.normalize(word)
        following.removeValue(forKey: word)
        for h in following.keys.sorted() {
            following[h]?.removeValue(forKey: word)
            if following[h]?.isEmpty == true { following.removeValue(forKey: h) }
        }
    }

    func followers(after context: String?) -> [String: Int] {
        context.flatMap { following[PersonalLexiconSnapshot.normalize($0)] } ?? [:]
    }
    /// P = (max(c-.5,0) + 1.5*T*P_corpus) / (N+T).
    /// Unseen contexts back off exactly. No language partition suppresses genuine code switches.
    func probability(_ word: String, after context: String?, corpus: Double) -> Double {
        let row = followers(after: context)
        guard !row.isEmpty else { return corpus }
        let n = Double(row.values.reduce(0, +)), t = Double(row.count)
        let c = Double(row[PersonalLexiconSnapshot.normalize(word)] ?? 0)
        return (max(c - 0.5, 0) + 1.5 * t * corpus) / (n + t)
    }
}
