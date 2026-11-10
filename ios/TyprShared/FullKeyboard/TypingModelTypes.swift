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
                  key.sigmaX.isFinite, key.sigmaY.isFinite else { return }
            result[letter] = Key(
                offsetX: max(-Self.maxOffset, min(Self.maxOffset, key.offsetX)),
                offsetY: max(-Self.maxOffset, min(Self.maxOffset, key.offsetY)),
                sigmaX: max(Self.sigmaRange.lowerBound, min(Self.sigmaRange.upperBound, key.sigmaX)),
                sigmaY: max(Self.sigmaRange.lowerBound, min(Self.sigmaRange.upperBound, key.sigmaY))
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
