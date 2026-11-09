import CoreGraphics
import XCTest
@testable import Typr

final class TyprKeyGestureTests: XCTestCase {
    func testTapTypesSpace() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 3, y: 2)), .ignored, "a jitter is still a tap")
        XCTAssertEqual(gesture.touchUp(), .tap)
        XCTAssertEqual(gesture.holdElapsed(), .ignored, "a timer left over from the tap")
        XCTAssertEqual(gesture.state, .idle)
    }

    func testStillHoldFiresOnceAndNoSpace() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.holdElapsed(), .ignored)
        XCTAssertEqual(gesture.touchUp(), .ignored, "a hold never types a space")
    }

    func testSlideUpOpensMenu() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 20, y: 9), allowsCompactBar: true), .openMenu)
        XCTAssertEqual(gesture.holdElapsed(), .ignored, "the menu won, no dictation")
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 0, y: 40), allowsCompactBar: true), .dragMenu,
                       "once open, moving down drags in the menu")
        XCTAssertEqual(gesture.touchUp(), .releaseMenu)
        XCTAssertEqual(gesture.state, .idle)
    }

    func testSlideSidewaysOpensMenu() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 5, y: 25), allowsCompactBar: true), .openMenu)
    }

    func testSlideDownShowsCompactBar() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 24, y: 32), allowsCompactBar: true), .showCompactBar)
        XCTAssertEqual(gesture.holdElapsed(), .ignored, "no dictation")
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 24, y: 60), allowsCompactBar: true), .ignored)
        XCTAssertEqual(gesture.touchUp(), .ignored, "no space, no menu")
        XCTAssertEqual(gesture.state, .idle)
    }

    func testSlideDownOpensMenuWithoutCompactBar() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 20, y: 40)), .openMenu, "switch key off: today's behaviour")
    }

    func testMoveAfterHoldDoesNothing() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: .zero)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 0, y: -80), allowsCompactBar: true), .ignored)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 0, y: 80), allowsCompactBar: true), .ignored)
        XCTAssertEqual(gesture.touchUp(), .ignored)
    }

    func testCancelResets() {
        var gesture = TyprKeyGesture()
        gesture.touchDown(at: .zero)
        gesture.cancel()
        XCTAssertEqual(gesture.state, .idle)
        XCTAssertEqual(gesture.holdElapsed(), .ignored)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: 50, y: 0)), .ignored)
        XCTAssertEqual(gesture.touchUp(), .ignored, "a cancelled press types no space")
    }
}
