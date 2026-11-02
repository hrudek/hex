import CoreGraphics
import XCTest
@testable import HEX

final class HexKeyGestureTests: XCTestCase {
    private let key = CGPoint(x: 300, y: 200)

    func testQuickTapDoesNothing() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        XCTAssertEqual(gesture.touchMoved(to: key, now: 0.1), [])
        XCTAssertNil(gesture.touchUp(at: key))
        XCTAssertEqual(gesture.phase, .idle)
    }

    func testHoldingStillStartsDictationOnce() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        XCTAssertNil(gesture.tick(now: 0.34))
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertNil(gesture.holdElapsed())
        XCTAssertNil(gesture.tick(now: 1))
    }

    func testReleaseAfterHoldKeepsDictationRunning() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertNil(gesture.touchUp(at: key), "release must not stop or toggle anything")
    }

    func testJitterWithinSlideDistanceStillHolds() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        let jitter = CGPoint(x: key.x + 6, y: key.y - 6)
        XCTAssertEqual(gesture.touchMoved(to: jitter, now: 0.2), [])
        XCTAssertEqual(gesture.holdElapsed(), .hold)
    }

    func testSlidingBeforeTheHoldOpensTheMenuAndPicksOnRelease() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        let up = CGPoint(x: key.x, y: key.y - 30)
        XCTAssertEqual(gesture.touchMoved(to: up, now: 0.15), [.openMenu, .drag(up)])
        XCTAssertNil(gesture.holdElapsed(), "a slide never starts dictation")
        let row = CGPoint(x: key.x - 20, y: key.y - 80)
        XCTAssertEqual(gesture.touchMoved(to: row, now: 0.5), [.drag(row)])
        XCTAssertEqual(gesture.touchUp(at: row), .finishMenu(row))
        XCTAssertEqual(gesture.phase, .idle)
    }

    func testSlidingAfterTheHoldDoesNotOpenTheMenu() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        XCTAssertEqual(gesture.holdElapsed(), .hold)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: key.x, y: key.y - 80), now: 0.6), [])
        XCTAssertNil(gesture.touchUp(at: key))
    }

    func testALateMoveEventStillCountsAsTheHold() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        XCTAssertEqual(gesture.touchMoved(to: CGPoint(x: key.x, y: key.y - 40), now: 0.4), [.hold])
    }

    func testCancelForgetsTheTouch() {
        var gesture = HexKeyGesture()
        gesture.touchDown(at: key, now: 0)
        gesture.cancel()
        XCTAssertNil(gesture.holdElapsed())
        XCTAssertEqual(gesture.phase, .idle)
    }
}
