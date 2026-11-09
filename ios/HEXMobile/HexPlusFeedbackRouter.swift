import Observation
import SwiftUI

/// Hex+: carries a "Fix in Hex" request from the keyboard (`HexPlusFeedbackLink`) to the
/// dictation log. The Hex+ card presents the log; the log consumes the request and opens
/// that entry with its "What I said" field focused.
@MainActor
@Observable
final class HexPlusFeedbackRouter {
    static let shared = HexPlusFeedbackRouter()

    /// Set by the URL handler, cleared by the log once it navigated to the entry.
    var requestedEntry: UUID?

    /// Returns true when the URL was a Hex+ feedback link (and is therefore handled).
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
