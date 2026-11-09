import XCTest
@testable import Typr

final class HostReturnCatalogTests: XCTestCase {
    func testResumingSchemesAvoidThoseThatAct() {
        XCTAssertEqual(HostReturnCatalog.scheme(for: "com.apple.MobileSMS")?.absoluteString, "ichat://")
        XCTAssertEqual(HostReturnCatalog.scheme(for: "net.whatsapp.WhatsApp")?.absoluteString, "whatsapp-consumer://")
        XCTAssertEqual(HostReturnCatalog.scheme(for: "com.tinyspeck.chatlyio")?.absoluteString, "slack://open")
        // Every URL they register acts (a blank tab, a new chat): the swipe keeps the user's place.
        XCTAssertNil(HostReturnCatalog.scheme(for: "com.apple.mobilesafari"))
        XCTAssertNil(HostReturnCatalog.scheme(for: "com.anthropic.claude"))
        XCTAssertNil(HostReturnCatalog.scheme(for: HostReturnCatalog.typrBundleID))
    }

    func testAShareSheetExtendsItsAppAndAnotherAppDoesNot() {
        let apps = ["ph.telegra.Telegraph", "com.atebits.Tweetie2"]
        XCTAssertTrue(HostReturnCatalog.isExtension("ph.telegra.Telegraph.Share", ofAny: apps))
        XCTAssertFalse(HostReturnCatalog.isExtension("ph.telegra.Telegraph", ofAny: apps))
        XCTAssertFalse(HostReturnCatalog.isExtension("ph.telegra.TelegraphX", ofAny: apps))
        XCTAssertFalse(HostReturnCatalog.isExtension("net.whatsapp.WhatsApp", ofAny: apps))
    }

    func testTyprOpensOnlyFromHostsItCanReturnTo() {
        let installed: (String) -> Bool? = { id in
            switch id {
            case "com.apple.mobilenotes", "com.apple.mobilesafari": true
            case "com.apple.Spotlight", "com.apple.MobileSMS.notification": false
            default: nil
            }
        }
        func canReturn(_ host: String?, known: [String] = []) -> Bool {
            HostReturnCatalog.canReturn(to: host, knownApps: known, appleAppInstalled: installed)
        }

        // Unknown hosts may open Typr; the user swipes back.
        XCTAssertTrue(canReturn(nil))
        XCTAssertTrue(canReturn(""))
        // Apple apps installed in LaunchServices come back; system surfaces do not.
        XCTAssertTrue(canReturn("com.apple.mobilesafari"))
        XCTAssertFalse(canReturn("com.apple.Spotlight"))
        XCTAssertFalse(canReturn("com.apple.MobileSMS.notification"))
        // LaunchServices without an answer does not block.
        XCTAssertTrue(canReturn("com.apple.journal"))
        // A third-party share sheet of a catalogued or previously seen app is refused.
        XCTAssertFalse(canReturn("ph.telegra.Telegraph.Share"))
        XCTAssertFalse(canReturn("com.example.notes.ShareExtension", known: ["com.example.notes"]))
        XCTAssertTrue(canReturn("com.example.notes", known: ["com.example.notes"]))
        XCTAssertTrue(canReturn("com.example.other"))
        // Catalogued extensions that do come back, and Typr itself.
        XCTAssertTrue(canReturn("com.apple.mobilenotes.EditorExtension"))
        XCTAssertTrue(canReturn(HostReturnCatalog.typrBundleID))
    }

    func testHostIsTheNameKeptUnderTheHostProcessNeverTheLatestArbiterAnswer() {
        var table = HostProcessTable()
        table.record(processID: 101, bundleID: "com.apple.MobileSMS")
        // The arbiter later names an app the user already left; the host's process still answers right.
        table.record(processID: 202, bundleID: "com.openai.chat")
        XCTAssertEqual(table.host(processID: 101), "com.apple.MobileSMS")
        XCTAssertEqual(table.host(processID: 202), "com.openai.chat")
        // A process the arbiter never named is unknown, not guessed.
        XCTAssertNil(table.host(processID: 303))
        XCTAssertNil(table.host(processID: 0))
    }

    func testAProcessIDSeenWithTwoAppsAnswersNothing() {
        var table = HostProcessTable()
        table.record(processID: 101, bundleID: "com.apple.MobileSMS")
        table.record(processID: 101, bundleID: "com.apple.MobileSMS")
        XCTAssertEqual(table.host(processID: 101), "com.apple.MobileSMS")
        table.record(processID: 101, bundleID: "net.whatsapp.WhatsApp")
        XCTAssertNil(table.host(processID: 101))
        table.record(processID: 101, bundleID: "com.apple.MobileSMS")
        XCTAssertNil(table.host(processID: 101))

        table.reset()
        table.record(processID: 101, bundleID: "net.whatsapp.WhatsApp")
        XCTAssertEqual(table.host(processID: 101), "net.whatsapp.WhatsApp")
    }

    func testInvalidArbiterAnswersAreIgnored() {
        var table = HostProcessTable()
        table.record(processID: 0, bundleID: "com.apple.MobileSMS")
        table.record(processID: -1, bundleID: "com.apple.MobileSMS")
        table.record(processID: 5, bundleID: "")
        XCTAssertEqual(table, HostProcessTable())
    }
}
