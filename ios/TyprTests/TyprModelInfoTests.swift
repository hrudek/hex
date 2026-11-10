import Foundation
import XCTest
@testable import Typr

@MainActor
final class TyprModelInfoTests: XCTestCase {
    func testConfiguredPath() {
        for framework in [false, true] {
            for enabled in [false, true] {
                XCTAssertEqual(TyprCleanupPath.resolve(frameworkAvailable: framework, typrOn: enabled),
                    !framework ? .unsupportedOS : (enabled ? .typr : .none))
            }
        }
    }

    func testAvailableTyprLines() {
        XCTAssertEqual(TyprModelInfo(path: .typr, osVersion: "26.1.0", availabilityReason: nil).lines, [
            "Apple on-device foundation model · running on iOS 26.1.0",
            "Used for new recordings by Typr AI cleanup (general use, permissive content transformations)",
            "Model availability: available. Model version managed by Apple. Never used in Verbatim."
        ])
    }

    func testUnavailableTyprLinesKeepItsOwnReason() {
        XCTAssertEqual(TyprModelInfo(path: .typr, osVersion: "26.1.0",
            availabilityReason: "Turn on Apple Intelligence in Settings to use this").lines, [
            "Apple on-device foundation model · running on iOS 26.1.0",
            "Used for new recordings by Typr AI cleanup (general use, permissive content transformations)",
            "Model availability: Turn on Apple Intelligence in Settings to use this"
        ])
    }

    func testNoModelLinesDoNotImplyAvailability() {
        XCTAssertEqual(TyprModelInfo(path: .none, osVersion: "26.1.0", availabilityReason: "unused").lines,
            ["No model: AI cleanup is off"])
        XCTAssertEqual(TyprModelInfo(path: .unsupportedOS, osVersion: "18.0.0", availabilityReason: "unused").lines,
            ["No model: requires iOS 26 or later"])
    }

    func testReaderOnlyLooksUpEnabledSupportedAvailability() {
        for framework in [false, true] {
            for enabled in [false, true] {
                var calls = 0
                let reader = TyprModelInfoReader(frameworkAvailable: { framework }, typrOn: { enabled },
                    typrReason: { calls += 1; return "Typr unavailable" }, osVersion: { "26.1.0" })
                let info = reader.read()
                XCTAssertEqual(info.path, !framework ? .unsupportedOS : (enabled ? .typr : .none))
                XCTAssertEqual(info.osVersion, "26.1.0")
                XCTAssertEqual(info.availabilityReason, framework && enabled ? "Typr unavailable" : nil)
                XCTAssertEqual(calls, framework && enabled ? 1 : 0)
            }
        }
    }

    func testReaderTracksTyprSettingAndIgnoresRemovedExperiment() throws {
        let name = "model-info.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TyprSettings(defaults: defaults)
        let reader = TyprModelInfoReader(frameworkAvailable: { true }, typrOn: { settings.aiCleanup },
            typrReason: { "Typr unavailable" }, osVersion: { "26.1.0" })
        for legacyOn in [false, true] {
            defaults.set(legacyOn, forKey: "experiments.appleIntelligenceCleanup")
            settings.aiCleanup = false
            XCTAssertEqual(reader.read().path, .none)
            XCTAssertNil(reader.read().availabilityReason)
            settings.aiCleanup = true
            XCTAssertEqual(reader.read().path, .typr)
            XCTAssertEqual(reader.read().availabilityReason, "Typr unavailable")
        }
    }

    func testDisplaySwitchDefaultsOnAndPersistsWithoutChangingCleanup() throws {
        let name = "model-info.settings.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.showCleanupModel)
        XCTAssertTrue(settings.aiCleanup)
        settings.showCleanupModel = false
        XCTAssertFalse(TyprSettings(defaults: defaults).showCleanupModel)
        XCTAssertNil(defaults.object(forKey: "typr.aiCleanup"))
        for enabled in [false, true] {
            settings.aiCleanup = enabled
            for show in [false, true] {
                settings.showCleanupModel = show
                XCTAssertEqual(TyprSettings(defaults: defaults).showCleanupModel, show)
                XCTAssertEqual(settings.aiCleanup, enabled)
            }
        }
    }
}
