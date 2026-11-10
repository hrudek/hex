import SwiftUI
import UIKit
import XCTest
@testable import Typr

final class SettingsPresentationTests: XCTestCase {
    func testEverySettingsPageHasAnExplicitSnapshotRoute() {
        for destination in SettingsDestination.allCases {
            XCTAssertFalse(destination.title.isEmpty)
            XCTAssertFalse(destination.subtitle.isEmpty)
            XCTAssertEqual(
                SettingsDestination.snapshotDestination(arguments: ["Typr", "--snap-state", "settings-\(destination.rawValue)"]),
                destination
            )
        }
        XCTAssertEqual(Set(SettingsDestination.allCases.map(\.title)),
                       ["Keyboard", "Writing", "History & feedback", "Speech engine"])
    }

    func testOrdinaryLaunchesAndUnrelatedScenesDoNotNavigate() {
        for arguments in [[], ["Typr"], ["--snap-state"], ["--snap-state", "ready"],
                          ["--snap-state", "keyboard-warm"], ["--snap-state", "settings-unknown"],
                          ["settings-keyboard"], ["--other", "settings-keyboard"]] {
            XCTAssertNil(SettingsDestination.snapshotDestination(arguments: arguments))
        }
    }

    @MainActor
    func testSettingsRowsGrowForAccessibilityTextAtCompactWidth() {
        func size(_ type: DynamicTypeSize) -> CGSize {
            let view = SettingsToggle(
                title: "Keep dictation history",
                detail: "Saves text stages, vocabulary and feedback. No audio. Kept until you delete it.",
                isOn: .constant(true)
            )
            .dynamicTypeSize(type)
            let host = UIHostingController(rootView: view)
            return host.sizeThatFits(in: CGSize(width: 320, height: 10_000))
        }
        let regular = size(.large)
        let accessible = size(.accessibility3)
        XCTAssertGreaterThanOrEqual(regular.height, 64)
        XCTAssertGreaterThan(accessible.height, regular.height)
        XCTAssertLessThanOrEqual(accessible.width, 320.5)
        XCTAssertLessThan(accessible.height, 10_000)
    }

    @MainActor
    func testWarmDurationButtonsUseTwoRowsAtAccessibilitySizes() {
        func size(_ type: DynamicTypeSize) -> CGSize {
            let host = UIHostingController(rootView:
                SettingsWarmDurationControl(selected: .fifteenMinutes, onSelect: { _ in })
                    .dynamicTypeSize(type)
            )
            return host.sizeThatFits(in: CGSize(width: 280, height: 10_000))
        }
        let regular = size(.large)
        let accessible = size(.accessibility3)
        XCTAssertGreaterThanOrEqual(regular.height, 44)
        XCTAssertGreaterThan(accessible.height, regular.height)
        XCTAssertLessThanOrEqual(accessible.width, 280.5)
    }

    @MainActor
    func testMenuEntryPointsStaySingleLineAndCompactAtStandardTextSize() {
        for title in ["Keyboard", "Writing", "History & feedback", "Speech engine", "iOS keyboard settings", "Open dictation log"] {
            let host = UIHostingController(rootView:
                SettingsLink(title: title, detail: "Explanations stay on the destination", icon: "keyboard")
                    .dynamicTypeSize(.large)
            )
            let size = host.sizeThatFits(in: CGSize(width: 353, height: 10_000))
            XCTAssertEqual(size.height, 56, accuracy: 0.5, title)
            XCTAssertLessThanOrEqual(size.width, 353.5, title)
        }
    }

    @MainActor
    func testNavigationRowsWrapRatherThanFixingTheirHeight() {
        let row = SettingsLink(title: "History & feedback", detail: "Dictation log, exports and keyboard ratings",
                               icon: "clock.arrow.circlepath", value: "100 entries")
            .dynamicTypeSize(.accessibility3)
        let host = UIHostingController(rootView: row)
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 10_000))
        XCTAssertGreaterThan(size.height, 76)
        XCTAssertLessThanOrEqual(size.width, 320.5)
        XCTAssertLessThan(size.height, 10_000)
    }
}
