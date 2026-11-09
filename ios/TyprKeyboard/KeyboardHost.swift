import ObjectiveC
import UIKit

/// The app the keyboard is typing in, by bundle ID, for returning there after a cold start.
/// Since iOS 26.4 a keyboard's own properties no longer name its host. The view controller
/// still knows the host's process ID (`_hostProcessIdentifier`), and UIKit's keyboard
/// arbiter, switched on by `KeyboardArbiter.c`, names apps with their process IDs, sometimes
/// an app already left. So each pair is kept in `HostProcessTable` until the keyboard next
/// appears, and the host is the name kept under the host's process ID, or none.
///
/// None of this is public API. Classes and keys are resolved by name and every read is
/// guarded (`value(forKey:)` on a missing key raises), so a missing step answers nil and
/// the user swipes back. Translated from iikb's `KeyboardHost.swift`
/// (https://github.com/AVGVSTVS96/iikb, MIT) and Dictus's `HostAppResolver.swift`
/// (https://github.com/getdictus/dictus-ios, MIT), which found and measured it.
@MainActor
enum KeyboardHost {
    private static var table = HostProcessTable()
    /// Hosts named during this keyboard process, to recognise a share sheet of one of them.
    /// Kept in memory only, like the table.
    private static var seenApps = Set<String>()

    /// The keyboard appeared: the host may have changed.
    static func appeared() {
        table.reset()
        enableArbiterIfNeeded()
        if let client, value(client, "connection") == nil,
           client.responds(to: NSSelectorFromString("startConnection")) {
            client.perform(NSSelectorFromString("startConnection"))
        }
        harvest()
    }

    /// Keeps the app the arbiter names now.
    static func harvest() {
        guard let state = client.flatMap({ value($0, "currentClientState") }) as? NSObject,
              let name = value(state, "sourceBundleIdentifier") as? String, !name.isEmpty,
              let id = (value(state, "processIdentifier") as? NSNumber)?.int32Value, id > 0
        else { return }
        table.record(processID: id, bundleID: name)
    }

    static func app(of keyboard: UIInputViewController) -> String? {
        harvest()
        let id = (value(keyboard, "_hostProcessIdentifier") as? NSNumber)?.int32Value ?? 0
        guard let app = table.host(processID: id) else { return nil }
        if !HostReturnCatalog.isExtension(app, ofAny: seenApps) {
            seenApps.insert(app)
        }
        return app
    }

    /// Whether opening Typr from `app` can come back to it (`HostReturnCatalog.canReturn`).
    static func canReturn(to app: String?) -> Bool {
        HostReturnCatalog.canReturn(to: app, knownApps: seenApps, appleAppInstalled: installed)
    }

    // MARK: - Private API, resolved by name

    private static var arbiterEnabled = false

    /// `KeyboardArbiter.c` already did this at load; repeat it in case the class loaded late.
    private static func enableArbiterIfNeeded() {
        guard !arbiterEnabled else { return }
        arbiterEnabled = Self.replaceArbiterEnabled()
    }

    /// Nonisolated: UIKit may ask `+enabled` on any thread, so the block must carry no actor.
    private nonisolated static func replaceArbiterEnabled() -> Bool {
        guard let type = NSClassFromString("_UIKeyboardArbiterClient"),
              let method = class_getClassMethod(type, NSSelectorFromString("enabled"))
        else { return false }
        let enabled: @Sendable @convention(block) (AnyObject) -> Bool = { _ in true }
        method_setImplementation(method, imp_implementationWithBlock(enabled))
        return true
    }

    private static var client: NSObject? {
        let shared = NSSelectorFromString("automaticSharedArbiterClient")
        guard let type = NSClassFromString("_UIKeyboardArbiterClient") as AnyObject?,
              type.responds(to: shared)
        else { return nil }
        return type.perform(shared)?.takeUnretainedValue() as? NSObject
    }

    private nonisolated static func installed(_ id: String) -> Bool? {
        let selector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard let type = NSClassFromString("LSApplicationProxy") as AnyObject?,
              type.responds(to: selector),
              let proxy = type.perform(selector, with: id)?.takeUnretainedValue() as? NSObject
        else { return nil }
        return value(proxy, "isInstalled") as? Bool
    }

    private nonisolated static func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
}
