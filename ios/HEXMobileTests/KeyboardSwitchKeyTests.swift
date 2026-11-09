import CoreGraphics
import XCTest
@testable import HEX

/// Typr: the key that switches between the full keyboard and the compact dictation bar.
@MainActor
final class KeyboardSwitchKeyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "KeyboardSwitchKeyTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Hold gesture

    func testHoldIs350Milliseconds() {
        XCTAssertEqual(KeyboardSwitchHold.holdDuration, 0.35, accuracy: 0.0001)
    }

    func testTapNeverSwitches() {
        var hold = KeyboardSwitchHold()
        hold.touchDown()
        hold.touchMoved(inside: true)
        hold.touchUp()
        XCTAssertFalse(hold.holdElapsed(), "the timer left over from a tap must not switch")
        XCTAssertEqual(hold.state, .idle)
    }

    func testHoldSwitchesOnce() {
        var hold = KeyboardSwitchHold()
        hold.touchDown()
        XCTAssertTrue(hold.holdElapsed())
        XCTAssertFalse(hold.holdElapsed())
        hold.touchUp()
        XCTAssertEqual(hold.state, .idle)
    }

    func testSlidingOffCancelsTheHold() {
        var hold = KeyboardSwitchHold()
        hold.touchDown()
        hold.touchMoved(inside: false)
        XCTAssertFalse(hold.holdElapsed())
        hold.touchMoved(inside: true)
        XCTAssertFalse(hold.holdElapsed(), "coming back does not re-arm the press")
    }

    func testNewPressRearms() {
        var hold = KeyboardSwitchHold()
        hold.touchDown()
        hold.touchMoved(inside: false)
        hold.touchUp()
        hold.touchDown()
        XCTAssertTrue(hold.holdElapsed())
    }

    // MARK: - Layout

    func testSwitchKeyLeadsTheBottomRowOnlyWhenShown() {
        for globe in [false, true] {
            for field in [KeyboardFieldKind.text, .url, .email] {
                let layout = KeyboardLayout(width: 393, field: field, showsGlobe: globe, showsCompactSwitch: true)
                let bottom = layout.keys.filter { $0.row == 3 }.sorted { $0.frame.minX < $1.frame.minX }
                XCTAssertEqual(bottom.first?.kind, .compactSwitch)
                XCTAssertEqual(bottom.dropFirst().first?.kind, .layerSwitch(.numbers))
                XCTAssertNotNil(layout.key(.space))
                XCTAssertNotNil(layout.key(.hex))
                XCTAssertNotNil(layout.key(.returnKey))
                if let last = bottom.last {
                    XCTAssertLessThanOrEqual(last.frame.maxX, 393 - layout.metrics.side + 0.5, "the row fits")
                }
            }
        }
        XCTAssertNil(KeyboardLayout(width: 393).key(.compactSwitch))
        XCTAssertNil(KeyboardLayout(width: 393, showsGlobe: true).key(.compactSwitch))
    }

    func testSwitchKeyIsOnEveryLayerAndOrientation() {
        for layer in [KeyboardLayer.letters, .numbers, .symbols] {
            XCTAssertNotNil(KeyboardLayout(width: 393, layer: layer, showsCompactSwitch: true).key(.compactSwitch))
            XCTAssertNotNil(
                KeyboardLayout(width: 852, orientation: .landscape, layer: layer, showsCompactSwitch: true).key(.compactSwitch)
            )
        }
    }

    func testSwitchKeyHitFrameReachesTheLeftEdge() throws {
        let layout = KeyboardLayout(width: 393, showsCompactSwitch: true)
        let key = try XCTUnwrap(layout.key(.compactSwitch))
        XCTAssertEqual(key.hitFrame.minX, 0)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 1, y: key.frame.midY))?.kind, .compactSwitch)
    }

    func testEngineShowsTheSwitchKey() {
        let engine = FullKeyboardEngine(target: FixtureTextTarget())
        engine.width = 393
        XCTAssertNil(engine.layout.key(.compactSwitch))
        engine.showsCompactSwitch = true
        XCTAssertNotNil(engine.layout.key(.compactSwitch))
        engine.showsCompactSwitch = false
        XCTAssertNil(engine.layout.key(.compactSwitch))
    }

    func testFullKeyboardViewShowsTheSwitchKey() {
        let view = FullKeyboardView(model: KeyboardViewModel(), target: FixtureTextTarget())
        XCTAssertFalse(view.showsCompactSwitch, "off unless the controller turns it on")
        view.showsCompactSwitch = true
        XCTAssertTrue(view.engine.showsCompactSwitch)
    }

    // MARK: - Settings and choice

    func testSettingDefaultsOnAndPersists() {
        let settings = HexPlusSettings(defaults: defaults)
        XCTAssertTrue(settings.keyboardSwitchKey)
        settings.keyboardSwitchKey = false
        XCTAssertFalse(HexPlusSettings(defaults: defaults).keyboardSwitchKey)
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
