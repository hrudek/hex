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
        var covarianceXY = 0.0

        private enum CodingKeys: String, CodingKey { case n, meanX, meanY, varianceX, varianceY, covarianceXY }
        init(n: Int = 0, meanX: Double = 0, meanY: Double = 0,
             varianceX: Double = 0, varianceY: Double = 0, covarianceXY: Double = 0) {
            self.n = n; self.meanX = meanX; self.meanY = meanY
            self.varianceX = varianceX; self.varianceY = varianceY; self.covarianceXY = covarianceXY
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            n = try c.decode(Int.self, forKey: .n)
            meanX = try c.decode(Double.self, forKey: .meanX)
            meanY = try c.decode(Double.self, forKey: .meanY)
            varianceX = try c.decode(Double.self, forKey: .varianceX)
            varianceY = try c.decode(Double.self, forKey: .varianceY)
            // Schema 1 had diagonal statistics only; missing covariance means zero.
            covarianceXY = try c.decodeIfPresent(Double.self, forKey: .covarianceXY) ?? 0
        }

        // Pitch-normalized sufficient statistics adapted from AVGVSTVS96/iikb
        // Packages/KeyboardModules/Sources/KeyboardCore/Correction/TouchModel.swift (MIT).
        mutating func update(x: Double, y: Double) {
            guard x.isFinite, y.isFinite else { return }
            // The inclusive learn gate tolerates floating-point pitch rounding only.
            let x = max(-1, min(1, x)), y = max(-1, min(1, y))
            n = min(256, n + 1)
            let weight = max(1 / Double(n), 1 / 64.0)
            let dx = x - meanX, dy = y - meanY
            meanX = max(-1, min(1, meanX + weight * dx))
            meanY = max(-1, min(1, meanY + weight * dy))
            varianceX = max(0, min(1, (1 - weight) * (varianceX + weight * dx * dx)))
            varianceY = max(0, min(1, (1 - weight) * (varianceY + weight * dy * dy)))
            let limit = sqrt(varianceX * varianceY)
            covarianceXY = max(-limit, min(limit, (1 - weight) * (covarianceXY + weight * dx * dy)))
        }

        var calibration: SpatialTouchCalibration.Key {
            let shrink = Double(n) / Double(n + 20)
            let prior = SpatialTouchCalibration.staticSigma * SpatialTouchCalibration.staticSigma
            let raw = SpatialTouchCalibration.Key(
                offsetX: shrink * meanX, offsetY: shrink * meanY,
                sigmaX: sqrt(shrink * varianceX + (1 - shrink) * prior),
                sigmaY: sqrt(shrink * varianceY + (1 - shrink) * prior),
                covarianceXY: shrink * covarianceXY)
            // Reuse the decoder contract's bounds for summaries as well as inference.
            return SpatialTouchCalibration(keys: ["a": raw]).keys["a"] ?? raw
        }

        var isValid: Bool {
            (1...256).contains(n) && meanX.isFinite && meanY.isFinite
                && abs(meanX) <= 1 && abs(meanY) <= 1
                && varianceX.isFinite && varianceY.isFinite
                && (0...1).contains(varianceX) && (0...1).contains(varianceY)
                && covarianceXY.isFinite && abs(covarianceXY) <= sqrt(varianceX * varianceY) + 1e-12
        }
    }

    nonisolated struct LayoutStats: Codable, Equatable, Sendable {
        var signature: KeyboardLayoutSignature
        var lastUpdated: Date
        var keys: [String: TouchStats] = [:]
        // Optional only for schema-1 decoding. New labels create this aggregate.
        var global: TouchStats?

        /// Within-key pooled covariance, not between-key center differences. Each key
        /// contributes at most 256 effective observations; iteration order is fixed.
        var pooled: SpatialTouchCalibration.Key {
            let prior = SpatialTouchCalibration.staticSigma * SpatialTouchCalibration.staticSigma
            var n = 20.0, xx = 20 * prior, yy = 20 * prior, xy = 0.0
            for letter in keys.keys.sorted() {
                guard let s = keys[letter], s.isValid else { continue }
                let weight = Double(s.n)
                n += weight; xx += weight * s.varianceX; yy += weight * s.varianceY
                xy += weight * s.covarianceXY
            }
            return .init(offsetX: 0, offsetY: 0, sigmaX: sqrt(xx / n), sigmaY: sqrt(yy / n), covarianceXY: xy / n)
        }

        func slowKey(_ stats: TouchStats?) -> SpatialTouchCalibration.Key {
            let prior = pooled
            guard let stats else { return prior }
            let w = Double(stats.n) / Double(stats.n + 20)
            return .init(offsetX: w * stats.meanX, offsetY: w * stats.meanY,
                         sigmaX: sqrt(w * stats.varianceX + (1 - w) * prior.sigmaX * prior.sigmaX),
                         sigmaY: sqrt(w * stats.varianceY + (1 - w) * prior.sigmaY * prior.sigmaY),
                         covarianceXY: w * stats.covarianceXY + (1 - w) * prior.covarianceXY)
        }
    }

    nonisolated struct WordCount: Codable, Equatable, Sendable {
        var count: Int
        var lastUpdated: Date
    }

    nonisolated struct State: Codable, Equatable, Sendable {
        var schemaVersion = 2
        var layouts: [String: LayoutStats] = [:]
        var kept: [String: Date] = [:]
        var counts: [String: WordCount] = [:]
        var rejected: [RejectedCorrection] = []

        func validated() -> State? {
            guard (1...2).contains(schemaVersion), layouts.count <= 4,
                  Set(kept.keys).union(counts.keys).count <= 2000, rejected.count <= 512,
                  Set(rejected).count == rejected.count else { return nil }
            for (id, layout) in layouts {
                let signature = layout.signature
                guard id == signature.id, ["portrait", "landscape"].contains(signature.orientation),
                      (8...4096).contains(signature.widthBucket), signature.widthBucket % 8 == 0,
                      layout.lastUpdated.timeIntervalSinceReferenceDate.isFinite,
                      !layout.keys.isEmpty, layout.keys.count <= 26,
                      layout.global == nil || layout.global?.isValid == true else { return nil }
                for (key, stats) in layout.keys {
                    guard key.count == 1, key.utf8.count == 1,
                          key.utf8.allSatisfy({ (97...122).contains($0) }), stats.isValid else { return nil }
                }
            }
            guard kept.allSatisfy({ Self.validWord($0.key) && $0.value.timeIntervalSinceReferenceDate.isFinite }),
                  counts.allSatisfy({ Self.validWord($0.key) && (1...10_000).contains($0.value.count)
                      && $0.value.lastUpdated.timeIntervalSinceReferenceDate.isFinite }),
                  rejected.allSatisfy({ Self.validRejectedWord($0.typed) && Self.validRejectedWord($0.replacement) }) else { return nil }
            var migrated = self
            migrated.schemaVersion = 2
            return migrated
        }

        /// Repair only invalid key aggregates, preserving unrelated words and layouts.
        /// Called before saving as a backstop against an invalid statistic poisoning a session.
        @discardableResult
        mutating func discardInvalidTouchStats() -> Bool {
            let original = layouts
            for (id, var layout) in layouts {
                layout.keys = layout.keys.filter { key, stats in
                    key.utf8.count == 1 && key.utf8.allSatisfy { (97...122).contains($0) } && stats.isValid
                }
                if layout.global?.isValid == false { layout.global = nil }
                if layout.keys.isEmpty { layouts.removeValue(forKey: id) }
                else { layouts[id] = layout }
            }
            return layouts != original
        }

        static func validWord(_ word: String) -> Bool {
            (2...32).contains(word.count) && word.utf8.count <= 256
                && word.allSatisfy(\.isLetter) && word == PersonalLexiconSnapshot.normalize(word)
        }

        /// Rejected correction forms may contain straight or typographic apostrophes.
        /// Keeps/counts remain letter-only; multi-word text replacements stay session-only.
        static func validRejectedWord(_ word: String) -> Bool {
            (2...32).contains(word.count) && word.utf8.count <= 256
                && word.contains(where: \.isLetter)
                && word.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" }
                && word == PersonalLexiconSnapshot.normalize(word)
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
        var covarianceXY: Double = 0
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
    var isLearningEnabled: Bool { didSet { cachedLexicon = nil; resetFastAim() } }
    // Only ONE active layout's fast aggregates live in RAM: at most 26+1 banks.
    private var fastLayout: String?
    private var fastKeys: [String: TouchAimMemories] = [:]
    private var fastGlobal: TouchAimMemories?

    func resetFastAim() {
        fastLayout = nil; fastKeys.removeAll(); fastGlobal = nil
    }

    private func activateAim(_ signature: KeyboardLayoutSignature) {
        if fastLayout != signature.id {
            resetFastAim()
            fastLayout = signature.id
        }
    }

    private static func bounded(_ key: SpatialTouchCalibration.Key) -> SpatialTouchCalibration.Key {
        SpatialTouchCalibration(keys: ["a": key]).keys["a"] ?? .init(
            offsetX: 0, offsetY: 0, sigmaX: SpatialTouchCalibration.staticSigma,
            sigmaY: SpatialTouchCalibration.staticSigma)
    }
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
                    activateAim(signature)
                    let letter = String(label.letter)
                    let old = stats.keys[letter] ?? TouchStats()
                    let global = stats.global ?? TouchStats()
                    var localAim = fastKeys[letter] ?? TouchAimMemories(slow: old)
                    var globalAim = fastGlobal ?? TouchAimMemories(slow: global)
                    let globalSlow = Self.bounded(global.calibration)
                    globalAim.update(x: x, y: y, slow: globalSlow)
                    let shared = globalAim.prediction(slow: globalSlow)
                    // Local memories explain residual aim after the shared shift, so
                    // a global change is neither diluted by rare keys nor counted twice.
                    let sharedX = global.n >= 20 ? shared.offsetX - globalSlow.offsetX : 0
                    let sharedY = global.n >= 20 ? shared.offsetY - globalSlow.offsetY : 0
                    localAim.update(x: x - sharedX, y: y - sharedY, slow: Self.bounded(stats.slowKey(old)))
                    fastKeys[letter] = localAim; fastGlobal = globalAim
                    stats.keys[letter, default: TouchStats()].update(x: x, y: y)
                    stats.global = global
                    stats.global?.update(x: x, y: y)
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
              let stats = state.layouts[KeyboardLayoutSignature(layout).id] else {
            resetFastAim()
            return nil
        }
        activateAim(stats.signature)
        // Migration does not invent an ordered global stream from old per-key data.
        // Until 20 new pooled labels, legacy keys retain their per-key threshold.
        let pooledReady = (stats.global?.n ?? 0) >= 20
        let globalSlow = stats.global?.calibration
        let globalPrediction = globalSlow.map { fastGlobal?.prediction(slow: $0) ?? $0 }
        var keys: [Character: SpatialTouchCalibration.Key] = [:]
        for character in "abcdefghijklmnopqrstuvwxyz" {
            let letter = String(character), value = stats.keys[letter]
            guard layout.key(.character(letter)) != nil, pooledReady || (value?.n ?? 0) >= 20 else { continue }
            let slow = Self.bounded(stats.slowKey(value))
            let local = fastKeys[letter]?.prediction(slow: slow) ?? slow
            var key = local
            if pooledReady, let globalSlow, let globalPrediction {
                // Shared drift reaches every key immediately; key memories explain
                // residuals. A key without any labels uses the pooled absolute center.
                let baseX = value == nil ? globalSlow.offsetX : local.offsetX
                let baseY = value == nil ? globalSlow.offsetY : local.offsetY
                // Carry shared between-memory uncertainty too (a PSD scatter term).
                let sharedXX = max(0, pow(globalPrediction.sigmaX, 2) - pow(globalSlow.sigmaX, 2))
                let sharedYY = max(0, pow(globalPrediction.sigmaY, 2) - pow(globalSlow.sigmaY, 2))
                key = .init(offsetX: baseX + globalPrediction.offsetX - globalSlow.offsetX,
                            offsetY: baseY + globalPrediction.offsetY - globalSlow.offsetY,
                            sigmaX: sqrt(local.sigmaX * local.sigmaX + sharedXX),
                            sigmaY: sqrt(local.sigmaY * local.sigmaY + sharedYY),
                            covarianceXY: local.covarianceXY + globalPrediction.covarianceXY - globalSlow.covarianceXY)
            }
            keys[character] = key
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
        guard State.validRejectedWord(pair.typed), State.validRejectedWord(pair.replacement) else { return false }
        if !state.rejected.contains(pair) {
            state.rejected.append(pair)
            if state.rejected.count > 512 { state.rejected.removeFirst() }
            cachedLexicon = nil
        }
        return true
    }

    func forgetKeep(_ word: String) {
        state.kept.removeValue(forKey: PersonalLexiconSnapshot.normalize(word))
        cachedLexicon = nil
    }

    func forgetRejection(_ pair: RejectedCorrection) {
        state.rejected.removeAll { $0 == pair }
        cachedLexicon = nil
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
                    let key = bounded(layout.slowKey(stats))
                    return KeySummary(letter: letter, n: stats.n, offsetX: key.offsetX, offsetY: key.offsetY,
                                      sigmaX: key.sigmaX, sigmaY: key.sigmaY, covarianceXY: key.covarianceXY)
                })
        }
        return Summary(layouts: layouts, keptWords: state.kept.count, countedWords: state.counts.count,
            wordCountTotal: state.counts.values.reduce(0) { $0 + $1.count }, rejectedCorrections: state.rejected.count)
    }

    /// Mutates RAM too, so the same invalid aggregate is reported only once.
    func prepareForSave() -> Bool {
        guard state.validated() == nil else { return false }
        return state.discardInvalidTouchStats()
    }

    func reset() { state = State(); cachedLexicon = nil; resetFastAim() }
}
