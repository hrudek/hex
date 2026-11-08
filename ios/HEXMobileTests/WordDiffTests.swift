import XCTest
@testable import HEX

final class WordDiffTests: XCTestCase {
    private func assertReconstructs(_ before: String, _ after: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .compared(let parts) = WordDiff.compute(before, after) else {
            XCTFail("Unexpected comparison limit", file: file, line: line); return
        }
        XCTAssertEqual(parts.filter { $0.kind != .added }.map(\.text).joined(), before, file: file, line: line)
        XCTAssertEqual(parts.filter { $0.kind != .removed }.map(\.text).joined(), after, file: file, line: line)
    }

    func testEmptyIdenticalAndAllAddedOrRemoved() {
        XCTAssertEqual(WordDiff.compute("", ""), .compared([]))
        XCTAssertEqual(WordDiff.compute("cat", "cat"), .compared([.init(text: "cat", kind: .unchanged)]))
        XCTAssertEqual(WordDiff.compute("", "cat"), .compared([.init(text: "cat", kind: .added)]))
        XCTAssertEqual(WordDiff.compute("cat", ""), .compared([.init(text: "cat", kind: .removed)]))
    }

    func testCorrectionsAndNotesLineBreaksRemainVisible() {
        for (before, after) in [("Dienstag nein Mittwoch", "Mittwoch"), ("cat\ndog", "cat dog"),
                                ("ä 👩🏽‍💻\n\nß", "Ä 👩🏽‍💻\nß"), ("one\r\ntwo", "one\ntwo"),
                                ("a\tb  c", "a b c"), ("same same last", "same last")] {
            assertReconstructs(before, after)
        }
        guard case .compared(let parts) = WordDiff.compute("cat\ndog", "cat dog") else { return XCTFail() }
        XCTAssertTrue(parts.contains { $0.text == "\n" && $0.kind == .removed })
        XCTAssertTrue(parts.contains { $0.text == " " && $0.kind == .added })
    }

    func testTokenBoundOnEitherSideAndWorstCaseMatrix() {
        let atLimit = String(repeating: "\n", count: 400)
        let overLimit = String(repeating: "\n", count: 401)
        assertReconstructs(atLimit, atLimit)
        XCTAssertEqual(WordDiff.compute(overLimit, "small"), .tooLong)
        XCTAssertEqual(WordDiff.compute("small", overLimit), .tooLong)
        assertReconstructs(String(repeating: "\n", count: 400), String(repeating: " ", count: 400))
    }
}
