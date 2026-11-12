import UIKit
import XCTest
@testable import Typr

@MainActor
final class AutocorrectEngineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var target: FixtureTextTarget!
    private var engine: FullKeyboardEngine!
    private var now: TimeInterval = 200

    override func setUp() async throws {
        suiteName = "AutocorrectEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let session = KeyboardLearningSession(defaults: defaults)
        let autocorrect = AutocorrectEngine(checker: SystemTextChecker(), learning: session, spatialDecoder: nil)
        engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func tap(_ kind: KeyKind) {
        let key = engine.layout.key(kind)!
        let center = CGPoint(x: key.frame.midX, y: key.frame.midY)
        engine.touchBegan(id: 1, at: center)
        engine.touchEnded(id: 1, at: center)
        now += 0.45
    }

    private func typeWord(_ word: String) {
        for ch in word {
            if ch.isUppercase {
                tap(.shift)
                tap(.character(ch.lowercased()))
            } else if ch == " " {
                tap(.space)
            } else {
                tap(.character(String(ch)))
            }
        }
    }

    func testLexiconHopDeliversOnMainFromBackgroundQueue() {
        let delivered = expectation(description: "delivered on main")
        let entries = [LexiconEntry(userInput: "omw", documentText: "On my way!")]
        DispatchQueue.global().async {
            LexiconDelivery.hop(entries) { received in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(received, entries)
                delivered.fulfill()
            }
        }
        wait(for: [delivered], timeout: 2)
    }

    func testLexiconEntriesLoadShortcut() {
        engine.autocorrect.loadLexiconEntries([LexiconEntry(userInput: "omw", documentText: "On my way!")])
        XCTAssertEqual(engine.autocorrect.lexiconShortcuts["omw"], "On my way!")
    }

    func testFiftyWordAndContextCases() {
        engine.autocorrect.loadLexiconEntries([
            ("omw", "On my way!"),
            ("addr", "123 Market St"),
            ("Kit", "Kit"),
        ])

        // 1–25: Contractions, transpositions, shortcuts, and casing that MUST auto-replace on space.
        let replacements: [(String, String)] = [
            ("i", "I"),
            ("im", "I'm"),
            ("ive", "I've"),
            ("dont", "don't"),
            ("Dont", "Don't"),
            ("DONT", "DON'T"),
            ("cant", "can't"),
            ("wont", "won't"),
            ("didnt", "didn't"),
            ("doesnt", "doesn't"),
            ("isnt", "isn't"),
            ("youre", "you're"),
            ("theyre", "they're"),
            ("thats", "that's"),
            ("oclock", "o'clock"),
            ("teh", "the"),
            ("Teh", "The"),
            ("TEH", "THE"),
            ("taht", "that"),
            ("adn", "and"),
            ("wiht", "with"),
            ("recieve", "receive"),
            ("keybaord", "keyboard"),
            ("iphnoe", "iPhone"),
            ("omw", "On my way!"),
        ]
        for (typed, expected) in replacements {
            let actual = engine.autocorrect.replacementOnSpace(
                beforeInput: typed,
                field: .text,
                autocorrectionType: .default
            )
            XCTAssertEqual(actual?.replacement, expected, "expected \(typed) -> \(expected)")
        }

        // 26–52: Valid English words, ambiguous words, acronyms, PascalCase, shorthand, and non-prose contexts that MUST stay untouched.
        let untouched: [(String, KeyboardFieldKind, UITextAutocorrectionType)] = [
            ("the", .text, .default),
            ("from", .text, .default),
            ("form", .text, .default),
            ("their", .text, .default),
            ("there", .text, .default),
            ("were", .text, .default),
            ("well", .text, .default),
            ("ill", .text, .default),
            ("its", .text, .default),
            ("lets", .text, .default),
            ("running", .text, .default),
            ("late", .text, .default),
            ("tonight", .text, .default),
            ("thx", .text, .default),
            ("pls", .text, .default),
            ("tmrw", .text, .default),
            ("tbh", .text, .default),
            ("idk", .text, .default),
            ("lmao", .text, .default),
            ("ios", .text, .default),
            ("hex", .text, .default),
            ("API", .text, .default),
            ("NYC", .text, .default),
            ("TyprKey", .text, .default),
            ("@teh", .text, .default),
            ("https://anoma.ly/teh", .text, .default),
            ("teh", .email, .default),
            ("teh", .url, .default),
            ("teh", .text, .no),
        ]
        for (context, field, mode) in untouched {
            let actual = engine.autocorrect.replacementOnSpace(
                beforeInput: context,
                field: field,
                autocorrectionType: mode
            )
            XCTAssertNil(actual, "expected \(context) (\(field)) to stay untouched, got \(String(describing: actual))")
        }
    }

    func testAmbiguousContractionsSuggestWithoutAutoReplacing() {
        let slots = engine.autocorrect.suggestions(
            beforeInput: "well",
            field: .text,
            autocorrectionType: .default
        )
        XCTAssertEqual(slots.first?.displayText, "“well”")
        XCTAssertEqual(slots.dropFirst().first?.replacement, "we'll")
        XCTAssertEqual(slots.dropFirst().first?.willAutoReplace, false)
    }

    func testSpaceDeleteSpaceKeepLoopAndPersonalProtection() async {
        typeWord("teh")
        await engine.waitForSuggestions()
        XCTAssertEqual(engine.suggestions.count >= 2, true)
        XCTAssertEqual(engine.suggestions[0].kind, .keepLiteral)
        XCTAssertEqual(engine.suggestions[1].replacement, "the")
        XCTAssertTrue(engine.suggestions[1].willAutoReplace)

        // 1. Space applies cautious autocorrect (`teh` -> `the `).
        tap(.space)
        XCTAssertEqual(target.text, "the ")

        // 2. Single Backspace reverts `the ` -> `teh` and suppresses `"teh"` for this session.
        tap(.delete)
        XCTAssertEqual(target.text, "teh")

        // 3. Pressing Space again keeps `teh ` untouched!
        tap(.space)
        XCTAssertEqual(target.text, "teh ")

        // 4. A literal chip keeps the protection and records an independent trusted choice.
        typeWord("teh")
        engine.acceptSuggestion(engine.suggestions[0])
        XCTAssertEqual(target.text, "teh teh ")
        XCTAssertTrue(engine.autocorrect.learning.model.lexicon.isKept("teh"))
        XCTAssertEqual(engine.autocorrect.learning.model.lexicon.counts["teh"], 1)
    }

    func testQwertyAdjacencyPrefersPhysicalNeighbor() {
        let near = AutocorrectEngine.singleEditKeyboardCost(from: "tge", to: "the")!
        let far = AutocorrectEngine.singleEditKeyboardCost(from: "tpe", to: "the")!
        XCTAssertLessThan(near, far, "g is adjacent to h; p is across the keyboard")
        XCTAssertNil(AutocorrectEngine.singleEditKeyboardCost(from: "abcdef", to: "abxyef"), "two substitutions are rejected")
    }

    func testTurningAutocorrectSettingOffKeepsSuggestionsWithoutAutoReplacing() async {
        engine.autocorrect.isEnabled = false
        // A deterministic prefix suggestion proves this is the finished strip even with the
        // Linux checker adapter. Automatic contraction of "dont" must still be disabled.
        engine.autocorrect.loadLexiconEntries([("dontcare", "dontcare")])
        typeWord("dont")
        // The finished ranking, not the interim literal chips.
        await engine.waitForSuggestions()
        XCTAssertFalse(engine.suggestions.isEmpty)
        XCTAssertEqual(engine.suggestions[1].replacement, "dontcare")
        XCTAssertEqual(engine.suggestions[1].kind, .primary(autoReplace: false))
        XCTAssertTrue(engine.suggestions[1].isCompletion)
        XCTAssertFalse(engine.suggestions.contains(where: \.willAutoReplace))
        tap(.space)
        XCTAssertEqual(target.text, "dont ")
    }
}
