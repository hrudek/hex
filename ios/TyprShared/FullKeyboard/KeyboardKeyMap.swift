import Foundation
import CoreGraphics

/// Invisible, conservative horizontal letter attribution, not a layout or word decoder.
/// KeyMap/posterior × prefix continuation idea translated from iikb Correction/KeyMap.swift
/// and Typing/TypingEngine+Words.swift at 09a2e9cdfbe851adff6c4646333c0a3f74ba8765
/// (MIT, © 2026 Bassim Shahidy). Typr owns the bounds, abstention and trust policy.
nonisolated struct KeyboardKeyMap: Sendable {
    static let keyLimit = 26
    /// Value policy is internal, not a user switch. Evaluations compare frozen alternatives.
    struct Policy: Sendable {
        let boundaryFraction: Double
        let novelFloor: Double
        let minimumPrefix: Int
        let densityMargin: Double
        let posteriorMargin: Double
        let requiresConsistency: Bool

        static let conservative = Policy(boundaryFraction: 0.015, novelFloor: 0.90,
                                         minimumPrefix: 4, densityMargin: log(4),
                                         posteriorMargin: log(16), requiresConsistency: true)
    }
    static let boundaryFraction = Policy.conservative.boundaryFraction
    struct Entry: Sendable {
        let key: KeyboardKey
        let density: SpatialTouchCalibration.Key
        let logPrior: Double
    }
    let layout: KeyboardLayout
    let prefix: String
    let entries: [Entry]
    let policy: Policy
    var payloadBytes: Int { entries.count * MemoryLayout<Entry>.stride }

    init(layout: KeyboardLayout, prefix: String, calibration: SpatialTouchCalibration,
         priors: [Double], policy: Policy = .conservative) {
        self.layout = layout
        self.prefix = prefix
        self.policy = policy
        entries = layout.keys.compactMap { key in
            guard let text = key.character, let letter = text.first, text.count == 1,
                  let index = SpatialWordLexicon.alphabet.firstIndex(of: letter), index < Self.keyLimit,
                  let density = calibration.keys[letter], priors.count == Self.keyLimit else { return nil }
            // Limit the prior odds between any two letters to four, even for rare/novel words.
            let gain = log(max(1.0 / 52, priors[index]) * 26)
            return Entry(key: key, density: density, logPrior: max(-log(2), min(log(2), gain)))
        }.prefix(Self.keyLimit).map { $0 }
    }

    /// Unknown source prefixes contribute uniform mass, never an English-only fallback.
    /// Equal enabled-language mixture, 90% uniform novel-word floor; personal mass can take
    /// at most 20% of the known component. Accents share physical a/o/u/s holders.
    static func priors(prefix: String, languages: Set<SpatialWordDecoder.Language>,
                       lexicons: [SpatialWordDecoder.Language: SpatialWordLexicon],
                       personal: PersonalCompletionIndex?, policy: Policy = .conservative) -> [Double]? {
        guard !languages.isEmpty, languages.allSatisfy({ lexicons[$0] != nil }),
              prefix.utf8.count <= 256, (2...31).contains(prefix.count) else { return nil }
        func distribution(_ masses: [Double]) -> [Double] {
            var folded = [Double](repeating: 0, count: keyLimit)
            for (index, mass) in masses.enumerated() {
                let letter = KeyboardLetterMap.holder(of: SpatialWordLexicon.alphabet[index])
                if let holder = SpatialWordLexicon.alphabet.firstIndex(of: letter), holder < keyLimit {
                    folded[holder] += mass
                }
            }
            let sum = folded.reduce(0, +)
            return sum > 0 ? folded.map { $0 / sum } : [Double](repeating: 1.0 / 26, count: keyLimit)
        }
        var mixed = [Double](repeating: 0, count: keyLimit)
        var hasContinuation = false
        // Fixed language order is important for deterministic floating point mixtures.
        for language in SpatialWordDecoder.Language.allCases where languages.contains(language) {
            let mass = lexicons[language]!.nextLetterMass(after: prefix)
            hasContinuation = hasContinuation || mass.contains(where: { $0 > 0 })
            let source = distribution(mass)
            for index in mixed.indices { mixed[index] += source[index] / Double(languages.count) }
        }
        if let personal {
            let mass = personal.nextLetterMass(after: prefix)
            if mass.reduce(0, +) > 0 {
                hasContinuation = true
                let source = distribution(mass)
                for index in mixed.indices { mixed[index] = 0.8 * mixed[index] + 0.2 * source[index] }
            }
        }
        // A trie cannot re-enter after an absent prefix by appending letters. Combined with
        // the per-word edit latch, this stops adaptation for the rest of an OOV/edited word.
        guard hasContinuation else { return nil }
        return mixed.map { policy.novelFloor / 26 + (1 - policy.novelFloor) * $0 }
    }

    /// Call at actual insertion, not touch-down. Caller also validates text/config/model epoch.
    /// Same-row immediate neighbors only; outer/function/space/punctuation cells cannot donate.
    func attributedKey(at point: CGPoint, geometric: KeyboardKey,
                       layout current: KeyboardLayout, prefix currentPrefix: String) -> KeyboardKey {
        guard current == layout, currentPrefix == prefix, prefix.count >= policy.minimumPrefix,
              layout.layer == .letters,
              layout.field == .text, point.x.isFinite, point.y.isFinite,
              layout.hitTest(point) == geometric, !geometric.frame.contains(point),
              let hit = entries.first(where: { $0.key == geometric }),
              abs(point.y - geometric.frame.midY) <= geometric.frame.height * 0.30 else { return geometric }
        let pitchX = Double(geometric.frame.width + layout.metrics.gap)
        let pitchY = Double(geometric.frame.height + layout.metrics.rowGap)
        guard pitchX > 0, pitchY > 0 else { return geometric }
        func score(_ entry: Entry) -> Double {
            entry.density.logDensity(x: Double(point.x - entry.key.frame.midX) / pitchX,
                                     y: Double(point.y - entry.key.frame.midY) / pitchY)
        }
        let literalDensity = score(hit)
        let literalScore = literalDensity + hit.logPrior
        var best = geometric
        var bestScore = literalScore + policy.posteriorMargin
        for entry in entries where entry.key.row == geometric.row && entry.key != geometric {
            let dx = entry.key.frame.midX - geometric.frame.midX
            guard abs(dx) <= CGFloat(pitchX) * 1.05 else { continue }
            let boundary = dx > 0 ? geometric.hitFrame.maxX : geometric.hitFrame.minX
            let band = min(geometric.frame.width * policy.boundaryFraction, layout.metrics.gap / 2)
            guard abs(point.x - boundary) <= band,
                  entry.logPrior > hit.logPrior else { continue }
            if policy.requiresConsistency {
                // A single displaced/overconfident key is not evidence of shared aim. Both
                // neighboring learned clouds must agree on drift direction, centre and spread.
                let a = entry.density, b = hit.density
                let direction = dx > 0 ? -1.0 : 1.0
                guard a.offsetX * direction >= 0.25, b.offsetX * direction >= 0.25,
                      abs(a.offsetX - b.offsetX) <= 0.08,
                      abs(a.offsetY - b.offsetY) <= 0.08,
                      abs(a.sigmaX - b.sigmaX) <= 0.08,
                      abs(a.sigmaY - b.sigmaY) <= 0.08,
                      abs(a.covarianceXY - b.covarianceXY) <= 0.015 else { continue }
            }
            let density = score(entry)
            // Language cannot override a geometrically better reading. Require learned aim
            // evidence in addition to the posterior margin; cold/static maps stay literal.
            guard density > literalDensity + policy.densityMargin else { continue }
            let posterior = density + entry.logPrior
            if posterior > bestScore { best = entry.key; bestScore = posterior }
        }
        return best
    }
}
