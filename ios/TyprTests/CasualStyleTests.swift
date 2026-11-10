import XCTest
@testable import Typr

final class CasualStyleTests: XCTestCase {
    func testChatStylesDifferOnlyInCapitalization() {
        let cases: [(String, String, String)] = [
            ("ähm ich treffe Anna im Büro. danach komme ich.",
             "Ich treffe Anna im Büro. Danach komme ich", "ich treffe anna im büro. danach komme ich"),
            ("Sounds good. See you tomorrow.", "Sounds good. See you tomorrow", "sounds good. see you tomorrow"),
            ("kommst du? ich warte.", "Kommst du? Ich warte", "kommst du? ich warte"),
            ("hallo! alles gut?", "Hallo! Alles gut?", "hallo! alles gut?"),
            ("ich nutze iPhone und GitHub.", "Ich nutze iPhone und GitHub", "ich nutze iphone und github"),
            ("ich komme um 13 Uhr bzw. etwas später.", "Ich komme um 13 Uhr bzw. etwas später", "ich komme um 13 uhr bzw. etwas später"),
            ("  klingt gut . dann bis morgen . \n", "Klingt gut. Dann bis morgen", "klingt gut. dann bis morgen"),
            ("", "", ""),
        ]
        for (raw, casual, veryCasual) in cases {
            XCTAssertEqual(TranscriptFormatter.format(raw, style: .casual), casual, raw)
            XCTAssertEqual(TranscriptFormatter.format(raw, style: .veryCasual), veryCasual, raw)
        }
    }

    func testOldStoredCasualValueKeepsLowercaseBehavior() throws {
        XCTAssertEqual(DictationStyle(rawValue: "casual"), .veryCasual)
        XCTAssertEqual(try JSONDecoder().decode(DictationStyle.self, from: Data("\"casual\"".utf8)), .veryCasual)
        XCTAssertEqual(DictationStyle.veryCasual.label, "Very casual")
        XCTAssertEqual(DictationStyle.casual.label, "Casual")
        for style in DictationStyle.allCases {
            XCTAssertEqual(try JSONDecoder().decode(DictationStyle.self, from: JSONEncoder().encode(style)), style)
            XCTAssertEqual(DictationStyle(rawValue: style.rawValue), style)
            let request = KeyboardLaunchRequest.startRecording(jobID: "style-test", requestedAt: 100, style: style, host: nil)
            XCTAssertEqual(KeyboardLaunchRequest(url: request.url), request)
        }
    }

    @MainActor
    func testCapturedLogStylesCannotCollideWithHistoricalCasualLabel() throws {
        for (style, expected) in [(DictationStyle.casual, "Casual (natural case)"),
                                  (.veryCasual, "Very casual")] {
            let context = DictationLogContext.capture(
                keyboardJob: false, copyToPasteboard: false, style: style,
                engine: "test", language: "de", duration: 1,
                loudestAverage: nil, cleanupPath: .none, vocabularyCount: 0
            )
            XCTAssertEqual(context.style, expected)
            XCTAssertNotEqual(context.style, "Casual")
            let decoded = try JSONDecoder().decode(DictationLogContext.self, from: JSONEncoder().encode(context))
            XCTAssertEqual(decoded.style, expected)
        }
        var historic = DictationLogContext()
        historic.style = "Casual"
        let decoded = try JSONDecoder().decode(DictationLogContext.self, from: JSONEncoder().encode(historic))
        XCTAssertEqual(decoded.style, "Casual")
    }

    @MainActor
    func testSavedStyleSelectionAndCycleIncludeBothChatStyles() {
        let suite = "typr.tests.casual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bridge = KeyboardBridge(defaults: defaults)
        bridge.style = .veryCasual
        XCTAssertEqual(KeyboardBridge(defaults: defaults).style, .veryCasual)
        bridge.style = .casual
        XCTAssertEqual(KeyboardBridge(defaults: defaults).style, .casual)
        XCTAssertEqual(DictationStyle.polished.next, .casual)
        XCTAssertEqual(DictationStyle.casual.next, .veryCasual)
        XCTAssertEqual(DictationStyle.veryCasual.next, .notes)
    }
}
