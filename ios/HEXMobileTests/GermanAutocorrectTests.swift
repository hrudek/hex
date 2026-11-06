import UIKit
import XCTest
@testable import HEX

@MainActor
private final class FakeTextChecker: TextChecking {
    var valid: Set<String>
    var guessTable: [String: [String]]

    init(valid: Set<String> = [], guesses: [String: [String]] = [:]) {
        self.valid = valid
        self.guessTable = guesses
    }

    func isWordValid(_ word: String) -> Bool { valid.contains(word) }
    func guesses(for word: String) -> [String] { guessTable[word] ?? [] }
    func completions(for prefix: String) -> [String] { [] }
}

@MainActor
final class GermanAutocorrectTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now: TimeInterval = 200

    override func setUp() async throws {
        suiteName = "GermanAutocorrectTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeEngine(
        english: Set<String> = ["does", "blue", "queue", "I'm", "the"],
        german: Set<String> = ["neue", "Feuer", "dass", "im"],
        germanGuesses: [String: [String]] = [:],
        germanOn: Bool = true
    ) -> AutocorrectEngine {
        let engine = AutocorrectEngine(
            checker: FakeTextChecker(valid: english),
            learnedWords: LearnedWordsStore(defaults: defaults)
        )
        if germanOn {
            engine.german = GermanAutocorrect(checker: FakeTextChecker(valid: german, guesses: germanGuesses))
        }
        return engine
    }

    private func fix(_ engine: AutocorrectEngine, _ word: String) -> String? {
        engine.replacementOnSpace(beforeInput: word, field: .text, autocorrectionType: .default)?.replacement
    }

    func testTableAndCasing() {
        let engine = makeEngine()
        XCTAssertEqual(fix(engine, "fuer"), "für")
        XCTAssertEqual(fix(engine, "Fuer"), "Für")
        XCTAssertEqual(fix(engine, "FUER"), "FÜR")
        XCTAssertEqual(fix(engine, "ueber"), "über")
        XCTAssertEqual(fix(engine, "strasse"), "straße")
    }

    func testDictionaryPath() {
        let engine = makeEngine(german: ["Brücke"])
        XCTAssertEqual(fix(engine, "bruecke"), "Brücke")
    }

    func testValidWordsAreLeftAlone() {
        let engine = makeEngine()
        for word in ["neue", "Feuer", "dass", "does", "blue", "queue"] {
            XCTAssertNil(fix(engine, word), word)
        }
    }

    func testImStaysWithGermanButContractsWithout() {
        XCTAssertNil(fix(makeEngine(), "im"))
        XCTAssertEqual(fix(makeEngine(germanOn: false), "im"), "I'm")
    }

    func testSwitchOffDoesNotTouchUmlauts() {
        XCTAssertNil(fix(makeEngine(germanOn: false), "fuer"))
    }

    func testLearnedWordIsNotRewritten() {
        let engine = makeEngine()
        engine.learnedWords.learn("fuer")
        XCTAssertNil(fix(engine, "fuer"))
    }

    func testUmlautAwareTypoCost() {
        let german = GermanAutocorrect(checker: FakeTextChecker())
        XCTAssertEqual(german.costAdjustedForUmlauts(from: "fur", to: "für"), 0.4)
        XCTAssertNotNil(german.costAdjustedForUmlauts(from: "brucke", to: "brücke"))
    }

    func testGermanTypoGuess() {
        let engine = makeEngine(german: ["Haus"], germanGuesses: ["hasu": ["Haus"]])
        XCTAssertEqual(fix(engine, "hasu"), "Haus")
    }

    func testEngineTypesUmlautAndBackspaceReverts() {
        let target = FixtureTextTarget()
        target.autocapitalizationType = UITextAutocapitalizationType.none
        let autocorrect = makeEngine()
        let engine = FullKeyboardEngine(target: target, autocorrect: autocorrect)
        engine.width = 393
        engine.clock = { [unowned self] in self.now }
        engine.configureForField()

        func tap(_ kind: KeyKind) {
            let key = engine.layout.key(kind)!
            let center = CGPoint(x: key.frame.midX, y: key.frame.midY)
            engine.touchBegan(id: 1, at: center)
            engine.touchEnded(id: 1, at: center)
            now += 0.45
        }
        for ch in "fuer" { tap(.character(String(ch))) }
        tap(.space)
        XCTAssertEqual(target.text, "für ")
        tap(.delete)
        XCTAssertEqual(target.text, "fuer")
    }

    func testSettingsDefaultOnAndPersist() {
        let settings = HexPlusSettings(defaults: defaults)
        XCTAssertTrue(settings.germanAutocorrect)
        settings.germanAutocorrect = false
        XCTAssertFalse(HexPlusSettings(defaults: defaults).germanAutocorrect)
    }

    func testRealDictionary() throws {
        guard UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("de") }) else {
            throw XCTSkip("No German dictionary on this simulator")
        }
        let engine = AutocorrectEngine(learnedWords: LearnedWordsStore(defaults: defaults))
        engine.german = GermanAutocorrect.system()
        XCTAssertEqual(fix(engine, "fuer"), "für")
        XCTAssertNil(fix(engine, "neue"))
    }
}
