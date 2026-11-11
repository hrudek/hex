import Foundation
import XCTest
@testable import Typr

@MainActor
final class PersonalTypingAimTests: XCTestCase {
    private let grid = KeyboardLayout(width: 393)

    private func label(_ letter: Character, _ x: Double, _ y: Double) -> TouchLabel {
        let key = grid.key(.character(String(letter)))!
        return TouchLabel(point: CGPoint(x: key.frame.midX + x * (key.frame.width + grid.metrics.gap),
                                         y: key.frame.midY + y * (key.frame.height + grid.metrics.rowGap)), letter: letter)
    }

    private func warm() -> PersonalTypingModel {
        let model = PersonalTypingModel()
        for i in 0..<160 {
            model.learn("abcdefghijklmnopqrstuvwxyz".map {
                label($0, Double(i % 5 - 2) * 0.035, Double(i % 3 - 1) * 0.05)
            }, layout: grid, source: .keep)
        }
        return model
    }

    func testCovarianceReferenceAndInvalidInput() {
        var stats = PersonalTypingModel.TouchStats()
        for (x, y) in [(0.2, 0.3), (-0.2, -0.1), (0.3, -0.2)] { stats.update(x: x, y: y) }
        XCTAssertEqual(stats.meanX, 0.1, accuracy: 1e-12)
        XCTAssertEqual(stats.meanY, 0, accuracy: 1e-12)
        XCTAssertEqual(stats.varianceX, 0.04666666666666667, accuracy: 1e-12)
        XCTAssertEqual(stats.varianceY, 0.04666666666666667, accuracy: 1e-12)
        XCTAssertEqual(stats.covarianceXY, 0.006666666666666667, accuracy: 1e-12)
        let before = stats
        stats.update(x: .nan, y: 0); stats.update(x: 0, y: .infinity)
        XCTAssertEqual(stats, before)
        stats.covarianceXY = 1
        XCTAssertFalse(stats.isValid)
    }

    func testFiniteEigenvalueFloorsAndDiagonalEquivalence() throws {
        for xy in [-1e100, -0.1, 0, 0.1, 1e100] {
            let key = try XCTUnwrap(SpatialTouchCalibration(keys: ["a": .init(
                offsetX: 10, offsetY: -10, sigmaX: 0.3, sigmaY: 0.4, covarianceXY: xy)]).keys["a"])
            let xx = key.sigmaX * key.sigmaX, yy = key.sigmaY * key.sigmaY
            let radius = hypot(xx - yy, 2 * key.covarianceXY)
            XCTAssertGreaterThanOrEqual((xx + yy - radius) / 2, 0.22 * 0.22 - 1e-12)
            XCTAssertLessThanOrEqual((xx + yy + radius) / 2, 0.25 + 1e-12)
            XCTAssertGreaterThanOrEqual(xx * yy - key.covarianceXY * key.covarianceXY, pow(0.22, 4) - 1e-12)
            XCTAssertTrue(key.logDensity(x: 1, y: -1).isFinite)
        }
        XCTAssertTrue(SpatialTouchCalibration(keys: ["a": .init(offsetX: 0, offsetY: 0,
            sigmaX: 0.3, sigmaY: 0.3, covarianceXY: .nan)]).keys.isEmpty)
        let diagonal = SpatialTouchCalibration.Key(offsetX: 0.1, offsetY: -0.1, sigmaX: 0.35, sigmaY: 0.35)
        XCTAssertEqual(diagonal.logDensity(x: 0.3, y: 0.2),
                       -0.5 * (0.2 * 0.2 + 0.3 * 0.3) / (0.35 * 0.35) - log(2 * Double.pi * 0.35 * 0.35), accuracy: 1e-12)
        // Numerical integration checks normalized density, including a tilted cloud.
        let tilted = try XCTUnwrap(SpatialTouchCalibration(keys: ["a": .init(offsetX: 0, offsetY: 0,
            sigmaX: 0.35, sigmaY: 0.35, covarianceXY: 0.06)]).keys["a"])
        var mass = 0.0
        for i in -150...150 { for j in -150...150 {
            mass += exp(tilted.logDensity(x: Double(i) * 0.01, y: Double(j) * 0.01)) * 0.0001
        } }
        XCTAssertEqual(mass, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(tilted.logDensity(x: 0.3, y: 0.3), tilted.logDensity(x: 0.3, y: -0.3))
    }

    func testPooledReferenceTiltedCloudAndScarceLabels() throws {
        let model = PersonalTypingModel()
        let signature = KeyboardLayoutSignature(grid)
        var layout = PersonalTypingModel.LayoutStats(signature: signature, lastUpdated: Date())
        layout.keys["a"] = .init(n: 20, varianceX: 0.08, varianceY: 0.06, covarianceXY: 0.03)
        XCTAssertEqual(layout.pooled.sigmaX * layout.pooled.sigmaX, (20 * 0.1225 + 20 * 0.08) / 40, accuracy: 1e-12)
        XCTAssertEqual(layout.pooled.covarianceXY, 0.015, accuracy: 1e-12)
        XCTAssertEqual(layout.slowKey(layout.keys["a"]).covarianceXY, 0.0225, accuracy: 1e-12)
        for i in 0..<120 {
            let x = Double(i % 7 - 3) * 0.15
            model.learn([label("a", x, x * 0.8)], layout: grid, source: .keep)
        }
        let keys = try XCTUnwrap(model.calibration(for: grid)?.keys)
        XCTAssertGreaterThan(try XCTUnwrap(keys["a"]).covarianceXY, 0.02)
        XCTAssertGreaterThan(try XCTUnwrap(keys["z"]).covarianceXY, 0.02, "pooled covariance reaches an unseen key")
        let sparse = PersonalTypingModel()
        sparse.learn(Array(repeating: label("e", 0.2, 0.1), count: 19), layout: grid, source: .keep)
        XCTAssertNil(sparse.calibration(for: grid))
        sparse.learn([label("t", 0.2, 0.1)], layout: grid, source: .keep)
        XCTAssertGreaterThan(try XCTUnwrap(sparse.calibration(for: grid)?.keys["z"]).offsetX, 0.05)
    }

    func testFixedShareRecoveryAndGlobalTransferReset() throws {
        let model = warm()
        let baseline = try XCTUnwrap(model.calibration(for: grid)?.keys["z"])
        for _ in 0..<30 { model.learn([label("e", 0.24, 0.10)], layout: grid, source: .keep) }
        let shifted = try XCTUnwrap(model.calibration(for: grid)?.keys["z"])
        XCTAssertGreaterThan(shifted.offsetX, baseline.offsetX + 0.07, "an unseen key receives the global shift")
        for _ in 0..<30 { model.learn([label("e", 0, 0)], layout: grid, source: .keep) }
        let returned = try XCTUnwrap(model.calibration(for: grid)?.keys["z"])
        XCTAssertLessThan(returned.offsetX, shifted.offsetX)
        let frozen = model.calibration(for: grid)
        let restored = PersonalTypingModel(state: model.state)
        model.resetFastAim()
        XCTAssertEqual(model.calibration(for: grid), restored.calibration(for: grid))
        XCTAssertNotEqual(frozen, model.calibration(for: grid))
        // The returned snapshot is immutable even if labels arrive later.
        model.learn(Array(repeating: label("e", -0.24, 0), count: 30), layout: grid, source: .keep)
        XCTAssertEqual(frozen?.keys["z"], returned)
        _ = model.calibration(for: KeyboardLayout(width: 430))
        XCTAssertEqual(model.calibration(for: grid), PersonalTypingModel(state: model.state).calibration(for: grid))
    }

    func testPrequentialFixedShareWeightsAndLifecycleReset() throws {
        let stats = PersonalTypingModel.TouchStats(n: 100, varianceX: 0.09, varianceY: 0.09)
        let slow = SpatialTouchCalibration.Key(offsetX: 0, offsetY: 0, sigmaX: 0.3, sigmaY: 0.3)
        var bank = TouchAimMemories(slow: stats)
        bank.update(x: 0.6, y: 0.1, slow: slow)
        XCTAssertEqual(bank.weights[0], 1 / 3, accuracy: 1e-12)
        XCTAssertEqual(bank.medium.x, 0.6 / 30, accuracy: 1e-12)
        XCTAssertEqual(bank.fast.x, 0.6 / 3, accuracy: 1e-12)
        // Independent pre-update predictive odds for the second tap, in log space.
        let means = [(0.0, 0.0), (0.6 / 30, 0.1 / 30), (0.6 / 3, 0.1 / 3)]
        let odds = means.map { exp(-0.5 * (pow(0.6 - $0.0, 2) + pow(0.1 - $0.1, 2)) / 0.09) / 3 }
        let total = odds.reduce(0, +)
        bank.update(x: 0.6, y: 0.1, slow: slow)
        for i in 0..<3 { XCTAssertEqual(bank.weights[i], 0.99 * odds[i] / total + 0.01 / 3, accuracy: 1e-12) }
        for _ in 0..<100 { bank.update(x: -0.6, y: -0.1, slow: slow) }
        XCTAssertEqual(bank.weights[0] + bank.weights[1] + bank.weights[2], 1, accuracy: 1e-12)
        XCTAssertTrue((0..<3).allSatisfy { bank.weights[$0] >= 0.01 / 3 })

        let session = KeyboardLearningSession()
        for _ in 0..<40 { session.learn([label("e", 0.2, 0.1)], layout: grid, source: .keep) }
        let before = session.model.state
        let generation = session.generation
        session.resetFastAim()
        XCTAssertGreaterThan(session.generation, generation)
        XCTAssertEqual(session.model.state, before)
        XCTAssertEqual(session.calibration(for: grid), PersonalTypingModel(state: before).calibration(for: grid))
    }

    func testMigrationRepairAndFastPrivacy() throws {
        let model = warm()
        model.keep("hallo"); model.recordWord("hello"); model.rejectCorrection(typed: "hallo", replacement: "hello")
        let data = try JSONEncoder().encode(model.state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 1
        var layouts = try XCTUnwrap(object["layouts"] as? [String: [String: Any]])
        for id in layouts.keys {
            var layout = layouts[id]!
            layout.removeValue(forKey: "global")
            var keys = layout["keys"] as! [String: [String: Any]]
            for key in keys.keys { keys[key]!.removeValue(forKey: "covarianceXY") }
            layout["keys"] = keys; layouts[id] = layout
        }
        object["layouts"] = layouts
        let legacy = try JSONDecoder().decode(PersonalTypingModel.State.self, from: JSONSerialization.data(withJSONObject: object))
        let migrated = try XCTUnwrap(legacy.validated())
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.kept, model.state.kept)
        XCTAssertEqual(migrated.counts, model.state.counts)
        XCTAssertEqual(migrated.rejected, model.state.rejected)
        XCTAssertTrue(migrated.layouts.values.allSatisfy { $0.global == nil && $0.keys.values.allSatisfy { $0.covarianceXY == 0 } })
        var broken = model.state
        let id = KeyboardLayoutSignature(grid).id
        broken.layouts[id]?.keys["a"]?.covarianceXY = 1
        broken.layouts[id]?.global?.meanX = .nan
        XCTAssertNil(broken.validated())
        XCTAssertTrue(broken.discardInvalidTouchStats())
        XCTAssertNotNil(broken.validated())
        XCTAssertEqual(broken.kept, model.state.kept)
        var future = migrated; future.schemaVersion = 99
        XCTAssertNil(future.validated())
        let encoded = String(decoding: data, as: UTF8.self)
        for forbidden in ["fast", "medium", "weights", "recent", "point"] { XCTAssertFalse(encoded.contains("\"" + forbidden + "\"")) }
    }

    func testMemoryByteBounds() throws {
        let model = warm()
        var maximumLayouts = model.state
        let template = try XCTUnwrap(model.state.layouts.values.first)
        for width: CGFloat in [410, 430, 450] {
            var layout = template
            layout.signature = KeyboardLayoutSignature(KeyboardLayout(width: width))
            maximumLayouts.layouts[layout.signature.id] = layout
        }
        XCTAssertNotNil(maximumLayouts.validated())
        let touchBytes = try JSONEncoder().encode(maximumLayouts).count
        let slowPayload = 4 * 27 * MemoryLayout<PersonalTypingModel.TouchStats>.stride
        let fastPayload = 27 * MemoryLayout<TouchAimMemories>.stride
        XCTAssertLessThan(touchBytes, 64 * 1024)
        XCTAssertLessThan(slowPayload + fastPayload, 16 * 1024)
        XCTAssertEqual(model.state.layouts.count, 1)
        print("EVAL P7_memory slowPayloadMaxBytes=\(slowPayload) fastPayloadMaxBytes=\(fastPayload) fourLayoutEncodedBytes=\(touchBytes) storeLimitBytes=\(KeyboardLearningStore.maximumLearningBytes) heapOverheadExcluded=true")
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<200 { XCTAssertNotNil(model.calibration(for: grid)) }
        let snapshotMs = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 200
        let learningStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<200 { model.learn([label("e", 0.15, 0.1)], layout: grid, source: .keep) }
        let labelMs = (ProcessInfo.processInfo.systemUptime - learningStart) * 1000 / 200
        XCTAssertLessThan(snapshotMs, 100)
        XCTAssertLessThan(labelMs, 100)
        print(String(format: "EVAL P7_modelLatency calls=200 snapshotMeanMs=%.3f trustedLabelMeanMs=%.3f platform=local_debug_not_iPhone", snapshotMs, labelMs))
    }
}
