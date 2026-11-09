import Foundation

/// The app the keyboard was typing in, named by its bundle ID, and the public way back into it.
///
/// After a cold-start dictation Typr returns to that app: first by bundle ID (private,
/// `Typr/HostReturner.swift`), then by a URL from `scheme(for:)`, else the user swipes back.
/// The keyboard learns the bundle ID from UIKit's keyboard arbiter (`TyprKeyboard/KeyboardHost.swift`).
///
/// The scheme table is translated from Dictus's `KnownAppSchemes`
/// (https://github.com/getdictus/dictus-ios, `DictusCore/Sources/DictusCore/KnownAppSchemes.swift`
/// at `8804c3629741b9aebe9475e0b2103769eb969dc5`, MIT), itself grown from VivaDicta
/// (https://github.com/n0an/VivaDicta, MIT). Its rule: a URL must bring the app back where
/// the user was, without navigating. Messages therefore uses `ichat://` (`sms://` and
/// `messages://` open a new message); Safari and Claude have no entry because every URL
/// they register acts (a blank tab, a new chat). Dictus's universal-link entries are left
/// out: a site's root URL is a navigation by construction.
nonisolated enum HostReturnCatalog {
    /// Typr's own app: a field inside Typr needs no return.
    static let typrBundleID = "dev.rudek.typr"

    static func scheme(for bundleID: String) -> URL? {
        schemes[bundleID].flatMap(URL.init(string:))
    }

    /// Apple has an extension's bundle ID start with its app's and a dot, so a host that
    /// extends one of `apps` is that app's share sheet or another of its extensions.
    static func isExtension(_ host: String, ofAny apps: some Sequence<String>) -> Bool {
        apps.contains { host.hasPrefix($0 + ".") }
    }

    /// Whether leaving `host` to start the microphone in Typr can bring the user back to it as
    /// they left it. A share sheet, a notification's reply, Spotlight or a markup editor closes
    /// once left, taking the text with it, and nothing reopens it. A keyboard sees Apple's
    /// installed apps in LaunchServices (`appleAppInstalled`, nil when unknown) but no
    /// third-party app, so a third-party host is refused only when it extends a known app
    /// (`knownApps`) — iikb's rule (https://github.com/AVGVSTVS96/iikb, MIT).
    /// An unknown host (nil) may open Typr; the user then swipes back.
    static func canReturn(
        to host: String?,
        knownApps: some Sequence<String>,
        appleAppInstalled: (String) -> Bool?
    ) -> Bool {
        guard let host, !host.isEmpty else { return true }
        if schemes[host] != nil || host == typrBundleID { return true }
        if host.hasPrefix("com.apple.") {
            return appleAppInstalled(host) ?? true
        }
        return !isExtension(host, ofAny: Array(schemes.keys) + Array(knownApps))
    }

    private static let schemes: [String: String] = [
        // Apple
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.mobilenotes.EditorExtension": "mobilenotes://",
        "com.apple.MobileSMS": "ichat://",
        "com.apple.mobilemail": "message://",
        "com.apple.Pages": "pages://",
        "com.apple.Numbers": "numbers://",
        "com.apple.Keynote": "keynote://",
        "com.apple.reminders": "x-apple-reminderkit://",
        "com.apple.shortcuts": "shortcuts://",
        "com.apple.Maps": "maps://",
        "com.apple.mobilecal": "calshow://",
        "com.apple.AppStore": "itms-apps://",
        "com.apple.Translate": "translate://",
        // Messaging
        "net.whatsapp.WhatsApp": "whatsapp-consumer://",
        "net.whatsapp.WhatsAppSMB": "whatsapp://",
        "com.telegram.telegram-ios": "tg://",
        "ph.telegra.Telegraph": "tg://",
        "app.swiftgram.ios": "sg://",
        "app.nicegram": "nicegram://",
        "com.tinyspeck.chatlyio": "slack://open",
        "com.hammerandchisel.discord": "discord://",
        "org.whispersystems.signal": "sgnl://",
        "ch.threema.iapp": "threema://",
        "com.facebook.Messenger": "fb-messenger://",
        "com.viber": "viber://",
        "com.microsoft.skype.teams": "msteams://",
        "com.mattermost.rn": "mattermost://",
        "io.element.elementx": "io.element.elementx://",
        "jp.naver.line": "line://",
        "com.iwilab.KakaoTalk": "kakaotalk://",
        "com.tencent.xin": "weixin://",
        "com.tencent.ww": "wxwork://",
        "com.vk.vkme": "vkme://",
        "com.automattic.beeper": "beeper://",
        "com.silentcircle.SilentPhone": "silentphone://",
        // Mail
        "com.google.Gmail": "googlegmail://",
        "com.microsoft.Office.Outlook": "ms-outlook://",
        "com.readdle.smartemail": "readdle-spark://",
        // Notes and writing
        "md.obsidian": "obsidian://",
        "notion.id": "notion://",
        "com.codality.NotationalFlow": "simplenote://",
        "com.culturedcode.ThingsiPhone": "things://",
        "com.agiletortoise.Drafts5": "drafts://",
        "pro.writer": "ia-writer://",
        "net.shinyfrog.bear-iOS": "bear://",
        "com.evernote.iPhone.Evernote": "evernote://",
        "com.google.Keep": "comgooglekeep://",
        "com.google.Docs": "googledocs://",
        "com.microsoft.Office.Word": "ms-word://",
        "com.logseq.logseq": "logseq://",
        "com.briansunter.logseq-dev": "logseq://",
        "co.fluder.mobile.FSNotes-iOS": "fsnotes://",
        "com.mem-labs.mem": "mem://",
        "net.ichi2.anki": "anki://",
        "com.overdesigned.Cheatsheet": "cheatsheet://",
        "io.raindrop.ios": "raindrop://",
        "h3p.Neon-Vision-Editor": "neonvisioneditor://",
        "com.linear.ios": "linear://",
        // AI assistants
        "com.openai.chat": "com.openai.chat://",
        "ai.perplexity.app": "perplexity-app://",
        "ai.x.GrokApp": "grok://",
        "com.google.gemini": "gemini-app://",
        "im.monica.app.monica": "monica://",
        "ai.pocketpal": "pocketpal://",
        "app.cogwheel.conduit": "conduit://",
        "psyche.kelivo": "kelivo://",
        "ai.openclawfoundation.app": "openclaw://",
        "com.ntoporcov.openclient": "openclient://",
        "com.ex3ndr.happy": "happy://",
        "sh.paseo": "paseo://",
        // Developer tools
        "com.t3tools.t3code": "t3code://",
        "com.github.stormbreaker.prod": "github://",
        "com.appliedphasor.secure-shellfish": "shellfish://",
        "com.crystalnix.ServerAuditor": "termius://",
        "com.stably.orca.mobile": "orca://",
        "xyz.block.buzz.mobile": "buzz://",
        "com.openminis.app": "minis://",
        // Social
        "com.atebits.Tweetie2": "twitter://",
        "com.burbn.instagram": "instagram://",
        "com.burbn.barcelona": "barcelona://",
        "com.facebook.Facebook": "fb://",
        "com.toyopagroup.picaboo": "snapchat://",
        "com.linkedin.LinkedIn": "linkedin://",
        "com.reddit.Reddit": "reddit://",
        "pinterest": "pinterest://",
        "com.xingin.discover": "xhsdiscover://",
        "com.cardify.tinder": "tinder://",
        "com.letterboxd.LetterboxdApp": "letterboxd://",
        // Browsers and Google
        "com.google.chrome.ios": "googlechrome://",
        "com.brave.ios.browser": "brave://",
        "org.mozilla.ios.Firefox": "firefox://",
        "company.thebrowser.ArcMobile2": "arcmobile2://",
        "ru.yandex.mobile.search": "yandexbrowser-open-url://",
        "com.google.OPA": "google://",
        "com.google.GoogleMobile": "googlemobileapp://",
        "com.google.Translate": "googletranslate://",
        "com.google.Maps": "comgooglemaps://",
        "com.google.ios.youtube": "youtube://",
        "ru.yandex.mobile.translate": "yandextranslate://",
        "eusoft.eudic.ip": "eudic://",
        // Other
        "com.spotify.client": "spotify://",
        "com.spotify.client.L32G8C83V9": "spotify://",
        "com.getdropbox.Dropbox": "dbapi-1://",
        "com.ubercab.UberClient": "uber://",
        "doordash.DoorDashConsumer": "doordash://",
        "com.ebay.iphone": "ebay://",
        "com.taobao.taobao4iphone": "taobao://",
        "com.meituan.imeituan": "imeituan://",
        "com.dianping.dpscope": "dianping://",
        "com.alibaba.sourcing": "enalibaba://",
        "com.xiaojukeji.didi": "diditaxi://",
        "com.newin.nplayer.basic": "nplayer-http://",
        "app.getmoshi.ios": "moshi://",
    ]
}

/// Process ID → bundle ID, learned from UIKit's keyboard arbiter, which sometimes names an
/// app the user already left. The host is the name kept under the keyboard's own host
/// process ID, never the arbiter's latest answer: that turns a wrong app into none
/// (Dictus measured 7 stale answers in 16 appearances; `_hostProcessIdentifier` was right
/// every time). A process ID seen with two bundle IDs answers nothing. Never persisted:
/// iOS reuses process IDs.
nonisolated struct HostProcessTable: Equatable, Sendable {
    private var names: [Int32: String] = [:]
    private var conflicting: Set<Int32> = []

    init() {}

    mutating func record(processID: Int32, bundleID: String) {
        guard processID > 0, !bundleID.isEmpty, !conflicting.contains(processID) else { return }
        if let known = names[processID], known != bundleID {
            names[processID] = nil
            conflicting.insert(processID)
            return
        }
        names[processID] = bundleID
    }

    func host(processID: Int32) -> String? {
        guard processID > 0 else { return nil }
        return names[processID]
    }

    mutating func reset() {
        names = [:]
        conflicting = []
    }
}
