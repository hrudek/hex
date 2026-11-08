import Foundation

/// Structural, deliberately fallible acceptance filter; not a semantic safety guarantee.
enum CleanupGuard {
    struct Token {
        let key: String
        let span: Range<String.Index>
        let protected: Bool
        let cue: Bool
        let marker: Bool
        let negation: Bool
    }

    private static let cues = ["ich korrigiere", "ich meine", "scratch that", "correction", "korrektur", "i mean", "nein", "no"]
    private static let markers = ["new paragraph", "bullet point", "next bullet", "new line", "bullet"]
    private static let negations: Set<String> = [
        "nicht", "nein", "kein", "keine", "keinen", "keinem", "keiner", "keines", "keinerlei", "nie", "niemals", "nichts", "ohne", "weder",
        "not", "no", "never", "none", "nothing", "neither", "nor", "without", "cannot"
    ]

    static func tokens(_ text: String) -> [Token] {
        // Protected spans win over word segmentation. Punctuation at a URL's end is not part of it.
        let pattern = #"https?://[^\s]+|[\w.+-]+@[\w.-]+\.[\p{L}]{2,}|[@#][\p{L}\p{N}_]+|[+-]?\d+(?:[.,:/-]\d+)*(?:\s*%)?"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var words: [Token] = []
        func appendWords(_ range: Range<String.Index>) {
            text.enumerateSubstrings(in: range, options: .byWords) { word, span, _, _ in
                guard let word else { return }
                let key = word.lowercased()
                words.append(Token(key: key, span: span, protected: false, cue: false, marker: false,
                                   negation: negations.contains(key) || key.hasSuffix("n't") || key.hasSuffix("n’t")))
            }
        }
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard var range = Range(match.range, in: text) else { continue }
            appendWords(cursor..<range.lowerBound)
            if text[range].hasPrefix("http") {
                while !range.isEmpty, let last = text[range].last, ".,;:!?)".contains(last) {
                    range = range.lowerBound..<text.index(before: range.upperBound)
                }
            }
            let raw = String(text[range])
            let key = raw.contains("%") ? raw.filter { !$0.isWhitespace } : raw
            words.append(Token(key: key, span: range, protected: true, cue: false, marker: false, negation: false))
            cursor = Range(match.range, in: text)!.upperBound
        }
        appendWords(cursor..<text.endIndex)
        let phrases = (cues + markers).sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }
        var result: [Token] = []
        var i = 0
        while i < words.count {
            var consumed = false
            for phrase in phrases {
                let parts = phrase.split(separator: " ").map(String.init)
                guard i + parts.count <= words.count else { continue }
                let group = Array(words[i..<(i + parts.count)])
                guard !group.contains(where: \.protected), group.map(\.key) == parts else { continue }
                let span = group.first!.span.lowerBound..<group.last!.span.upperBound
                // Punctuation is ignored, but a phrase must never cross a line anchor.
                guard !text[span].contains("\n") else { continue }
                result.append(Token(key: phrase, span: span, protected: false, cue: cues.contains(phrase),
                                    marker: markers.contains(phrase), negation: group.contains(where: \.negation)))
                i += parts.count
                consumed = true
                break
            }
            if !consumed { result.append(words[i]); i += 1 }
        }
        return result
    }

    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in count += 1 }
        return count
    }

    static func accepts(input: String, output: String, style: DictationStyle) -> Bool {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let inputs = style == .notes ? input.components(separatedBy: "\n") : [input]
        let outputs = style == .notes ? output.components(separatedBy: "\n") : [output]
        guard inputs.count == outputs.count else { return false }
        var localFixes = 0
        var retractions = 0
        let wordCount = wordCount(input)
        // The pipeline skips very short dictations; enforce that limit here too.
        if wordCount < 3, tokens(input).map(\.key) != tokens(output).map(\.key) { return false }
        for (line, revised) in zip(inputs, outputs) {
            let a = tokens(line), b = tokens(revised)
            guard check(a, b, localFixes: &localFixes, retractions: &retractions) else { return false }
        }
        return localFixes <= max(1, wordCount / 10) && retractions <= 4
    }

    private struct Hunk { var start: Int; var end: Int; let inserted: [Token] }

    private static func check(_ a: [Token], _ b: [Token], localFixes: inout Int, retractions: inout Int) -> Bool {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i].key == b[j].key ? 1 + lcs[i + 1][j + 1] : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var i = 0, j = 0
        var hunks: [Hunk] = []
        while i < n || j < m {
            if i < n, j < m, a[i].key == b[j].key { i += 1; j += 1; continue }
            let start = i
            var inserted: [Token] = []
            while i < n || j < m {
                if i < n, j < m, a[i].key == b[j].key { break }
                // Preserve the earliest input match when equal-length alignments compete.
                if j < m && (i == n || lcs[i][j + 1] >= lcs[i + 1][j]) {
                    inserted.append(b[j]); j += 1
                } else { i += 1 }
            }
            hunks.append(Hunk(start: start, end: i, inserted: inserted))
        }
        for index in hunks.indices {
            var h = hunks[index]
            if h.inserted.isEmpty {
                let boundary = index == 0 ? 0 : hunks[index - 1].end
                while h.start > boundary, h.end > h.start, a[h.start - 1].key == a[h.end - 1].key {
                    h.start -= 1; h.end -= 1
                }
                hunks[index] = h
            }
        }
        // Sliding must reconstruct exactly the same keys and preserve neighbouring anchors.
        var reconstructed: [String] = []
        var cursor = 0
        for h in hunks {
            guard h.start >= cursor else { return false }
            reconstructed += a[cursor..<h.start].map(\.key)
            reconstructed += h.inserted.map(\.key)
            cursor = h.end
        }
        reconstructed += a[cursor...].map(\.key)
        guard reconstructed == b.map(\.key) else { return false }
        for h in hunks {
            let deleted = Array(a[h.start..<h.end])
            if !h.inserted.isEmpty {
                guard !deleted.isEmpty, deleted.count <= 2, h.inserted.count <= 2,
                      !(deleted + h.inserted).contains(where: { $0.protected || $0.negation || $0.marker || $0.cue }) else { return false }
                localFixes += 1
            } else {
                guard h.end < n, !deleted.contains(where: \.marker) else { return false }
                var segment: [Token] = []
                for token in deleted {
                    segment.append(token)
                    if token.cue {
                        guard (2...8).contains(segment.count), segment.dropLast().contains(where: { !$0.cue }) else { return false }
                        retractions += 1
                        segment = []
                    }
                }
                guard segment.isEmpty else { return false }
            }
        }
        return true
    }
}
