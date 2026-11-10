import Foundation
import XCTest
@testable import Typr

final class KeyboardDiagnosticsTests: XCTestCase {
    func testCountersSaturateAndIgnoreNegativeIncrements() {
        var diagnostics = KeyboardDiagnostics(now: Date(timeIntervalSince1970: 1))
        diagnostics.increment(.boundaries, by: Int.max)
        diagnostics.increment(.boundaries)
        diagnostics.increment(.boundaries, by: -1)
        XCTAssertEqual(diagnostics[.boundaries], Int(Int32.max))
        XCTAssertEqual(diagnostics[.evidenceComplete], 0)
        for counter in KeyboardDiagnostics.Counter.allCases { diagnostics.increment(counter) }
        XCTAssertEqual(diagnostics.counters.count, KeyboardDiagnostics.Counter.allCases.count)
        XCTAssertGreaterThanOrEqual(diagnostics.updatedAt, diagnostics.since)
    }

    func testLatencyBucketEdgesAndInvalidSamples() {
        var diagnostics = KeyboardDiagnostics()
        for seconds in [0, 0.001, 0.002, 0.005, 0.010, 0.020, 0.050] {
            diagnostics.recordLatency(seconds, kind: .boundary)
        }
        XCTAssertEqual(diagnostics.boundaryMs, Array(repeating: 1, count: 7))
        for seconds in [-1.0, .nan, .infinity] { diagnostics.recordLatency(seconds, kind: .boundary) }
        XCTAssertEqual(diagnostics.boundaryMs, Array(repeating: 1, count: 7))
        diagnostics.recordLatency(0.00099, kind: .suggestion)
        diagnostics.recordLatency(Double.greatestFiniteMagnitude, kind: .suggestion)
        XCTAssertEqual(diagnostics.suggestionMs, [1, 0, 0, 0, 0, 0, 1])
    }

    func testCodableRoundTripAndUnknownCountersIgnored() throws {
        var original = KeyboardDiagnostics(now: Date(timeIntervalSince1970: 1))
        original.increment(.autoRule)
        original.recordLatency(0.004, kind: .suggestion)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardDiagnostics.self, from: data), original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["counters"] = ["autoRule": 1, "futureCounter": Int.max, "futureFormat": ["ignored": true]]
        let decoded = try JSONDecoder().decode(KeyboardDiagnostics.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.counters, ["autoRule": 1])
        XCTAssertEqual(decoded.since, original.since)
    }

    func testRejectsWrongSchemaInvalidCountsAndMalformedHistograms() throws {
        let original = KeyboardDiagnostics(now: Date(timeIntervalSince1970: 1))
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let invalid: [(String, Any)] = [
            ("schemaVersion", 2), ("counters", ["boundaries": -1]),
            ("counters", ["boundaries": Int.max]), ("boundaryMs", [0, 0]),
            ("suggestionMs", [-1, 0, 0, 0, 0, 0, 0]), ("updatedAt", -Double.greatestFiniteMagnitude),
        ]
        for (key, value) in invalid {
            var changed = object; changed[key] = value
            let encoded = try JSONSerialization.data(withJSONObject: changed)
            XCTAssertThrowsError(try JSONDecoder().decode(KeyboardDiagnostics.self, from: encoded), key)
        }
    }

    func testLatencyCountersSaturateOnIncrement() throws {
        let data = try JSONEncoder().encode(KeyboardDiagnostics())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["boundaryMs"] = [Int(Int32.max), 0, 0, 0, 0, 0, 0]
        var decoded = try JSONDecoder().decode(KeyboardDiagnostics.self, from: JSONSerialization.data(withJSONObject: object))
        decoded.recordLatency(0, kind: .boundary)
        XCTAssertEqual(decoded.boundaryMs[0], Int(Int32.max))
    }
}
