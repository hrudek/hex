import CoreGraphics
import XCTest
@testable import Typr

/// Typr: switching between the full keyboard and the compact dictation bar.
@MainActor
final class KeyboardSurfaceChoiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "KeyboardSurfaceChoiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Full keyboard

    func testBottomRowHasNoSeparateSwitchKey() {
        for globe in [false, true] {
            for field in [KeyboardFieldKind.text, .url, .email] {
                let layout = KeyboardLayout(width: 393, field: field, showsGlobe: globe)
                let bottom = layout.keys.filter { $0.row == 3 }.sorted { $0.frame.minX < $1.frame.minX }
                XCTAssertEqual(bottom.first?.kind, .layerSwitch(.numbers), "123 leads the row again")
                XCTAssertNotNil(layout.key(.typr))
            }
        }
    }

    func testFullKeyboardViewAllowsCompactBarOnTheTyprKey() {
        let view = FullKeyboardView(model: KeyboardViewModel(), target: FixtureTextTarget())
        XCTAssertFalse(view.allowsCompactBar, "off unless the controller turns it on")
        view.allowsCompactBar = true
        XCTAssertTrue(view.allowsCompactBar)
    }

    // MARK: - Settings and choice

    func testSettingDefaultsOnAndPersists() {
        let settings = TyprSettings(defaults: defaults)
        XCTAssertTrue(settings.keyboardSwitchKey)
        settings.keyboardSwitchKey = false
        XCTAssertFalse(TyprSettings(defaults: defaults).keyboardSwitchKey)
    }

    func testChoiceDefaultsToFullKeyboardAndPersists() {
        let choice = KeyboardSurfaceChoice(defaults: defaults)
        XCTAssertFalse(choice.showsCompactBar)
        choice.showsCompactBar = true
        XCTAssertTrue(KeyboardSurfaceChoice(defaults: defaults).showsCompactBar)
    }

    func testWhichKeyboardMounts() {
        typealias Choice = KeyboardSurfaceChoice
        XCTAssertTrue(Choice.wantsFullKeyboard(experimentOn: true, switchKeyOn: true, compactChosen: false))
        XCTAssertFalse(Choice.wantsFullKeyboard(experimentOn: true, switchKeyOn: true, compactChosen: true))
        XCTAssertTrue(
            Choice.wantsFullKeyboard(experimentOn: true, switchKeyOn: false, compactChosen: true),
            "switch off keeps today's behaviour: the experiment alone decides"
        )
        XCTAssertFalse(Choice.wantsFullKeyboard(experimentOn: false, switchKeyOn: true, compactChosen: false))
        XCTAssertFalse(Choice.wantsFullKeyboard(experimentOn: false, switchKeyOn: false, compactChosen: false))
    }
}
