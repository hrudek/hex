import Observation
import SwiftUI

/// Typr: carries a "Fix in Typr" request from the keyboard (`HexPlusFeedbackLink`) to the
/// dictation log. The Typr card presents the log; the log consumes the request and opens
/// that entry with its "What I said" field focused.
@MainActor
@Observable
final class HexPlusFeedbackRouter {
    static let shared = HexPlusFeedbackRouter()

    /// Set by the URL handler, cleared by the log once it navigated to the entry.
    var requestedEntry: UUID?

    /// Returns true when the URL was a Typr feedback link (and is therefore handled).
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let id = HexPlusFeedbackLink.entryID(from: url) else { return false }
        requestedEntry = id
        return true
    }

    func consume() -> UUID? {
        defer { requestedEntry = nil }
        return requestedEntry
    }
}
