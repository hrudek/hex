import UIKit
import XCTest
@testable import HEX

/// A checker with fixed word lists, so the German-and-English rules run without UIKit's dictionaries.
@MainActor
private final class FixedChecker: TextChecking {
    var english: Set<String> = []
    var other: Set<String> = []
    var guessList: [String: [String]] = [:]

    func isWordValid(_ word: String) -> Bool {
        english.contains(word.lowercased()) || isValidOutsideEnglish(word)
    }
    func guesses(for word: String) -> [String] { guessList[word.lowercased()] ?? [] }
    func completions(for prefix: String) -> [String] { [] }
    /// Exact spelling (a German noun such as `Größe`) or its lowercase form.
    func isValidOutsideEnglish(_ word: String) -> Bool { other.contains(word) || other.contains(word.lowercased()) }
}

@MainActor
final class MultilingualAutocorrectTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "MultilingualAutocorrectTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func engine(_ checker: TextChecking) -> AutocorrectEngine {
        AutocorrectEngine(checker: checker, learnedWords: LearnedWordsStore(defaults: defaults))
    }

    private func spaceFix(_ engine: AutocorrectEngine, after text: String) -> String? {
        engine.replacementOnSpace(beforeInput: text, field: .text, autocorrectionType: .default)?.replacement
    }

    func testEnglishOnlyFixLeavesAGermanWordAlone() {
        let checker = FixedChecker()
        checker.other = ["im", "wich"]
        let autocorrect = engine(checker)
        XCTAssertNil(spaceFix(autocorrect, after: "Ich bin im"))
        XCTAssertNil(spaceFix(autocorrect, after: "er wich"))
        XCTAssertEqual(spaceFix(autocorrect, after: "I think teh"), "the")
    }

    func testEnglishOnlyFixStillAppliesWithoutAnotherLanguage() {
        let autocorrect = engine(FixedChecker())
        XCTAssertEqual(spaceFix(autocorrect, after: "yes im"), "I'm")
    }

    func testMissingUmlautIsCorrected() {
        let checker = FixedChecker()
        checker.other = ["grün", "für"]
        checker.guessList = ["grun": ["grün", "grub"]]
        XCTAssertEqual(spaceFix(engine(checker), after: "das ist grun"), "grün")
    }

    func testUmlautCostsLessThanADistantKey() {
        let umlaut = AutocorrectEngine.singleEditKeyboardCost(from: "grun", to: "grün")!
        let distant = AutocorrectEngine.singleEditKeyboardCost(from: "grun", to: "gran")!
        XCTAssertLessThan(umlaut, distant)
    }

    func testGermanWordWithSeveralTyposIsCorrected() {
        let checker = FixedChecker()
        checker.other = ["vielleicht", "entschuldigung"]
        checker.guessList = [
            "vileicht": ["vielleicht"],
            "entschudlgiung": ["Entschuldigung"],
        ]
        let autocorrect = engine(checker)
        XCTAssertEqual(spaceFix(autocorrect, after: "ja vileicht"), "vielleicht")
        XCTAssertEqual(spaceFix(autocorrect, after: "entschudlgiung"), "Entschuldigung")
    }

    func testCommonGermanSlipsAreFixed() {
        let autocorrect = engine(FixedChecker())
        XCTAssertEqual(spaceFix(autocorrect, after: "das ist nciht"), "nicht")
        XCTAssertEqual(spaceFix(autocorrect, after: "Udn"), "Und")
        XCTAssertEqual(spaceFix(autocorrect, after: "ihc"), "ich")
    }

    func testGermanWithoutUmlautsOrSharpSIsSpelledProperly() {
        let checker = FixedChecker()
        checker.other = ["schön", "straße", "Größe"]
        let autocorrect = engine(checker)
        XCTAssertEqual(spaceFix(autocorrect, after: "sehr schoen"), "schön")
        XCTAssertEqual(spaceFix(autocorrect, after: "die strasse"), "straße")
        XCTAssertEqual(spaceFix(autocorrect, after: "die groesse"), "Größe")
    }

    func testUnrelatedGuessIsNotForced() {
        let checker = FixedChecker()
        checker.guessList = ["qwrt": ["house"]]
        let autocorrect = engine(checker)
        XCTAssertNil(spaceFix(autocorrect, after: "qwrt"))
    }

    func testKeyboardEditCostAllowsSeveralCheapEdits() {
        XCTAssertEqual(AutocorrectEngine.keyboardEditCost(from: "shcreiben", to: "schreiben")!, 0.6, accuracy: 0.001)
        XCTAssertLessThan(AutocorrectEngine.keyboardEditCost(from: "ueber", to: "über")!, 0.5)
        XCTAssertLessThan(AutocorrectEngine.keyboardEditCost(from: "zusamen", to: "zusammen")!, 0.7)
        let twoTypos = AutocorrectEngine.keyboardEditCost(from: "vileicht", to: "vielleicht")!
        XCTAssertLessThanOrEqual(twoTypos, AutocorrectEngine.correctionBudget(forLength: 8))
        XCTAssertNil(AutocorrectEngine.keyboardEditCost(from: "qwrt", to: "house"))
    }

    func testMissingSpaceIsInserted() {
        let checker = FixedChecker()
        checker.other = ["wie", "geht", "das", "Haus", "ich", "habe"]
        let autocorrect = engine(checker)
        XCTAssertEqual(spaceFix(autocorrect, after: "hallo wiegehts"), "wie geht's")
        XCTAssertEqual(spaceFix(autocorrect, after: "Wiegehts"), "Wie geht's")
        XCTAssertEqual(spaceFix(autocorrect, after: "dashaus"), "das Haus")
        XCTAssertEqual(spaceFix(autocorrect, after: "ichhabe"), "ich habe")
    }

    func testMissingSpaceWithATypoInOneHalf() {
        let checker = FixedChecker()
        checker.other = ["wie", "ich", "habe"]
        checker.guessList = ["geths": ["geht's"], "hbae": ["habe"]]
        let autocorrect = engine(checker)
        XCTAssertEqual(spaceFix(autocorrect, after: "wiegeths"), "wie geht's")
        XCTAssertEqual(spaceFix(autocorrect, after: "ichhbae"), "ich habe")
    }

    func testGermanCompoundIsNotSplit() {
        let checker = FixedChecker()
        checker.other = ["Haus", "Boot"]
        XCTAssertNil(spaceFix(engine(checker), after: "das hausboot"))
    }

    func testContactNameIsNotSplit() {
        let checker = FixedChecker()
        checker.other = ["mich"]
        checker.guessList = ["aela": ["aale"]]
        let autocorrect = engine(checker)
        autocorrect.loadLexiconEntries([("Michaela", "Michaela")])
        XCTAssertNil(spaceFix(autocorrect, after: "Michaela"))
    }

    func testTypingLanguagesPutKeyboardsFirstAndAlwaysIncludeEnglish() {
        let available = ["en_US", "en_GB", "de_DE", "fr_FR", "es_ES"]
        XCTAssertEqual(
            SystemTextChecker.typingLanguages(preferred: ["de-DE"], keyboards: [], available: available),
            ["de_DE", "en_US"]
        )
        XCTAssertEqual(
            SystemTextChecker.typingLanguages(preferred: ["en-GB"], keyboards: ["de-DE", "en-US"], available: available),
            ["de_DE", "en_US"]
        )
        XCTAssertEqual(
            SystemTextChecker.typingLanguages(preferred: ["de-AT", "fr-FR", "es-ES"], keyboards: [], available: available),
            ["de_DE", "fr_FR", "es_ES"]
        )
        XCTAssertEqual(SystemTextChecker.typingLanguages(preferred: [], keyboards: [], available: available), ["en_US"])
    }

    func testInterleaveTakesEachLanguagesBestFirst() {
        XCTAssertEqual(
            SystemTextChecker.interleave([["haus", "hans"], ["house", "Haus", "hose"]]),
            ["haus", "house", "hans", "hose"]
        )
    }

    func testSystemDictionariesAcceptBothLanguages() throws {
        let checker = SystemTextChecker(languages: ["de_DE", "en_US"])
        try XCTSkipUnless(UITextChecker.availableLanguages.contains("de_DE"), "no German dictionary")
        XCTAssertTrue(checker.isWordValid("Straße"))
        XCTAssertTrue(checker.isWordValid("keyboard"))
        XCTAssertTrue(checker.isValidOutsideEnglish("im"))
        XCTAssertFalse(checker.isValidOutsideEnglish("keyboard"))
    }
}
