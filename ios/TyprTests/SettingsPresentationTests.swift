import SwiftUI
import UIKit
import XCTest
@testable import Typr

final class SettingsPresentationTests: XCTestCase {
    func testEverySettingsPageHasAnExplicitSnapshotRoute() {
        for destination in SettingsDestination.allCases {
            XCTAssertFalse(destination.title.isEmpty)
            XCTAssertEqual(
                SettingsDestination.snapshotDestination(arguments: ["Typr", "--snap-state", "settings-\(destination.rawValue)"]),
                destination
            )
        }
        XCTAssertEqual(Set(SettingsDestination.allCases.map(\.title)),
                       ["Keyboard", "AI & vocabulary", "History & feedback", "Speech engine", "Style", "Language"])
    }

    func testTypingAssistanceSnapshotOpensKeyboardSettings() {
        XCTAssertEqual(SettingsDestination.snapshotDestination(arguments: ["Typr", "--snap-state", "settings-keyboard-typing"]), .keyboard)
    }

    func testOverviewLanguageWarningCoversExplicitAndAutomaticParakeet() {
        for language in DictationLanguage.allCases {
            XCTAssertEqual(SpeechEngineRowState.languageWarning(engine: .parakeetV2, language: language) != nil,
                           language != .english)
            let otherEngines: [SpeechEngineChoice?] = [nil, .appleSpeech, .whisperLargeV3Turbo]
            for engine in otherEngines {
                XCTAssertNil(SpeechEngineRowState.languageWarning(engine: engine, language: language))
            }
        }
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
        for title in ["Keyboard", "AI & vocabulary", "History & feedback", "Speech engine", "iOS keyboard settings", "Open dictation log"] {
            let host = UIHostingController(rootView:
                SettingsLink(title: title, detail: "Explanations stay on the destination", icon: "keyboard")
                    .dynamicTypeSize(.large)
            )
            let size = host.sizeThatFits(in: CGSize(width: 353, height: 10_000))
            XCTAssertEqual(size.height, 50, accuracy: 0.5, title)
            XCTAssertLessThanOrEqual(size.width, 353.5, title)
        }
    }

    @MainActor
    func testWarmDurationRowIsInlineWhenItFitsAndStacksWithoutClipping() {
        func size(width: CGFloat, type: DynamicTypeSize = .large) -> CGSize {
            let host = UIHostingController(rootView:
                SettingsWarmDurationRow(selected: .fifteenMinutes, onSelect: { _ in })
                    .dynamicTypeSize(type)
            )
            return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
        }
        XCTAssertEqual(size(width: 353).height, 50, accuracy: 0.5)
        XCTAssertGreaterThan(size(width: 280).height, 50)
        let accessible = size(width: 320, type: .accessibility3)
        XCTAssertGreaterThan(accessible.height, 50)
        XCTAssertLessThanOrEqual(accessible.width, 320.5)
    }

    func testEveryDictationChoiceExplainsItsBehavior() {
        for style in DictationStyle.allCases {
            XCTAssertFalse(style.settingsDescription.isEmpty, style.rawValue)
        }
        for language in DictationLanguage.allCases {
            XCTAssertFalse(language.settingsDescription.isEmpty, language.rawValue)
        }
        XCTAssertTrue(DictationStyle.verbatim.settingsDescription.contains("Skips AI cleanup"))
        XCTAssertTrue(DictationStyle.verbatim.settingsDescription.contains("Vocabulary corrections"))
        XCTAssertTrue(DictationLanguage.automatic.settingsDescription.contains("Whisper detects"))
        XCTAssertTrue(DictationLanguage.automatic.settingsDescription.contains("Parakeet V2 is English only"))
    }

    @MainActor
    func testDictationLinksShowSelectedValuesAtStandardAndAccessibilitySizes() {
        for (title, value) in [("Speech engine", "Apple Speech"), ("Speech engine", "Parakeet V2"),
                               ("Speech engine", "Whisper"), ("Style", "Polished"),
                               ("Language", "Automatic"), ("Language", "Deutsch")] {
            func size(_ type: DynamicTypeSize) -> CGSize {
                let host = UIHostingController(rootView:
                    SettingsLink(title: title, detail: "Open details", value: value).dynamicTypeSize(type)
                )
                return host.sizeThatFits(in: CGSize(width: 353, height: 10_000))
            }
            XCTAssertEqual(size(.large).height, 50, accuracy: 0.5, "\(title): \(value)")
            let accessible = size(.accessibility3)
            XCTAssertGreaterThan(accessible.height, 50, title)
            XCTAssertLessThanOrEqual(accessible.width, 353.5, title)
        }
    }

    @MainActor
    func testDictationChoiceDescriptionsWrapAtCompactWidthAndLargerText() {
        let choices = DictationStyle.allCases.map { ($0.label, $0.settingsDescription) }
            + DictationLanguage.allCases.map { ($0.label, $0.settingsDescription) }
        for (title, detail) in choices {
            func size(_ type: DynamicTypeSize, selected: Bool) -> CGSize {
                let host = UIHostingController(rootView:
                    SettingsChoiceRow(title: title, detail: detail, isSelected: selected, onSelect: {})
                        .dynamicTypeSize(type)
                )
                return host.sizeThatFits(in: CGSize(width: 280, height: 10_000))
            }
            let regular = size(.large, selected: true)
            let accessible = size(.accessibility3, selected: true)
            XCTAssertGreaterThanOrEqual(regular.height, 64, title)
            XCTAssertGreaterThan(accessible.height, regular.height, title)
            XCTAssertLessThanOrEqual(accessible.width, 280.5, title)
            XCTAssertLessThan(accessible.height, 10_000, title)
            XCTAssertEqual(size(.large, selected: false).height, regular.height, accuracy: 0.5, title)
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
