import Foundation
import XCTest
@testable import Typr

/// Shared frozen generator: both the original evaluation and worker equivalence get identical taps.
nonisolated enum SpatialTypoEvaluationEvidence {
    enum ErrorClass: String, CaseIterable {
        case neighbour1, neighbour2, missing, extra, transposition
    }
    private struct SplitMix64 {
        var state: UInt64
        mutating func uniform() -> Double {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            value ^= value >> 31
            return (Double(value >> 11) + 0.5) / 9_007_199_254_740_992
        }
        mutating func normal() -> Double {
            sqrt(-2 * log(uniform())) * cos(2 * Double.pi * uniform())
        }
    }
    private static func neighbour(_ letter: Character, grid: KeyboardLayout) throws -> Character {
        let frame = try XCTUnwrap(grid.key(.character(String(letter)))).frame
        let pitchX = frame.width + grid.metrics.gap
        let pitchY = frame.height + grid.metrics.rowGap
        let candidates = Array("abcdefghijklmnopqrstuvwxyz").filter { $0 != letter }
        let sorted = candidates.sorted { a, b in
            func distance(_ c: Character) -> CGFloat {
                guard let other = grid.key(.character(String(c)))?.frame else { return .infinity }
                let dx = (frame.midX - other.midX) / pitchX
                let dy = (frame.midY - other.midY) / pitchY
                return dx * dx + dy * dy
            }
            let da = distance(a), db = distance(b)
            return da == db ? a < b : da < db
        }
        return try XCTUnwrap(sorted.first)
    }

    static func evidence(_ word: String, grid: KeyboardLayout, error: ErrorClass? = nil, ordinal: Int,
                          seed: UInt64, sigma: Double) throws -> KeyboardTouchWord {
        var typed = Array(word.lowercased())
        var aimed = typed
        let index = ordinal % typed.count
        switch error {
        case .neighbour1, .neighbour2:
            typed[index] = try neighbour(typed[index], grid: grid)
            if error == .neighbour2 {
                let other = (index + max(1, typed.count / 2)) % typed.count
                typed[other] = try neighbour(typed[other], grid: grid)
            }
        case .missing:
            typed.remove(at: index)
            aimed.remove(at: index)
        case .extra:
            let extra = try neighbour(typed[index], grid: grid)
            typed.insert(extra, at: index)
            aimed.insert(extra, at: index)
        case .transposition:
            // Every fixture has a distinct adjacent pair; repeated equal pairs are not errors.
            let pairs = (0..<(typed.count - 1)).filter { typed[$0] != typed[$0 + 1] }
            let position = pairs[ordinal % pairs.count]
            typed.swapAt(position, position + 1)
            aimed.swapAt(position, position + 1)
        case nil: break
        }
        // Each case has a stable local RNG, so variants A and B receive identical samples.
        let classIndex = error.flatMap { ErrorClass.allCases.firstIndex(of: $0) } ?? 5
        var random = SplitMix64(state: seed &+ UInt64(ordinal) &* 97 &+ UInt64(classIndex) &* 1_000_003)
        let samples = try zip(typed, aimed).map { typed, aimed in
            let key = try XCTUnwrap(grid.key(.character(String(typed))))
            let frame = try XCTUnwrap(grid.key(.character(String(aimed)))).frame
            let x = frame.midX + CGFloat(random.normal() * sigma) * (frame.width + grid.metrics.gap)
            let y = frame.midY + CGFloat(random.normal() * sigma) * (frame.height + grid.metrics.rowGap)
            return KeyboardTouchWord.Sample(text: String(typed), point: CGPoint(x: x, y: y), key: key)
        }
        return KeyboardTouchWord(layout: grid, samples: samples)
    }

}
