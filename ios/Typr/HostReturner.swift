import UIKit

/// Returns to the app a cold-start dictation came from, named by the keyboard as a bundle ID.
/// First by bundle ID through `LSApplicationWorkspace` (private API, resolved by name: it
/// brings any app back exactly as it was left), then by the app's own URL
/// (`HostReturnCatalog`). `false` means neither opened anything: the user swipes back.
/// After iikb's `HostApp.swift` (https://github.com/AVGVSTVS96/iikb, MIT).
@MainActor
struct HostReturner {
    var openByBundleID: (String) -> Bool
    var openURL: (URL) async -> Bool

    static let live = HostReturner(
        openByBundleID: { HostReturner.openApplication($0) },
        openURL: { await UIApplication.shared.open($0) }
    )

    func open(_ bundleID: String) async -> Bool {
        if openByBundleID(bundleID) { return true }
        guard let url = HostReturnCatalog.scheme(for: bundleID) else { return false }
        return await openURL(url)
    }

    private static func openApplication(_ bundleID: String) -> Bool {
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?
                .takeUnretainedValue() as? NSObject,
              workspace.responds(to: selector)
        else { return false }
        typealias Open = @convention(c) (NSObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(workspace.method(for: selector), to: Open.self)
        return open(workspace, selector, bundleID as NSString)
    }
}
