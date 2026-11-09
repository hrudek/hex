import Foundation
import XCTest
@testable import HEX

@MainActor
final class HexPlusModelInfoTests: XCTestCase {
    func testConfiguredPathPrecedence() {
        let cases: [(Bool, Bool, Bool, HexPlusCleanupPath)] = [
            (true, true, true, .hexPlus),
            (true, true, false, .hexPlus),
            (true, false, true, .upstreamExperiment),
            (true, false, false, .none),
            (false, true, true, .unsupportedOS),
            (false, true, false, .unsupportedOS),
            (false, false, true, .unsupportedOS),
            (false, false, false, .unsupportedOS)
        ]
        for (framework, hexPlus, upstream, expected) in cases {
            XCTAssertEqual(HexPlusCleanupPath.resolve(
                frameworkAvailable: framework, hexPlusOn: hexPlus, upstreamOn: upstream
            ), expected)
        }
    }

    func testAvailableHexPlusLines() {
        let info = HexPlusModelInfo(path: .hexPlus, osVersion: "26.1.0", availabilityReason: nil)
        XCTAssertEqual(info.lines, [
            "Apple on-device foundation model · running on iOS 26.1.0",
            "Used for new recordings by Typr AI cleanup (general use, permissive content transformations)",
            "Model availability: available. Model version managed by Apple. Never used in Verbatim."
        ])
    }

    func testAvailableUpstreamLines() {
        let info = HexPlusModelInfo(path: .upstreamExperiment, osVersion: "26.2.1", availabilityReason: nil)
        XCTAssertEqual(info.lines, [
            "Apple on-device foundation model · running on iOS 26.2.1",
            "Used for new recordings by Clean up with Apple Intelligence (Experiments) (general use, default guardrails)",
            "Model availability: available. Model version managed by Apple. Never used in Verbatim."
        ])
    }

    func testUnavailableHexPlusLinesKeepItsOwnReason() {
        let info = HexPlusModelInfo(
            path: .hexPlus, osVersion: "26.1.0",
            availabilityReason: "Turn on Apple Intelligence in Settings to use this"
        )
        XCTAssertEqual(info.lines, [
            "Apple on-device foundation model · running on iOS 26.1.0",
            "Used for new recordings by Typr AI cleanup (general use, permissive content transformations)",
            "Model availability: Turn on Apple Intelligence in Settings to use this"
        ])
    }

    func testUnavailableUpstreamLinesKeepItsOwnReason() {
        let info = HexPlusModelInfo(
            path: .upstreamExperiment, osVersion: "26.1.0",
            availabilityReason: "Apple Intelligence is getting ready"
        )
        XCTAssertEqual(info.lines, [
            "Apple on-device foundation model · running on iOS 26.1.0",
            "Used for new recordings by Clean up with Apple Intelligence (Experiments) (general use, default guardrails)",
            "Model availability: Apple Intelligence is getting ready"
        ])
    }

    func testNoModelLinesDoNotImplyAvailability() {
        // Even an injected reason must not leak into the no-model presentation.
        XCTAssertEqual(HexPlusModelInfo(
            path: .none, osVersion: "26.1.0", availabilityReason: "unused reason"
        ).lines, ["No model: AI cleanup and Clean up with Apple Intelligence are off"])
        XCTAssertEqual(HexPlusModelInfo(
            path: .unsupportedOS, osVersion: "18.0.0", availabilityReason: "unused reason"
        ).lines, ["No model: requires iOS 26 or later"])
    }

    func testReaderOnlyLooksUpSelectedAvailabilityAndNeverFallsThrough() {
        for framework in [false, true] {
            for hexPlus in [false, true] {
                for upstream in [false, true] {
                    var hexPlusCalls = 0
                    var upstreamCalls = 0
                    let reader = HexPlusModelInfoReader(
                        frameworkAvailable: { framework },
                        hexPlusOn: { hexPlus },
                        upstreamOn: { upstream },
                        hexPlusReason: { hexPlusCalls += 1; return "Typr unavailable" },
                        upstreamReason: { upstreamCalls += 1; return "Upstream unavailable" },
                        osVersion: { "26.1.0" }
                    )
                    let info = reader.read()
                    XCTAssertEqual(info.osVersion, "26.1.0")
                    if !framework {
                        XCTAssertEqual(info.path, .unsupportedOS)
                        XCTAssertNil(info.availabilityReason)
                    } else if hexPlus {
                        XCTAssertEqual(info.path, .hexPlus)
                        XCTAssertEqual(info.availabilityReason, "Typr unavailable")
                    } else if upstream {
                        XCTAssertEqual(info.path, .upstreamExperiment)
                        XCTAssertEqual(info.availabilityReason, "Upstream unavailable")
                    } else {
                        XCTAssertEqual(info.path, .none)
                        XCTAssertNil(info.availabilityReason)
                    }
                    XCTAssertEqual(hexPlusCalls, framework && hexPlus ? 1 : 0)
                    XCTAssertEqual(upstreamCalls, framework && !hexPlus && upstream ? 1 : 0)
                }
            }
        }
    }

    func testReaderSeesSiblingSettingChangesInBothDirections() throws {
        let name = "model-info.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = HexPlusSettings(defaults: defaults)
        let upstream = AppleIntelligenceCleanupSettings(defaults: defaults)
        settings.aiCleanup = false
        let reader = HexPlusModelInfoReader(
            frameworkAvailable: { true },
            hexPlusOn: { HexPlusSettings(defaults: defaults).aiCleanup },
            upstreamOn: { AppleIntelligenceCleanupSettings(defaults: defaults).isEnabled },
            hexPlusReason: { XCTFail("Typr is off"); return nil },
            upstreamReason: { nil },
            osVersion: { "26.1.0" }
        )
        XCTAssertEqual(reader.read().path, .none)
        upstream.isEnabled = true
        XCTAssertEqual(reader.read().path, .upstreamExperiment)
        upstream.isEnabled = false
        XCTAssertEqual(reader.read().path, .none)

        // Restoring Typr takes priority even when upstream is on.
        upstream.isEnabled = true
        settings.aiCleanup = true
        let prioritized = HexPlusModelInfoReader(
            frameworkAvailable: { true },
            hexPlusOn: { settings.aiCleanup },
            upstreamOn: { upstream.isEnabled },
            hexPlusReason: { "Typr unavailable" },
            upstreamReason: { XCTFail("Unavailable Typr must not fall through"); return nil },
            osVersion: { "26.1.0" }
        )
        XCTAssertEqual(prioritized.read().path, .hexPlus)
        XCTAssertEqual(prioritized.read().availabilityReason, "Typr unavailable")
    }

    func testDisplaySwitchDefaultsOnAndPersistsWithoutChangingCleanupSettings() throws {
        let name = "model-info.settings.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = HexPlusSettings(defaults: defaults)
        let upstream = AppleIntelligenceCleanupSettings(defaults: defaults)
        XCTAssertTrue(settings.showCleanupModel)
        XCTAssertTrue(settings.aiCleanup)
        XCTAssertFalse(upstream.isEnabled)
        settings.showCleanupModel = false
        XCTAssertFalse(HexPlusSettings(defaults: defaults).showCleanupModel)
        XCTAssertEqual(defaults.object(forKey: "typr.showCleanupModel") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "typr.aiCleanup"))
        XCTAssertNil(defaults.object(forKey: "experiments.appleIntelligenceCleanup"))

        for hexPlusOn in [false, true] {
            for upstreamOn in [false, true] {
                settings.aiCleanup = hexPlusOn
                upstream.isEnabled = upstreamOn
                for show in [true, false] {
                    settings.showCleanupModel = show
                    XCTAssertEqual(HexPlusSettings(defaults: defaults).showCleanupModel, show)
                    XCTAssertEqual(settings.aiCleanup, hexPlusOn)
                    XCTAssertEqual(upstream.isEnabled, upstreamOn)
                }
            }
        }
    }
}
