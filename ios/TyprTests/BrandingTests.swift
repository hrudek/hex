import SwiftUI
import XCTest
@testable import Typr

final class BrandingTests: XCTestCase {
    func testWordmarkAspectFitsAndCentersWithinItsSlot() {
        for rect in [CGRect(x: 0, y: 0, width: 80, height: 40),
                     CGRect(x: 12, y: 7, width: 20, height: 20)] {
            let bounds = TyprWordmark().path(in: rect).boundingRect
            XCTAssertFalse(bounds.isEmpty)
            XCTAssertEqual(bounds.midX, rect.midX, accuracy: 0.01)
            XCTAssertEqual(bounds.midY, rect.midY, accuracy: 0.01)
            XCTAssertLessThanOrEqual(bounds.width, rect.width + 0.01)
            XCTAssertLessThanOrEqual(bounds.height, rect.height + 0.01)
            XCTAssertEqual(bounds.width / bounds.height, 1359.718 / 573, accuracy: 0.001)
        }
    }

    func testOpticallyCenteredWordmarkShiftsRightAndDownProportionally() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 40)
        let plain = TyprWordmark().path(in: rect).boundingRect
        let optical = TyprWordmark(opticallyCentered: true).path(in: rect).boundingRect
        let scale = plain.width / 1359.718
        XCTAssertEqual(optical.size.width, plain.size.width, accuracy: 0.01)
        XCTAssertEqual(optical.size.height, plain.size.height, accuracy: 0.01)
        XCTAssertEqual(optical.minX - plain.minX, TyprWordmark.opticalOffset.width * scale, accuracy: 0.01)
        XCTAssertEqual(optical.minY - plain.minY, TyprWordmark.opticalOffset.height * scale, accuracy: 0.01)
    }
}
