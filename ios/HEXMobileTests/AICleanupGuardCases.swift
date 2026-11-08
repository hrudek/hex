import XCTest
@testable import HEX

final class AICleanupGuardCases: XCTestCase {
    func testAcceptedLocalFixesAndCuedRetractions() {
        let cases: [(String, String)] = [
            ("am Dienstag, nein, am Mittwoch", "am Mittwoch"),
            ("Dienstag nein Mittwoch nein Freitag", "Freitag"),
            ("nicht Dienstag, ich meine Mittwoch", "Mittwoch"),
            ("Die Katze sitzt auf der Mathe", "Die Katze sitzt auf der Matte"),
            ("150 Euro, nein 250 Euro", "250 Euro"),
            ("am am Dienstag nein am am Mittwoch", "am am Mittwoch"),
            ("rot nein blau und klein nein groß", "blau und groß"),
            ("a b nein a b korrektur a b c", "a b c"),
            ("5 % Rabatt", "5% Rabatt"),
            ("Heute bitte Anna anrufen!", "heute bitte Anna anrufen."),
            ("https://example.org/test. bleibt", "https://example.org/test bleibt"),
            // Owner's iPhone dictations (2026-11-08) and the cue phrases added for them.
            ("Wir treffen uns um 13:00 Uhr nein besser um 14:00 Uhr.", "Wir treffen uns um 14:00 Uhr."),
            ("Dienstag, nein Mittwoch, nein Freitag.", "Freitag."),
            ("Ich komme morgen, nein übermorgen.", "Ich komme übermorgen."),
            ("Ruf Peter an, ach nein, ruf Anna an.", "Ruf Anna an."),
            ("Das kostet 20 Euro, besser gesagt 25 Euro.", "Das kostet 25 Euro."),
            ("Send it to Tom, no wait, to Jerry.", "Send it to Jerry."),
            ("Meet at five, or rather at six.", "Meet at six.")
        ]
        for (input, output) in cases {
            XCTAssertTrue(CleanupGuard.accepts(input: input, output: output, style: .polished), "\(input) => \(output)")
        }
    }

    func testRejectedChanges() {
        let cases: [(String, String)] = [
            ("Kaffee oder lieber Tee?", "Tee?"),
            ("Nein besser nicht", "nicht"),
            ("Wir treffen uns um 13:00 Uhr nein besser um 14:00 Uhr.", "Wir treffen uns um 13:00 Uhr."),
            ("150 Euro", "950 Euro"),
            ("Überweise 150 Euro", "Überweise Euro"),
            ("Anna bekommt 150, Peter 950", "Anna bekommt 950, Peter 150"),
            ("No, do not send the invoice", "Do send the invoice"),
            ("Sorry, bitte nicht löschen", "Bitte löschen"),
            ("Bitte nicht löschen, sorry für die Umstände", "Bitte für die Umstände"),
            ("Nicht Anna, sondern Peter anrufen", "Anna, nicht Peter anrufen"),
            ("Bitte überweise heute 150 Euro an Anna und ruf danach Peter an", "Bitte ruf Anna an"),
            ("Hallo", "Alles erledigt"),
            ("Was ist die Hauptstadt von Frankreich", "Paris ist die Hauptstadt von Frankreich"),
            ("What is the capital of France", "Paris is the capital of France"),
            ("Was ist die Hauptstadt von Frankreich", "Die Hauptstadt von Frankreich ist Paris"),
            ("Bitte heute Anna und Peter anrufen", "Bitte heute Anna"),
            ("Anna und Peter anrufen", "Peter und Anna anrufen"),
            ("bullet call Anna", "new line call Anna"),
            ("Anna anrufen", "Anna sofort anrufen"),
            ("Dienstag nein nein Mittwoch", "Mittwoch"),
            ("Dienstag nein Mittwoch heute", "heute"),
            ("Dienstag nein", ""),
            ("eins zwei drei vier fünf sechs sieben acht nein Mittwoch", "Mittwoch"),
            ("a nein b nein c nein d nein e nein f", "f"),
            ("@Anna bitte anrufen", "@anna bitte anrufen"),
            ("mail a@b.de bitte", "mail c@b.de bitte"),
            ("heute #Wichtig bitte", "heute #wichtig bitte"),
            ("nicht löschen", "jetzt löschen"),
            ("do not delete", "do now delete"),
            ("I cannot go", "I can go"),
            ("I wouldn't go", "I would go"),
            ("rot nein blau und grün", "blau")
        ]
        for (input, output) in cases {
            XCTAssertFalse(CleanupGuard.accepts(input: input, output: output, style: .polished), "\(input) => \(output)")
        }
    }

    func testNotesAnchorsAndMarkers() {
        XCTAssertTrue(CleanupGuard.accepts(input: "bullet Dienstag nein Mittwoch\nnew line Mathe",
                                          output: "bullet Mittwoch\nnew line Matte", style: .notes))
        for output in ["bullet Mittwoch new line Matte", "bullet\nMittwoch new line Matte", "Mittwoch\nnew line Matte"] {
            XCTAssertFalse(CleanupGuard.accepts(input: "bullet Dienstag nein Mittwoch\nnew line Mathe", output: output, style: .notes))
        }
        XCTAssertFalse(CleanupGuard.accepts(input: "Dienstag nein\nMittwoch", output: "\nMittwoch", style: .notes))
    }

    func testProtectedTokenPrepassAndSpans() {
        let text = "-5 1.000,50 12:30 5 % https://example.org. a@b.de @Anna #Tag"
        let tokens = CleanupGuard.tokens(text)
        XCTAssertEqual(tokens.map(\.key), ["-5", "1.000,50", "12:30", "5%", "https://example.org", "a@b.de", "@Anna", "#Tag"])
        XCTAssertTrue(tokens.allSatisfy(\.protected))
        XCTAssertEqual(String(text[tokens[3].span]), "5 %")
    }

    /// Every changed example the model is shown must be one the guard accepts, or the model learns rejected edits.
    func testPromptExamplesPassTheGuard() {
        let examples = CleanupPrompt.instructions.split(separator: "\n").compactMap { line -> (String, String)? in
            guard !line.hasPrefix("Examples") else { return nil }
            let parts = line.components(separatedBy: " => ")
            return parts.count == 2 ? (parts[0].trimmingCharacters(in: .whitespaces), parts[1]) : nil
        }
        XCTAssertGreaterThanOrEqual(examples.count, 10)
        for (input, output) in examples {
            XCTAssertTrue(CleanupGuard.accepts(input: input, output: output, style: .polished), "\(input) => \(output)")
        }
    }
}
