import Foundation

/// Aggregate-only, RAM-only aim memories. Translated from iikb TouchModel.swift
/// (KeyTouches/Drift/Posterior), 09a2e9cdfbe851adff6c4646333c0a3f74ba8765,
/// MIT © 2026 Bassim Shahidy. No recent-point reservoir or self-labeling.
nonisolated struct TouchAimMemories: Sendable {
    struct Drift: Sendable {
        var count: Double
        var x: Double
        var y: Double

        mutating func update(x: Double, y: Double, memory: Double) {
            count = count * (1 - 1 / memory) + 1
            self.x += (x - self.x) / count
            self.y += (y - self.y) / count
        }
    }

    var medium: Drift
    var fast: Drift
    private(set) var weights = SIMD3<Double>(repeating: 1 / 3)

    init(slow: PersonalTypingModel.TouchStats) {
        medium = Drift(count: Double(min(30, slow.n)), x: slow.meanX, y: slow.meanY)
        fast = Drift(count: Double(min(3, slow.n)), x: slow.meanX, y: slow.meanY)
    }

    private func candidates(_ slow: SpatialTouchCalibration.Key) -> [SpatialTouchCalibration.Key] {
        [slow, .init(offsetX: medium.x, offsetY: medium.y, sigmaX: slow.sigmaX,
                     sigmaY: slow.sigmaY, covarianceXY: slow.covarianceXY),
         .init(offsetX: fast.x, offsetY: fast.y, sigmaX: slow.sigmaX,
               sigmaY: slow.sigmaY, covarianceXY: slow.covarianceXY)]
    }

    mutating func update(x: Double, y: Double, slow: SpatialTouchCalibration.Key) {
        // Score BEFORE updating. Log-space normalization avoids underflow. Fixed share
        // lets a dormant slow memory recover when the original grip returns.
        let scores = candidates(slow).map { $0.logDensity(x: x, y: y) }
        let best = scores.max() ?? 0
        var odds = weights
        for i in 0..<3 { odds[i] *= exp(scores[i] - best) }
        let total = odds[0] + odds[1] + odds[2]
        weights = 0.99 * odds / total + SIMD3<Double>(repeating: 0.01 / 3)
        medium.update(x: x, y: y, memory: 30)
        fast.update(x: x, y: y, memory: 3)
    }

    func prediction(slow: SpatialTouchCalibration.Key) -> SpatialTouchCalibration.Key {
        let keys = candidates(slow)
        var x = 0.0, y = 0.0
        for i in 0..<3 { x += weights[i] * keys[i].offsetX; y += weights[i] * keys[i].offsetY }
        // Moment-match, not an unnormalized sum of densities. Disagreeing memories
        // broaden the Gaussian instead of asserting unwarranted precision.
        var xx = slow.sigmaX * slow.sigmaX, yy = slow.sigmaY * slow.sigmaY, xy = slow.covarianceXY
        for i in 0..<3 {
            let dx = keys[i].offsetX - x, dy = keys[i].offsetY - y
            xx += weights[i] * dx * dx; yy += weights[i] * dy * dy; xy += weights[i] * dx * dy
        }
        return .init(offsetX: x, offsetY: y, sigmaX: sqrt(xx), sigmaY: sqrt(yy), covarianceXY: xy)
    }
}
