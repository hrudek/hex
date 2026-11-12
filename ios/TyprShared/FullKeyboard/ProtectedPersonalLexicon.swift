import Foundation

/// App-built literals, independent of typing learning and corpus frequencies.
/// Sorted NFC keys provide bounded binary queries without scanning contacts on a keypress.
nonisolated struct ProtectedPersonalLexicon: Equatable, Sendable {
    static let maximumEntries = 2_000
    static let maximumWordBytes = 64
    static let maximumFileBytes = 256 * 1024
    static let fileName = "personal-lexicon-v1.json"
    static let contactsKey = "keyboard.personalLexicon.contacts"
    static let vocabularyKey = "keyboard.personalLexicon.vocabulary"
    static let resetKey = "keyboard.personalLexicon.reset"
    static let empty = Self(words: [])
    let words: [String]

    private init(words: [String]) { self.words = words }

    static func key(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'").lowercased().precomposedStringWithCanonicalMapping
    }

    private func lowerBound(_ key: String) -> Int {
        var low = 0
        var high = words.count
        while low < high {
            let middle = low + (high - low) / 2
            if words[middle] < key { low = middle + 1 } else { high = middle }
        }
        return low
    }

    func contains(_ text: String) -> Bool {
        guard text.utf8.count <= Self.maximumWordBytes else { return false }
        let normalized = Self.key(text)
        let index = lowerBound(normalized)
        return index < words.count && words[index] == normalized
    }

    /// Includes an exact prefix: attribution must not consume the next letter of a known name.
    func protectsPrefix(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= Self.maximumWordBytes else { return false }
        let prefix = Self.key(text)
        let index = lowerBound(prefix)
        return index < words.count && words[index].hasPrefix(prefix)
    }

    func completions(for text: String, limit: Int = 3) -> [String] {
        guard text.count >= 2, text.utf8.count <= Self.maximumWordBytes else { return [] }
        let prefix = Self.key(text)
        var index = lowerBound(prefix)
        var result: [String] = []
        let cap = min(3, max(0, limit))
        while index < words.count && result.count < cap && words[index].hasPrefix(prefix) {
            if words[index] != prefix { result.append(words[index]) }
            index += 1
        }
        return result
    }

    /// Streaming top-K: input order never determines which entries survive the cap.
    /// Only letters/apostrophes enter the keyboard's literal-token grammar. Phrases are split.
    struct Builder: Sendable {
        private var words: [String] = []
        mutating func add(_ text: String) {
            // Stream tokens rather than materializing a second copy of a transcript/contact book.
            var token = ""
            var overflow = false
            for character in text {
                if character.isLetter || character == "'" || character == "’" {
                    if token.utf8.count + character.utf8.count <= maximumWordBytes {
                        token.append(character)
                    } else { overflow = true }
                } else {
                    if !overflow { insert(token) }
                    token = ""; overflow = false
                }
            }
            if !overflow { insert(token) }
        }

        private mutating func insert(_ token: String) {
            let word = ProtectedPersonalLexicon.key(token)
            guard word.count >= 2, word.utf8.count <= maximumWordBytes,
                  word.first?.isLetter == true, word.last?.isLetter == true else { return }
            let index = ProtectedPersonalLexicon(words: words).lowerBound(word)
            guard index == words.count || words[index] != word else { return }
            if words.count == maximumEntries && index == words.count { return }
            words.insert(word, at: index)
            if words.count > maximumEntries { words.removeLast() }
        }

        func build() -> ProtectedPersonalLexicon { ProtectedPersonalLexicon(words: words) }
    }

    private struct Document: Codable { let version: Int; let words: [String] }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Document(version: 1, words: words))
    }

    static func decode(_ data: Data) -> Self? {
        guard data.count <= maximumFileBytes,
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.version == 1, document.words.count <= maximumEntries else { return nil }
        var builder = Builder()
        for word in document.words { builder.add(word) }
        let result = builder.build()
        guard result.words == document.words else { return nil }
        return result
    }

    /// Metadata preflight plus a capped read; malformed/old/missing files mean no imports.
    static func load(directory: URL?) -> Self {
        guard let url = directory?.appendingPathComponent(fileName),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumFileBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumFileBytes + 1) else { return .empty }
        return decode(data) ?? .empty
    }

    /// Called only by the containing app, never the keyboard.
    func write(directory: URL?) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(Self.fileName)
        let data = try encoded()
        guard data.count <= Self.maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Disabling sources prevents a launch/defaults notification from recreating deleted imports.
    static func reset(directory: URL?, defaults: UserDefaults?) throws {
        defaults?.set(UUID().uuidString, forKey: resetKey)
        defaults?.set(false, forKey: contactsKey)
        defaults?.set(false, forKey: vocabularyKey)
        guard let url = directory?.appendingPathComponent(fileName) else { return }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
