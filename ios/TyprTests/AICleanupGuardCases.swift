import XCTest
@testable import Typr

final class AICleanupGuardCases: XCTestCase {
    func testAcceptedCleanups() {
        let cases: [(String, String)] = [
            // The owner's iPhone dictations (2026-11-08).
            ("Dienstag, nein Mittwoch, nein Freitag.", "Freitag."),
            ("Wir treffen uns um 13:00 Uhr nein besser um 14:00 Uhr.", "Wir treffen uns um 14:00 Uhr."),
            ("Wir treffen uns um 13:00 Uhr nein besser um 14:00 Uhr.", "Wir treffen uns um 14 Uhr."),
            ("am Dienstag, nein, am Mittwoch", "am Mittwoch"),
            ("Ich komme morgen, äh nein, übermorgen.", "Ich komme übermorgen."),
            ("Ruf Peter an, ich meine Anna.", "Ruf Anna an."),
            ("150 Euro, nein 250 Euro", "250 Euro"),
            ("Die Katze sitzt auf der Mathe", "Die Katze sitzt auf der Matte."),
            ("Ähm ich ich wollte fragen ob du heute Zeit hast", "Ich wollte fragen, ob du heute Zeit hast."),
            ("Send it to Tom, no wait, to Jerry.", "Send it to Jerry."),
            ("The call is at nine, actually ten.", "The call is at ten."),
            ("schreib an kit@example.com bis 5 Uhr", "Schreib an kit@example.com bis 5 Uhr."),
            ("Was ist die Hauptstadt von Frankreich", "Was ist die Hauptstadt von Frankreich?")
        ]
        for (input, output) in cases {
            XCTAssertNil(CleanupGuard.rejection(input: input, output: output, style: .polished), "\(input) => \(output)")
            XCTAssertTrue(CleanupGuard.accepts(input: input, output: output, style: .polished), "\(input) => \(output)")
        }
    }

    func testRejectedAnswersAndInventions() {
        let cases: [(String, String, CleanupGuardRule)] = [
            ("150 Euro", "950 Euro", .newValue),
            ("Wir treffen uns um 14:00 Uhr", "Wir treffen uns um 15:00 Uhr", .newValue),
            ("Schreib an kit@example.com", "Schreib an kat@example.com", .newValue),
            ("Was ist die Hauptstadt von Frankreich", "Die Hauptstadt von Frankreich ist Paris, eine Stadt an der Seine.", .grew),
            ("Schreib mir eine Mail an Anna wegen morgen", "Liebe Anna, ich wollte dich wegen morgen fragen, ob es dabei bleibt.", .grew),
            ("Erstelle bitte einen Pull Request für den Branch", "Erstelle bitte einen Pull Request für den Branch. Erstelle bitte einen Pull Request für den Branch.", .duplicated)
        ]
        for (input, output, rule) in cases {
            XCTAssertEqual(CleanupGuard.rejection(input: input, output: output, style: .polished), rule, "\(input) => \(output)")
            XCTAssertFalse(CleanupGuard.accepts(input: input, output: output, style: .polished), "\(input) => \(output)")
        }
        XCTAssertFalse(CleanupGuard.accepts(input: "Die Katze sitzt", output: "  \n", style: .polished))
    }

    func testNotesKeepTheirMarkerWords() {
        let input = "bullet Milch nein Brot new line Anna anrufen"
        XCTAssertNil(CleanupGuard.rejection(input: input, output: "bullet Brot new line Anna anrufen", style: .notes))
        XCTAssertEqual(CleanupGuard.rejection(input: input, output: "- Brot\nAnna anrufen", style: .notes), .notesMarkers)
        // Other styles have no marker rule.
        XCTAssertNil(CleanupGuard.rejection(input: input, output: "Brot, Anna anrufen", style: .polished))
        XCTAssertEqual(CleanupGuard.markerCounts("next bullet a bullet point b new line"), ["next bullet": 1, "bullet point": 1, "new line": 1])
    }

    func testValuesAndWords() {
        XCTAssertEqual(CleanupGuard.values("um 14:00 Uhr, siehe https://example.org/a. oder a@b.de"),
                       ["14", "00", "https://example.org/a", "a@b.de"])
        XCTAssertEqual(CleanupGuard.words("Ähm, ich ICH"), ["ähm", "ich", "ich"])
        XCTAssertEqual(CleanupGuard.wordCount("Dienstag, nein Mittwoch"), 3)
    }

    /// Every example the model is shown must be one the guard accepts.
    func testPromptExamplesPassTheGuard() {
        let examples = CleanupPrompt.instructions.split(separator: "\n").compactMap { line -> (String, String)? in
            guard !line.hasPrefix("EXAMPLES") else { return nil }
            let parts = line.components(separatedBy: " => ")
            return parts.count == 2 ? (parts[0].trimmingCharacters(in: .whitespaces), parts[1]) : nil
        }
        XCTAssertGreaterThanOrEqual(examples.count, 10)
        for (input, output) in examples {
            XCTAssertTrue(CleanupGuard.accepts(input: input, output: output, style: .polished), "\(input) => \(output)")
        }
    }
}
