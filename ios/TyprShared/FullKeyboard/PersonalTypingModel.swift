import Foundation

/// Aggregates only: no raw taps, word order or surrounding text are retained.
@MainActor
final class PersonalTypingModel {
    nonisolated struct TouchStats: Codable, Equatable, Sendable {
        var n = 0
        var meanX = 0.0
        var meanY = 0.0
        var varianceX = 0.0
        var varianceY = 0.0

        // Pitch-normalized sufficient statistics adapted from AVGVSTVS96/iikb
        // Packages/KeyboardModules/Sources/KeyboardCore/Correction/TouchModel.swift (MIT).
        mutating func update(x: Double, y: Double) {
            n = min(256, n + 1)
            let weight = max(1 / Double(n), 1 / 64.0)
            let dx = x - meanX, dy = y - meanY
            meanX += weight * dx
            meanY += weight * dy
            varianceX = (1 - weight) * (varianceX + weight * dx * dx)
            varianceY = (1 - weight) * (varianceY + weight * dy * dy)
        }

        var calibration: SpatialTouchCalibration.Key {
            let shrink = Double(n) / Double(n + 20)
            let prior = SpatialTouchCalibration.staticSigma * SpatialTouchCalibration.staticSigma
            let raw = SpatialTouchCalibration.Key(
                offsetX: shrink * meanX, offsetY: shrink * meanY,
                sigmaX: sqrt(shrink * varianceX + (1 - shrink) * prior),
                sigmaY: sqrt(shrink * varianceY + (1 - shrink) * prior))
            // Reuse the decoder contract's bounds for summaries as well as inference.
            return SpatialTouchCalibration(keys: ["a": raw]).keys["a"] ?? raw
        }

        var isValid: Bool {
            (1...256).contains(n) && meanX.isFinite && meanY.isFinite
                && abs(meanX) <= 1 && abs(meanY) <= 1
                && varianceX.isFinite && varianceY.isFinite
                && (0...1).contains(varianceX) && (0...1).contains(varianceY)
        }
    }

    nonisolated struct LayoutStats: Codable, Equatable, Sendable {
        var signature: KeyboardLayoutSignature
        var lastUpdated: Date
        var keys: [String: TouchStats] = [:]
    }

    nonisolated struct WordCount: Codable, Equatable, Sendable {
        var count: Int
        var lastUpdated: Date
    }

    nonisolated struct State: Codable, Equatable, Sendable {
        var schemaVersion = 1
        var layouts: [String: LayoutStats] = [:]
        var kept: [String: Date] = [:]
        var counts: [String: WordCount] = [:]
        var rejected: [RejectedCorrection] = []

        func validated() -> State? {
            guard schemaVersion == 1, layouts.count <= 4,
                  Set(kept.keys).union(counts.keys).count <= 2000, rejected.count <= 512,
                  Set(rejected).count == rejected.count else { return nil }
            for (id, layout) in layouts {
                let signature = layout.signature
                guard id == signature.id, ["portrait", "landscape"].contains(signature.orientation),
                      (8...4096).contains(signature.widthBucket), signature.widthBucket % 8 == 0,
                      layout.lastUpdated.timeIntervalSinceReferenceDate.isFinite,
                      !layout.keys.isEmpty, layout.keys.count <= 26 else { return nil }
                for (key, stats) in layout.keys {
                    guard key.count == 1, key.utf8.count == 1,
                          key.utf8.allSatisfy({ (97...122).contains($0) }), stats.isValid else { return nil }
                }
            }
            guard kept.allSatisfy({ Self.validWord($0.key) && $0.value.timeIntervalSinceReferenceDate.isFinite }),
                  counts.allSatisfy({ Self.validWord($0.key) && (1...10_000).contains($0.value.count)
                      && $0.value.lastUpdated.timeIntervalSinceReferenceDate.isFinite }),
                  rejected.allSatisfy({ Self.validWord($0.typed) && Self.validWord($0.replacement) }) else { return nil }
            return self
        }

        static func validWord(_ word: String) -> Bool {
            (2...32).contains(word.count) && word.utf8.count <= 256
                && word.allSatisfy(\.isLetter) && word == PersonalLexiconSnapshot.normalize(word)
        }

        /// One shared word budget. Evict unkept counts first, then the oldest keep
        /// (including its count), so retained protection always has priority.
        mutating func enforceWordLimit() {
            while Set(kept.keys).union(counts.keys).count > 2000 {
                if let victim = counts.filter({ kept[$0.key] == nil }).min(by: {
                    if $0.value.count != $1.value.count { return $0.value.count < $1.value.count }
                    return $0.value.lastUpdated == $1.value.lastUpdated ? $0.key < $1.key
                        : $0.value.lastUpdated < $1.value.lastUpdated
                })?.key {
                    counts.removeValue(forKey: victim)
                } else if let victim = kept.min(by: {
                    $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
                })?.key {
                    kept.removeValue(forKey: victim)
                    counts.removeValue(forKey: victim)
                }
            }
        }

        /// Used only to enforce the encoded byte ceiling. Touch statistics are never evicted here.
        mutating func dropOldestLexiconEntries(_ limit: Int) -> Bool {
            guard limit > 0 else { return false }
            enum Entry { case kept(String), counted(String) }
            var entries: [(Date, String, Entry)] = kept.map { ($0.value, "k:" + $0.key, .kept($0.key)) }
            entries += counts.map { ($0.value.lastUpdated, "c:" + $0.key, .counted($0.key)) }
            let oldest = entries.sorted {
                let aKept = $0.1.hasPrefix("k:"), bKept = $1.1.hasPrefix("k:")
                if aKept != bKept { return !aKept }
                return $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0
            }.prefix(limit)
            for entry in oldest {
                switch entry.2 {
                case .kept(let word): kept.removeValue(forKey: word)
                case .counted(let word): counts.removeValue(forKey: word)
                }
            }
            let pairsToDrop = min(rejected.count, limit - oldest.count)
            if pairsToDrop > 0 { rejected.removeFirst(pairsToDrop) }
            return !oldest.isEmpty || pairsToDrop > 0
        }
    }

    nonisolated struct LearnOutcome: Equatable, Sendable {
        var accepted = 0
        var rejected: [TouchLabelRejection: Int] = [:]
    }

    nonisolated struct KeySummary: Equatable, Sendable {
        let letter: String
        let n: Int
        let offsetX: Double
        let offsetY: Double
        let sigmaX: Double
        let sigmaY: Double
        var isCalibrated: Bool { n >= 20 }
    }

    nonisolated struct LayoutSummary: Equatable, Sendable {
        let signature: KeyboardLayoutSignature
        let lastUpdated: Date
        let keys: [KeySummary]
    }

    nonisolated struct Summary: Equatable, Sendable {
        let layouts: [LayoutSummary]
        let keptWords: Int
        let countedWords: Int
        let wordCountTotal: Int
        let rejectedCorrections: Int
        var effectiveTouchCount: Int { layouts.flatMap(\.keys).reduce(0) { $0 + $1.n } }
    }

    private(set) var state: State
    var isLearningEnabled: Bool { didSet { cachedLexicon = nil } }
    private var cachedLexicon: PersonalLexiconSnapshot?
    private let now: () -> Date

    init(state: State = State(), isLearningEnabled: Bool = true, now: @escaping () -> Date = Date.init) {
        self.state = state.validated() ?? State()
        self.isLearningEnabled = isLearningEnabled
        self.now = now
    }

    @discardableResult
    func learn(_ labels: [TouchLabel], layout: KeyboardLayout, source: TouchLabelSource) -> LearnOutcome {
        guard isLearningEnabled else {
            return LearnOutcome(rejected: labels.isEmpty ? [:] : [.learningOff: labels.count])
        }
        var outcome = LearnOutcome()
        // Validate before constructing a signature (rounding a non-finite width would trap).
        let usable = layout.layer == .letters && layout.field == .text
            && layout.width.isFinite && (8...4096).contains(layout.width)
        for label in labels {
            var rejection: TouchLabelRejection?
            if !usable { rejection = .layoutMismatch }
            else if !label.point.x.isFinite || !label.point.y.isFinite { rejection = .nonFinite }
            else if !label.letter.isLetter || String(label.letter) != String(label.letter).lowercased() {
                rejection = .unknownKey
            } else if let key = layout.key(.character(String(label.letter))) {
                let pitchX = key.frame.width + layout.metrics.gap
                let pitchY = key.frame.height + layout.metrics.rowGap
                let x = Double((label.point.x - key.frame.midX) / pitchX)
                let y = Double((label.point.y - key.frame.midY) / pitchY)
                if !x.isFinite || !y.isFinite || pitchX <= 0 || pitchY <= 0 { rejection = .nonFinite }
                // The inclusive one-pitch boundary needs only a rounding tolerance.
                else if hypot(x, y) > 1 + 1e-12 { rejection = .outlier }
                else {
                    let signature = KeyboardLayoutSignature(layout)
                    if state.layouts[signature.id] == nil, state.layouts.count >= 4,
                       let oldest = state.layouts.min(by: {
                           $0.value.lastUpdated == $1.value.lastUpdated ? $0.key < $1.key : $0.value.lastUpdated < $1.value.lastUpdated
                       })?.key { state.layouts.removeValue(forKey: oldest) }
                    var stats = state.layouts[signature.id] ?? LayoutStats(signature: signature, lastUpdated: now())
                    stats.keys[String(label.letter), default: TouchStats()].update(x: x, y: y)
                    stats.lastUpdated = now()
                    state.layouts[signature.id] = stats
                    outcome.accepted += 1
                }
            } else { rejection = .unknownKey }
            if let rejection { outcome.rejected[rejection, default: 0] += 1 }
        }
        return outcome
    }

    func calibration(for layout: KeyboardLayout) -> SpatialTouchCalibration? {
        guard isLearningEnabled, layout.layer == .letters, layout.field == .text,
              layout.width.isFinite, (8...4096).contains(layout.width),
              let stats = state.layouts[KeyboardLayoutSignature(layout).id] else { return nil }
        var keys: [Character: SpatialTouchCalibration.Key] = [:]
        for (letter, value) in stats.keys where value.n >= 20 {
            if let character = letter.first, layout.key(.character(letter)) != nil { keys[character] = value.calibration }
        }
        return keys.isEmpty ? nil : SpatialTouchCalibration(keys: keys)
    }

    // Explicit keeps remain available while learning is off. Counting is a separate trusted event.
    @discardableResult
    func keep(_ word: String) -> Bool {
        let word = PersonalLexiconSnapshot.normalize(word)
        guard State.validWord(word) else { return false }
        state.kept[word] = now()
        state.enforceWordLimit()
        cachedLexicon = nil
        return true
    }

    @discardableResult
    func recordWord(_ word: String) -> Bool {
        let word = PersonalLexiconSnapshot.normalize(word)
        guard isLearningEnabled, State.validWord(word) else { return false }
        let count = min(10_000, (state.counts[word]?.count ?? 0) + 1)
        state.counts[word] = WordCount(count: count, lastUpdated: now())
        state.enforceWordLimit()
        cachedLexicon = nil
        return true
    }

    @discardableResult
    func rejectCorrection(typed: String, replacement: String) -> Bool {
        let pair = RejectedCorrection(typed: typed, replacement: replacement)
        guard State.validWord(pair.typed), State.validWord(pair.replacement) else { return false }
        if !state.rejected.contains(pair) {
            state.rejected.append(pair)
            if state.rejected.count > 512 { state.rejected.removeFirst() }
            cachedLexicon = nil
        }
        return true
    }

    func forgetCount(_ word: String) {
        state.counts.removeValue(forKey: PersonalLexiconSnapshot.normalize(word))
        cachedLexicon = nil
    }

    var lexicon: PersonalLexiconSnapshot {
        if let cachedLexicon { return cachedLexicon }
        let snapshot = PersonalLexiconSnapshot(kept: Set(state.kept.keys),
            counts: isLearningEnabled ? state.counts.mapValues(\.count) : [:], rejected: Set(state.rejected))
        cachedLexicon = snapshot
        return snapshot
    }

    var summary: Summary { Self.summarize(state) }

    static func summarize(_ state: State) -> Summary {
        let layouts = state.layouts.values.sorted { $0.signature.id < $1.signature.id }.map { layout in
            LayoutSummary(signature: layout.signature, lastUpdated: layout.lastUpdated,
                keys: layout.keys.sorted { $0.key < $1.key }.map { letter, stats in
                    let key = stats.calibration
                    return KeySummary(letter: letter, n: stats.n, offsetX: key.offsetX, offsetY: key.offsetY,
                                      sigmaX: key.sigmaX, sigmaY: key.sigmaY)
                })
        }
        return Summary(layouts: layouts, keptWords: state.kept.count, countedWords: state.counts.count,
            wordCountTotal: state.counts.values.reduce(0) { $0 + $1.count }, rejectedCorrections: state.rejected.count)
    }

    func reset() { state = State(); cachedLexicon = nil }
}
