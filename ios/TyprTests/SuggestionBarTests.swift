import UIKit
import XCTest
@testable import Typr

/// Typr: *Hide suggestion bar* on the full keyboard.
@MainActor
final class SuggestionBarTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "SuggestionBarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSettingDefaultsOnAndPersists() {
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.hideSuggestionBar)
        settings.hideSuggestionBar = false
        XCTAssertFalse(TyprSettings(defaults: defaults).hideSuggestionBar)
    }

    private func keyboard(showsBar: Bool, text: String = "") -> (FullKeyboardView, FixtureTextTarget) {
        let target = FixtureTextTarget(text: text)
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target)
        view.suggestionBarOverride = showsBar
        view.orientationOverride = .portrait
        view.engine.autocorrect.isEnabled = true
        view.frame = CGRect(x: 0, y: 0, width: 393, height: view.preferredHeight)
        view.layoutIfNeeded()
        return (view, target)
    }

    private func press(_ kinds: [KeyKind], on view: FullKeyboardView) {
        for (index, kind) in kinds.enumerated() {
            guard let key = view.engine.layout.key(kind) else { return XCTFail("no key \(kind)") }
            let point = CGPoint(x: key.frame.midX, y: key.frame.midY)
            view.engine.touchBegan(id: 500 + index, at: point)
            view.engine.touchEnded(id: 500 + index, at: point)
        }
    }

    func testHiddenBarMakesTheKeyboardShorterAndComputesNoSuggestions() {
        let (view, _) = keyboard(showsBar: false)
        XCTAssertEqual(view.preferredHeight, 224)
        XCTAssertFalse(view.engine.showsStrip)
        press([.character("t"), .character("e"), .character("h")], on: view)
        XCTAssertTrue(view.engine.suggestions.isEmpty)
        XCTAssertEqual(view.engine.layout.key(.character("q"))?.frame.minY, 6)
    }

    func testBarOnKeepsTheEarlierKeyboard() {
        let (view, _) = keyboard(showsBar: true)
        XCTAssertEqual(view.preferredHeight, 253)
        press([.character("t"), .character("e"), .character("h")], on: view)
        XCTAssertFalse(view.engine.suggestions.isEmpty)
        XCTAssertEqual(view.engine.layout.key(.character("q"))?.frame.minY, 35)
    }

    func testAutocorrectOnSpaceStillAppliesWithoutTheBar() {
        let (view, target) = keyboard(showsBar: false)
        press([.character("t"), .character("e"), .character("h"), .space], on: view)
        XCTAssertTrue(target.text.hasSuffix("he "), target.text)
        XCTAssertFalse(target.text.lowercased().contains("teh"), target.text)
    }

    func testSwitchingTheBarRebuildsTheKeys() {
        let (view, _) = keyboard(showsBar: true)
        view.suggestionBarOverride = false
        XCTAssertEqual(view.preferredHeight, 224)
        XCTAssertEqual(view.engine.layout.key(.character("q"))?.frame.minY, 6)
        view.suggestionBarOverride = true
        XCTAssertEqual(view.preferredHeight, 253)
    }
}
