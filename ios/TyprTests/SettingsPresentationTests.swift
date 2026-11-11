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
                       ["Keyboard", "Typing diagnostics", "Manage learned words", "AI & vocabulary", "History & feedback", "Speech engine", "Style", "Language", "Cleanup prompt"])
    }

    @MainActor
    func testLearnedWordsFixtureContainsOnlySyntheticEntries() {
        let state = KeyboardLearnedWordsView.fixtureState()
        XCTAssertNotNil(state.validated())
        XCTAssertEqual(Set(state.kept.keys), ["swift", "typr"])
        XCTAssertEqual(state.rejected, [.init(typed: "teh", replacement: "the")])
        XCTAssertEqual(state.counts["hello"]?.count, 12)
        XCTAssertEqual(SettingsDestination.snapshotDestination(arguments:
            ["Typr", "--snap-state", "settings-keyboard-learned-words"]), .keyboardLearnedWords)
    }

    @MainActor
    func testLearnedWordsSearchFiltersEveryCategoryAndBothSidesOfCorrections() {
        var state = KeyboardLearnedWordsView.fixtureState()
        state.kept["München"] = KeyboardDiagnosticsFixture.now
        state.kept["hello"] = KeyboardDiagnosticsFixture.now
        state.counts["other"] = .init(count: 3, lastUpdated: KeyboardDiagnosticsFixture.now)
        typealias Results = KeyboardLearnedWordsView.SearchResults

        let all = Results(state: state, query: "  \n ")
        XCTAssertEqual(all.kept, state.kept.keys.sorted())
        XCTAssertEqual(all.pairs, state.rejected)
        XCTAssertEqual(all.counts, ["hello", "other"])

        let partial = Results(state: state, query: "  ELL  ")
        XCTAssertEqual(partial.kept, ["hello"])
        XCTAssertEqual(partial.counts, ["hello"])
        XCTAssertTrue(partial.pairs.isEmpty)
        XCTAssertEqual(Results(state: state, query: "munchen").kept, ["München"])
        XCTAssertEqual(Results(state: state, query: "TEH").pairs, state.rejected)
        XCTAssertEqual(Results(state: state, query: "THE").pairs, state.rejected)

        let none = Results(state: state, query: "not-saved")
        XCTAssertTrue(none.kept.isEmpty)
        XCTAssertTrue(none.pairs.isEmpty)
        XCTAssertTrue(none.counts.isEmpty)
        XCTAssertEqual(state.counts["hello"]?.count, 12)
        XCTAssertEqual(state.kept.count, 4)
    }

    @MainActor
    func testLearnedWordsFilteredDeletionTargetsVisibleEntriesOnly() {
        var state = KeyboardLearnedWordsView.fixtureState()
        state.kept["zebra"] = KeyboardDiagnosticsFixture.now
        state.counts["zebra"] = .init(count: 1, lastUpdated: KeyboardDiagnosticsFixture.now)
        state.rejected.append(.init(typed: "adn", replacement: "and"))
        let visible = KeyboardLearnedWordsView.SearchResults(state: state, query: "t")
        XCTAssertEqual(visible.kept, ["swift", "typr"])
        XCTAssertEqual(visible.pairs, [.init(typed: "teh", replacement: "the")])
        XCTAssertTrue(visible.counts.isEmpty)

        state.kept.removeValue(forKey: visible.kept[0])
        state.rejected.removeAll { $0 == visible.pairs[0] }
        XCTAssertNotNil(state.kept["zebra"])
        XCTAssertNotNil(state.kept["typr"])
        XCTAssertNil(state.kept["swift"])
        XCTAssertEqual(state.rejected, [.init(typed: "adn", replacement: "and")])
    }

    func testTypingDiagnosticsRouteAndTitle() {
        XCTAssertEqual(SettingsDestination.snapshotDestination(arguments: ["Typr", "--snap-state", "settings-keyboard-diagnostics"]), .keyboardDiagnostics)
        XCTAssertEqual(SettingsDestination.keyboardDiagnostics.title, "Typing diagnostics")
        XCTAssertEqual(SettingsDestination.keyboardDiagnostics.subtitle, "")
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

    func testEveryDictationStyleExplainsItsBehavior() {
        for style in DictationStyle.allCases {
            XCTAssertFalse(style.settingsDescription.isEmpty, style.rawValue)
        }
        XCTAssertTrue(DictationStyle.notes.settingsDescription.contains("new line"))
        XCTAssertTrue(DictationStyle.notes.settingsDescription.contains("new paragraph"))
        XCTAssertEqual(TranscriptFormatter.format("first new line second", style: .notes), "First\nSecond")
        XCTAssertEqual(TranscriptFormatter.format("first new paragraph second", style: .notes), "First\n\nSecond")
        XCTAssertEqual(TranscriptFormatter.format("bullet first bullet second", style: .notes), "- First\n- Second")
        XCTAssertTrue(DictationStyle.verbatim.settingsDescription.contains("Skips AI cleanup"))
        XCTAssertTrue(DictationStyle.verbatim.settingsDescription.contains("Vocabulary corrections"))
    }

    @MainActor
    func testDictationLinksShowSelectedValuesAtStandardAndAccessibilitySizes() {
        for (title, value) in [("Speech engine", "Apple Speech"), ("Speech engine", "Parakeet V2"),
                               ("Speech engine", "Whisper"), ("Style", "Polished"),
                               ("Language", "Automatic"), ("Language", "German")] {
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
    func testLanguageChoicesUseSingleLineRowsWithoutDescriptions() {
        for language in DictationLanguage.allCases {
            for selected in [true, false] {
                let row = SettingsChoiceRow(title: language.label, isSelected: selected, onSelect: {})
                XCTAssertNil(row.detail)
                let host = UIHostingController(rootView: row.dynamicTypeSize(.large))
                let size = host.sizeThatFits(in: CGSize(width: 280, height: 10_000))
                XCTAssertEqual(size.height, 64, accuracy: 0.5, language.rawValue)
                XCTAssertLessThanOrEqual(size.width, 280.5, language.rawValue)
            }
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
