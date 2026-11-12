import Foundation

/// Corpus-only discounted backoff, inspired by iikb LanguageModel/Corrector at
/// 09a2e9cdfbe851adff6c4646333c0a3f74ba8765 (MIT, © 2026 Bassim Shahidy).
/// TBG1, bilingual weighting and all policy/bounds are Typr's. No personal history.
nonisolated struct KeyboardContextModel: Sendable {
    static let bos = "<s>"
    static let suppressed: Set<String> = ["tom", "mary", "maria", "john"]
    static let maxPackBytes = 1_048_576
    static let maxWords = 8_001
    static let candidateLimit = 32
    static let contextLimit = 256
    static let contextByteLimit = 2_048

    nonisolated struct Pack: Sendable {
        let data: Data
        let language: String
        let wordCount: Int
        let total: Double
        let edgeOffset: Int
        let stringOffset: Int
        let edgeCount: Int
        /// Only persistent derived index: two bytes per lexical word.
        let base: [UInt16]
        var residentPayloadBytes: Int { data.count + base.count * 2 }

        init?(data input: Data) {
            // Rebase sliced Data before any indexed access.
            let data = input.startIndex == 0 ? input : Data(input)
            guard data.count >= 64, data.count <= KeyboardContextModel.maxPackBytes else { return nil }
            func u(_ p: Int, _ n: Int = 4) -> UInt64 {
                (0..<n).reduce(0) { $0 | UInt64(data[p + $1]) << ($1 * 8) }
            }
            let v = Int(u(12)), e = Int(u(16)), eo = Int(u(24)), so = Int(u(28))
            let total = u(36, 8), k = Int(u(52, 2)), minimum = u(54, 2)
            guard Array(data.prefix(4)) == Array("TBG1".utf8), u(4, 2) == 1, u(6, 2) == 64,
                  let lang = String(data: data[8..<10], encoding: .utf8), ["de", "en"].contains(lang),
                  u(10, 2) == 0, u(60) == 0, (2...KeyboardContextModel.maxWords).contains(v),
                  (1...16).contains(k), minimum > 0, e <= v * k,
                  u(20) == 64, eo == 64 + v * 20, so == eo + e * 8,
                  so < data.count, Int(u(32)) == data.count,
                  total > 0, total <= 1_000_000_000_000, u(44) == 0x3f000000,
                  u(48) == UInt64(v - 1), Self.crc32(data.dropFirst(64)) == UInt32(u(56)) else { return nil }
            func string(_ offset: Int) -> String? {
                let start = so + offset
                guard start >= so, start < data.count,
                      let end = data[start..<min(data.count, start + 129)].firstIndex(of: 0), end > start,
                      let s = String(data: data[start..<end], encoding: .utf8) else { return nil }
                return s
            }
            var previous: String?
            var sum: UInt64 = 0
            var firstExpected = 0
            for i in 0..<v {
                let p = 64 + i * 20
                guard let key = string(Int(u(p))), let display = string(Int(u(p + 4))),
                      i == 0 ? (key == KeyboardContextModel.bos && display == key && u(p + 8) == 0)
                        : (Self.validWord(key, apostrophes: lang == "en") && Self.validWord(display, apostrophes: lang == "en")
                           && KeyboardContextModel.key(key) == key && KeyboardContextModel.key(display) == key
                           && u(p + 8) > 0),
                      i < 2 || previous!.utf8.lexicographicallyPrecedes(key.utf8) else { return nil }
                previous = key
                sum += u(p + 8)
                let first = Int(u(p + 12))
                let end = i + 1 < v ? Int(u(p + 32)) : e
                guard first == firstExpected, first <= end, end <= e, end - first <= k else { return nil }
                firstExpected = end
                var rowSum: UInt64 = 0
                var lastCount: UInt64 = .max
                var lastID = -1
                var seen: Set<Int> = []
                for j in first..<end {
                    let q = eo + j * 8, id = Int(u(q, 2)), count = u(q + 4)
                    guard id > 0, id < v, u(q + 2, 2) == 0, count >= minimum,
                          seen.insert(id).inserted, count < lastCount || (count == lastCount && id > lastID) else { return nil }
                    rowSum += count
                    lastCount = count; lastID = id
                }
                guard rowSum <= u(p + 16) else { return nil }
            }
            guard sum == total else { return nil }
            self.data = data; language = lang; wordCount = v; self.total = Double(total)
            edgeOffset = eo; stringOffset = so; edgeCount = e
            base = (1..<v).map { UInt16($0) }.sorted {
                let a = u(64 + Int($0) * 20 + 8), b = u(64 + Int($1) * 20 + 8)
                return a == b ? $0 < $1 : a > b
            }
        }

        private static func validWord(_ s: String, apostrophes: Bool) -> Bool {
            guard s.count <= 32, s.utf8.count <= 128, s.first?.isLetter == true,
                  s.last?.isLetter == true else { return false }
            let characters = Array(s)
            for (i, ch) in characters.enumerated() where !ch.isLetter {
                guard apostrophes, ch == "'", i > 0, i + 1 < characters.count,
                      characters[i - 1].isLetter, characters[i + 1].isLetter else { return false }
            }
            return true
        }

        private static func crc32(_ data: Data.SubSequence) -> UInt32 {
            var crc: UInt32 = 0xffffffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
            }
            return crc ^ 0xffffffff
        }

        private func u(_ p: Int, _ n: Int = 4) -> Int {
            (0..<n).reduce(0) { $0 | Int(data[p + $1]) << ($1 * 8) }
        }
        func word(_ id: Int, display: Bool = false) -> String {
            let start = stringOffset + u(64 + id * 20 + (display ? 4 : 0))
            let end = data[start..<min(data.count, start + 129)].firstIndex(of: 0)!
            return String(data: data[start..<end], encoding: .utf8)!
        }
        func id(_ key: String) -> Int? {
            if key == KeyboardContextModel.bos { return 0 }
            var lo = 1, hi = wordCount
            while lo < hi {
                let mid = (lo + hi) / 2, w = word(mid)
                if w.utf8.lexicographicallyPrecedes(key.utf8) { lo = mid + 1 } else { hi = mid }
            }
            return lo < wordCount && word(lo) == key ? lo : nil
        }
        func count(_ key: String) -> Double { id(key).map { Double(u(64 + $0 * 20 + 8)) } ?? 0 }
        func p0(_ id: Int) -> Double { (Double(u(64 + id * 20 + 8)) + 0.5) / (total + 0.5 * Double(wordCount - 1)) }
        struct Distribution {
            var lambda = 1.0
            var boosts: [(id: Int, probability: Double)] = []
        }
        func distribution(_ context: String?) -> Distribution {
            guard let context, let id = id(context) else { return Distribution() }
            let p = 64 + id * 20, total = u(p + 16)
            guard total > 0 else { return Distribution() }
            let first = u(p + 12), end = id + 1 < wordCount ? u(p + 32) : edgeCount
            var result = Distribution()
            for j in first..<end {
                let q = edgeOffset + j * 8
                result.boosts.append((u(q, 2), (Double(u(q + 4)) - 0.5) / Double(total)))
            }
            result.lambda = 1 - result.boosts.reduce(0) { $0 + $1.probability }
            return result
        }
        func probability(_ key: String, distribution d: Distribution) -> Double {
            guard let id = id(key), id > 0 else { return 0 }
            return d.lambda * p0(id) + (d.boosts.first { $0.id == id }?.probability ?? 0)
        }
        func probability(_ key: String, after context: String?) -> Double {
            probability(key, distribution: distribution(context))
        }
    }

    let de: Pack?
    let en: Pack?
    let unionSize: Int
    var residentPayloadBytes: Int { (de?.residentPayloadBytes ?? 0) + (en?.residentPayloadBytes ?? 0) }

    init?(de: Pack?, en: Pack?) {
        guard de != nil || en != nil, de == nil || de?.language == "de", en == nil || en?.language == "en",
              (de?.data.count ?? 0) + (en?.data.count ?? 0) <= Self.maxPackBytes else { return nil }
        self.de = de; self.en = en
        var a = 1, b = 1, count = 0
        while a < (de?.wordCount ?? 1) || b < (en?.wordCount ?? 1) {
            let x = a < (de?.wordCount ?? 1) ? de!.word(a) : nil
            let y = b < (en?.wordCount ?? 1) ? en!.word(b) : nil
            if let x, let y {
                if x == y { a += 1; b += 1 }
                else if x.utf8.lexicographicallyPrecedes(y.utf8) { a += 1 } else { b += 1 }
            } else if x != nil { a += 1 } else { b += 1 }
            count += 1
        }
        unionSize = count
    }

    static func key(_ word: String) -> String { word.lowercased().precomposedStringWithCanonicalMapping }
    func logRatio(_ word: String) -> Double {
        let key = Self.key(word), d = de?.count(key) ?? 0, e = en?.count(key) ?? 0
        guard key != Self.bos, d > 0 || e > 0, let de, let en else { return 0 }
        let qd = (d + 0.5) / (de.total + 0.5 * Double(unionSize + 1))
        let qe = (e + 0.5) / (en.total + 0.5 * Double(unionSize + 1))
        return log(qd / qe)
    }
    func evidence(_ word: String) -> Double { min(3, max(-3, logRatio(word))) }
    struct State: Sendable {
        private(set) var value = 0.0
        var weightDE: Double { 0.05 + 0.90 / (1 + exp(-value)) }
        mutating func consume(_ word: String, model: KeyboardContextModel) {
            value = min(6, max(-6, 0.75 * value + model.evidence(word)))
        }
        mutating func sentenceBoundary() { value *= 0.5 }
    }

    struct Suggestion: Equatable, Sendable {
        let key: String
        let display: String
        let probability: Double
    }

    /// Exact mixture top-three: all boosted followers, then descending unigram scans.
    /// Strict bound preserves ties. At most 16,000 lexical keys and 32 boosts visited;
    /// the seen set is request-local, never a history/cache. No fixed top-16 approximation.
    func suggestions(after context: String?, weightDE: Double, german: Bool = true, english: Bool = true,
                     suppress: Set<String> = Self.suppressed) -> [Suggestion] {
        guard (!german || de != nil), (!english || en != nil), german || english else { return [] }
        let d = german ? de : nil, e = english ? en : nil
        let a = german ? (english ? min(1, max(0, weightDE.isFinite ? weightDE : 0.5)) : 1) : 0
        let dd = d?.distribution(context) ?? Pack.Distribution(), ed = e?.distribution(context) ?? Pack.Distribution()
        var seen: Set<String> = [], best: [Suggestion] = []
        func visit(_ key: String) {
            guard !suppress.contains(key), seen.insert(key).inserted else { return }
            let dp = a * (d?.probability(key, distribution: dd) ?? 0)
            let ep = (1 - a) * (e?.probability(key, distribution: ed) ?? 0)
            let pack = dp >= ep && d?.id(key) != nil ? d! : e!
            let id = pack.id(key)!
            best.append(Suggestion(key: key, display: pack.word(id, display: true), probability: dp + ep))
            best.sort { $0.probability == $1.probability ? $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) : $0.probability > $1.probability }
            if best.count > 3 { best.removeLast() }
        }
        for boost in dd.boosts { visit(d!.word(boost.id)) }
        for boost in ed.boosts { visit(e!.word(boost.id)) }
        var pos = 0
        while pos < max(d?.base.count ?? 0, e?.base.count ?? 0) {
            if let d, pos < d.base.count { visit(d.word(Int(d.base[pos]))) }
            if let e, pos < e.base.count { visit(e.word(Int(e.base[pos]))) }
            pos += 1
            let db = d.flatMap { pos < $0.base.count ? $0.p0(Int($0.base[pos])) : nil } ?? 0
            let eb = e.flatMap { pos < $0.base.count ? $0.p0(Int($0.base[pos])) : nil } ?? 0
            if best.count == 3, best[2].probability > a * dd.lambda * db + (1 - a) * ed.lambda * eb { break }
        }
        return best
    }

    func probability(_ word: String, after context: String?, weightDE: Double, german: Bool, english: Bool) -> Double {
        guard (!german || de != nil), (!english || en != nil) else { return 0 }
        let a = german ? (english ? weightDE : 1) : 0
        let key = Self.key(word)
        return a * (german ? de?.probability(key, after: context) ?? 0 : 0)
            + (1 - a) * (english ? en?.probability(key, after: context) ?? 0 : 0)
    }

    struct Context: Sendable {
        var state = State()
        var previous: String?
        var canPredict = false
    }

    /// Recompute from a short RAM-only suffix every request: edits cannot double-consume
    /// evidence and field changes cannot retain a posterior. Discard a clipped first word.
    /// Unknown/numeric/identifier barriers are NOT BOS; sentence punctuation is BOS.
    func context(before input: String?, currentToken: String?) -> Context {
        guard let input else { return Context() }
        let bytes = input.utf8.suffix(Self.contextByteLimit + 1)
        let tail = String(decoding: bytes.suffix(Self.contextByteLimit), as: UTF8.self).suffix(Self.contextLimit + 1)
        // A caller (including the suggestion worker) may already have clipped to
        // exactly these caps. Conservatively discard its potentially partial first word.
        let clipped = bytes.count >= Self.contextByteLimit || tail.count >= Self.contextLimit
        var suffix = String(tail.suffix(Self.contextLimit))
        if clipped { suffix = String(suffix.drop(while: { !$0.isWhitespace && !".!?…".contains($0) })) }
        if let token = currentToken, suffix.hasSuffix(token) { suffix.removeLast(token.count) }
        var result = Context(), token = ""
        var atSentenceBoundary = false
        func flush() {
            guard !token.isEmpty else { return }
            if token.count <= 32, token.utf8.count <= 128, token.first?.isLetter == true,
               token.last?.isLetter == true, token.allSatisfy({ $0.isLetter || $0 == "'" }) {
                let key = Self.key(token)
                result.state.consume(key, model: self); result.previous = key
                result.canPredict = true; atSentenceBoundary = false
            } else { result.previous = nil; result.canPredict = false }
            token = ""
        }
        for segment in suffix.replacingOccurrences(of: "’", with: "'").split(whereSeparator: { $0.isWhitespace }) {
            // Non-prose spans are barriers, including their punctuation (not a fake BOS
            // inside a URL/email/identifier/number). Ordinary comma/quotes separate words.
            if segment.contains(where: { $0.isNumber || "@/:_#-\\\\".contains($0) }) {
                result.previous = nil; result.canPredict = false
                continue
            }
            for ch in segment {
                if ch.isLetter || ch == "'" { token.append(ch) }
                else {
                    flush()
                    if ".!?…".contains(ch) {
                        if !atSentenceBoundary { result.state.sentenceBoundary() }
                        result.previous = Self.bos; result.canPredict = true; atSentenceBoundary = true
                    }
                }
            }
            flush()
        }
        // At an empty/unknown document start do not pretend a sentence boundary was seen.
        return result
    }

    /// Bounded additive natural-log term over an existing ordered candidate pool.
    /// Original rank is the base score; context contributes [-1.5, 0]. Literal,
    /// automatic and explicit-revert slots are protected by the caller.
    func rerank(_ candidates: [String], context: Context, german: Bool, english: Bool) -> [String] {
        let pool = Array(candidates.prefix(Self.candidateLimit))
        guard context.canPredict else { return pool }
        return pool.enumerated().map { i, word in
            let p = probability(word, after: context.previous, weightDE: context.state.weightDE, german: german, english: english)
            return (word, -0.2 * Double(i) + 0.10 * max(-15, log(max(p, exp(-15)))))
        }.sorted { $0.1 == $1.1 ? $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) : $0.1 > $1.1 }.map(\.0)
    }
}

/// Shared immutable maps are prepared off the key path; unavailable selected data
/// abstains rather than silently falling back to the other language.
@MainActor
final class KeyboardContextResources {
    static let bundled = KeyboardContextResources(bundle: .main)
    private(set) var model: KeyboardContextModel?
    private let bundle: Bundle?
    private var task: Task<Void, Never>?
    private var ready: (@MainActor () -> Void)?
    init(model: KeyboardContextModel?) { self.model = model; bundle = nil }
    init(bundle: Bundle) { self.bundle = bundle }
    func prepare(onReady: @escaping @MainActor () -> Void) {
        guard model == nil, let bundle else { return }
        ready = onReady
        guard task == nil else { return }
        let urls = ["de", "en"].map { bundle.url(forResource: "keyboard-\($0)", withExtension: "tbg", subdirectory: "WordData") }
        task = Task { [weak self] in
            let model = await Task.detached(priority: .utility) {
                let packs = urls.map { url in
                    url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }.flatMap(KeyboardContextModel.Pack.init)
                }
                return KeyboardContextModel(de: packs[0], en: packs[1])
            }.value
            guard let self else { return }
            self.model = model
            let callback = self.ready; self.ready = nil
            callback?()
        }
    }
}
