import Foundation

/// Bounded LCS over word/whitespace tokens. Newlines are individual tokens, not lost
/// in whitespace splitting, so Notes line structure remains visible. No UI dependencies.
enum WordDiff {
    enum Kind: String, Equatable, Sendable { case unchanged, removed, added }
    struct Part: Equatable, Sendable {
        let text: String
        let kind: Kind
    }
    enum Result: Equatable, Sendable {
        case compared([Part])
        case tooLong
    }

    private static func tokens(_ text: String) -> [String]? {
        var result: [String] = [], word = ""
        func flush() {
            if !word.isEmpty { result.append(word); word = "" }
        }
        for character in text {
            if character.isWhitespace {
                flush()
                result.append(String(character))
            } else {
                word.append(character)
            }
            if result.count > 400 { return nil }
        }
        flush()
        return result.count <= 400 ? result : nil
    }

    static func compute(_ before: String, _ after: String) -> Result {
        guard let a = tokens(before), let b = tokens(after) else { return .tooLong }
        let columns = b.count + 1
        // At most 400 x 400 comparisons (+ sentinel row/column).
        var lcs = [Int](repeating: 0, count: (a.count + 1) * columns)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    lcs[i * columns + j] = a[i] == b[j]
                        ? 1 + lcs[(i + 1) * columns + j + 1]
                        : max(lcs[(i + 1) * columns + j], lcs[i * columns + j + 1])
                }
            }
        }
        var i = 0, j = 0, parts: [Part] = []
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                parts.append(Part(text: a[i], kind: .unchanged)); i += 1; j += 1
            } else if i < a.count, j == b.count || lcs[(i + 1) * columns + j] >= lcs[i * columns + j + 1] {
                parts.append(Part(text: a[i], kind: .removed)); i += 1
            } else {
                parts.append(Part(text: b[j], kind: .added)); j += 1
            }
        }
        return .compared(parts)
    }
}
