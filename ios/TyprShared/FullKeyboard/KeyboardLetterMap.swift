import Foundation

/// Physical holders, not popup positions. Translated from iikb Correction/LetterKeys.swift,
/// 09a2e9cdfbe851adff6c4646333c0a3f74ba8765 (MIT, © 2026 Bassim Shahidy).
/// The corpus alphabet stays Unicode; several letters share ONE key's touch density.
nonisolated enum KeyboardLetterMap {
    static func holder(of letter: Character) -> Character {
        switch letter {
        case "ä": "a"
        case "ö": "o"
        case "ü": "u"
        case "ß": "s"
        default: letter
        }
    }

    struct Emissions {
        let likelihoods: [[Double]]
        let best: [Double]
        let literal: Double
    }

    /// Same normalized, gated Gaussian for correction and noisy-prefix retrieval. Calibration
    /// belongs to the physical key. This does not turn popup gestures into observed taps or labels.
    static func emissions(for word: KeyboardTouchWord, calibration: SpatialTouchCalibration?) -> Emissions? {
        guard word.layout.layer == .letters, word.layout.field == .text,
              !word.samples.isEmpty, word.samples.count <= 32 else { return nil }
        let alphabet = SpatialWordLexicon.alphabet
        let holders = alphabet.map { holder(of: $0) }
        let frames = holders.map { word.layout.key(.character(String($0)))?.frame }
        let keys = holders.map { calibration?.keys[$0] }
        var likelihoods: [[Double]] = []
        var bestScores: [Double] = []
        var literalSpatial = 0.0
        for sample in word.samples {
            guard sample.text.count == 1, sample.text.lowercased().count == 1,
                  sample.key == word.layout.key(sample.key.kind),
                  sample.key.character?.lowercased() == sample.text.lowercased(),
                  sample.point.x.isFinite, sample.point.y.isFinite,
                  let letter = sample.text.lowercased().first,
                  let label = alphabet.firstIndex(of: letter),
                  word.layout.key(.character(String(letter))) != nil else { return nil }
            var scores = [Double](repeating: -.infinity, count: alphabet.count)
            for index in alphabet.indices {
                guard let frame = frames[index] else { continue }
                let width = Double(frame.width + word.layout.metrics.gap)
                let height = Double(frame.height + word.layout.metrics.rowGap)
                guard frame.width > 0, frame.height > 0, width.isFinite, height.isFinite,
                      width > 0, height > 0 else { return nil }
                let key = keys[index]
                let dx = Double(sample.point.x - frame.midX) / width - (key?.offsetX ?? 0)
                let dy = Double(sample.point.y - frame.midY) / height - (key?.offsetY ?? 0)
                let sx = key?.sigmaX ?? SpatialTouchCalibration.staticSigma
                let sy = key?.sigmaY ?? SpatialTouchCalibration.staticSigma
                if dx * dx + dy * dy <= 1.6 * 1.6 {
                    scores[index] = -0.5 * (dx * dx / (sx * sx) + dy * dy / (sy * sy))
                        - log(2 * Double.pi * sx * sy)
                }
            }
            guard scores[label].isFinite, let best = scores.max(), best.isFinite else { return nil }
            literalSpatial += scores[label]
            bestScores.append(best)
            for index in scores.indices where scores[index] < best - 6 { scores[index] = -.infinity }
            likelihoods.append(scores)
        }
        return Emissions(likelihoods: likelihoods, best: bestScores, literal: literalSpatial)
    }
}
