import Foundation
import CoreGraphics

/// Learning is isolated to one orientation, width bucket and accessory configuration.
nonisolated struct KeyboardLayoutSignature: Hashable, Codable, Sendable {
    let orientation: String
    let widthBucket: Int
    let showsStrip: Bool
    let showsGlobe: Bool

    init(_ layout: KeyboardLayout) {
        switch layout.orientation {
        case .portrait: orientation = "portrait"
        case .landscape: orientation = "landscape"
        }
        widthBucket = Int((layout.width / 8).rounded()) * 8
        showsStrip = layout.showsStrip
        showsGlobe = layout.showsGlobe
    }

    var id: String {
        "\(orientation)-\(widthBucket)-\(showsStrip ? "strip" : "no-strip")-\(showsGlobe ? "globe" : "no-globe")"
    }
}

/// Read-only offsets and spreads in key pitches (frame width + gap, height + rowGap).
// Layout-separated calibration adapted from AVGVSTVS96/iikb
// Packages/KeyboardModules/Sources/KeyboardCore/Correction/TouchModel.swift (MIT).
nonisolated struct SpatialTouchCalibration: Equatable, Sendable {
    struct Key: Equatable, Sendable {
        let offsetX: Double
        let offsetY: Double
        let sigmaX: Double
        let sigmaY: Double
        var covarianceXY: Double = 0

        /// Normalized full-covariance Gaussian. Sanitized by the snapshot initializer.
        func logDensity(x: Double, y: Double) -> Double {
            let dx = x - offsetX, dy = y - offsetY
            let xx = sigmaX * sigmaX, yy = sigmaY * sigmaY
            let determinant = xx * yy - covarianceXY * covarianceXY
            return -0.5 * max(0, (yy * dx * dx - 2 * covarianceXY * dx * dy + xx * dy * dy) / determinant)
                - log(2 * Double.pi) - 0.5 * log(determinant)
        }
    }

    let keys: [Character: Key]
    static let staticSigma = 0.35
    static let maxOffset = 0.25
    static let sigmaRange: ClosedRange<Double> = 0.22...0.50

    init(keys: [Character: Key]) {
        self.keys = keys.reduce(into: [:]) { result, entry in
            let (letter, key) = entry
            guard letter.isLetter, String(letter) == String(letter).lowercased(),
                  key.offsetX.isFinite, key.offsetY.isFinite,
                  key.sigmaX.isFinite, key.sigmaY.isFinite, key.covarianceXY.isFinite else { return }
            let sx = max(Self.sigmaRange.lowerBound, min(Self.sigmaRange.upperBound, key.sigmaX))
            let sy = max(Self.sigmaRange.lowerBound, min(Self.sigmaRange.upperBound, key.sigmaY))
            // Both eigenvalues stay in [.22², .50²], hence det >= .22⁴.
            let floor = Self.sigmaRange.lowerBound * Self.sigmaRange.lowerBound
            let ceiling = Self.sigmaRange.upperBound * Self.sigmaRange.upperBound
            let xyLimit = min(sqrt(max(0, (sx * sx - floor) * (sy * sy - floor))),
                              sqrt(max(0, (ceiling - sx * sx) * (ceiling - sy * sy))))
            result[letter] = Key(
                offsetX: max(-Self.maxOffset, min(Self.maxOffset, key.offsetX)),
                offsetY: max(-Self.maxOffset, min(Self.maxOffset, key.offsetY)),
                sigmaX: sx, sigmaY: sy,
                covarianceXY: max(-xyLimit, min(xyLimit, key.covarianceXY))
            )
        }
    }
}

/// A trusted tap and lowercase letter supplied by the integration's aligner; never persisted.
nonisolated struct TouchLabel: Equatable, Sendable {
    let point: CGPoint
    let letter: Character
}

nonisolated enum TouchLabelSource: String, Codable, CaseIterable, Sendable {
    case literalValid, keep, undo, manualPick
}

nonisolated enum TouchLabelRejection: String, Codable, CaseIterable, Sendable {
    case outlier, nonFinite, unknownKey, layoutMismatch, ambiguousAlignment, learningOff
}

/// A normalized typed → replacement pair rejected by explicit feedback.
nonisolated struct RejectedCorrection: Hashable, Codable, Sendable {
    let typed: String
    let replacement: String

    init(typed: String, replacement: String) {
        self.typed = PersonalLexiconSnapshot.normalize(typed)
        self.replacement = PersonalLexiconSnapshot.normalize(replacement)
    }

    private enum CodingKeys: String, CodingKey { case typed, replacement }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(typed: try container.decode(String.self, forKey: .typed),
                  replacement: try container.decode(String.self, forKey: .replacement))
    }
}

/// Immutable canonical word collections; the learning model supplies normalized keys.
// Keeps and personal counts adapted from AVGVSTVS96/iikb
// Packages/KeyboardModules/Sources/KeyboardCore/Correction/TypingMemory.swift (MIT).
nonisolated struct PersonalLexiconSnapshot: Equatable, Sendable {
    let kept: Set<String>
    let counts: [String: Int]
    let rejected: Set<RejectedCorrection>
    /// Shared identity lets the decoder reuse filtered entries without comparing 2,000 words.
    let scan: ScanList

    nonisolated final class ScanList: Sendable {
        nonisolated struct Entry: Sendable {
            let word: String
            let labels: [Int]
            let bonus: Double
        }
        let entries: [Entry]
        let complete: Bool
        let maxBonus: Double

        init(kept: Set<String>, counts: [String: Int]) {
            func bonus(_ count: Int) -> Double {
                guard count >= 1 else { return 0 }
                return min(PersonalLexiconSnapshot.maxBonus, 0.25 * log2(1 + Double(count)))
            }
            // Check each counted key once; kept-only words are checked below. Noncanonical
            // count keys cannot supply a bonus, even in externally constructed snapshots.
            let normalizedCounts = counts.filter { $0.key == PersonalLexiconSnapshot.normalize($0.key) }
            let words = kept.union(counts.keys.filter { (counts[$0] ?? 0) >= 2 }).sorted()
            complete = words.count <= 2_000
            maxBonus = normalizedCounts.values.map(bonus).max() ?? 0
            entries = words.prefix(2_000).compactMap { word in
                let normalized = counts[word] == nil
                    ? word == PersonalLexiconSnapshot.normalize(word) : normalizedCounts[word] != nil
                guard normalized else { return nil }
                let letters = Array(word)
                guard (2...32).contains(letters.count) else { return nil }
                let labels = letters.compactMap { SpatialWordLexicon.alphabet.firstIndex(of: $0) }
                guard labels.count == letters.count else { return nil }
                return Entry(word: word, labels: labels, bonus: bonus(counts[word] ?? 0))
            }
        }
    }

    init(kept: Set<String>, counts: [String: Int], rejected: Set<RejectedCorrection>) {
        self.kept = kept
        self.counts = counts
        self.rejected = rejected
        scan = ScanList(kept: kept, counts: counts)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kept == rhs.kept && lhs.counts == rhs.counts && lhs.rejected == rhs.rejected
    }

    static let empty = PersonalLexiconSnapshot(kept: [], counts: [:], rejected: [])
    static let maxBonus = 1.0

    static func normalize(_ word: String) -> String {
        word.lowercased().precomposedStringWithCanonicalMapping
    }

    func isKept(_ word: String) -> Bool {
        kept.contains(Self.normalize(word))
    }

    func isRejected(typed: String, replacement: String) -> Bool {
        rejected.contains(RejectedCorrection(typed: typed, replacement: replacement))
    }

    func bonus(for word: String) -> Double {
        guard let count = counts[Self.normalize(word)], count >= 1 else { return 0 }
        return min(Self.maxBonus, 0.25 * log2(1 + Double(count)))
    }
}
