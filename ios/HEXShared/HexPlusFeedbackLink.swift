import Foundation

/// Hex+: opens the app's dictation log on one entry's feedback editor.
/// The link carries only the archive entry UUID, never dictated text. Any app could open it;
/// it can only show an existing local entry, so no other check is needed.
nonisolated enum HexPlusFeedbackLink {
    static let scheme = "hex-dictation"
    static let host = "hexplus"
    static let path = "/feedback"

    static func url(entryID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = [URLQueryItem(name: "entry", value: entryID.uuidString)]
        return components.url!
    }

    static func entryID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == host, url.path == path,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "entry" })?.value else { return nil }
        return UUID(uuidString: value)
    }
}
