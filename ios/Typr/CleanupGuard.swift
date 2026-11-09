import Foundation

/// A light plausibility check on the model's answer. Cleanup may rewrite freely into good written
/// language (every style except Verbatim), so the guard no longer counts new words. It rejects only
/// what a cleanup never does: an answer much longer than what was said (answering or inventing), a
/// number, link or address nobody said, a transcript repeated twice (OpenWhispr's duplicated-transcript
/// check, MIT, see PORTS.md), or changed Notes markers. Empty answers and Notes line breaks are checked
/// by the coordinator. Not a semantic guarantee: a wrong word, a dropped clause or a short answer to
/// a dictated question can pass.
enum CleanupGuard {
    static let revision = "2026-11-09a"

    static func wordCount(_ text: String) -> Int {
        words(text).count
    }

    /// Case-folded words.
    static func words(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            if let word { result.append(word.lowercased()) }
        }
        return result
    }

    /// Digit runs ("14:00" → 14, 00), links and e-mail addresses: values the model must never invent.
    static func values(_ text: String) -> Set<String> {
        let pattern = #"https?://[^\s]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+|\d+"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var result = Set<String>()
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result.insert(String(text[range]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)")))
        }
        return result
    }

    private static let markers = ["new paragraph", "bullet point", "next bullet", "new line", "bullet"]

    /// How often each Notes marker phrase occurs, longest first and without overlaps.
    static func markerCounts(_ text: String) -> [String: Int] {
        var rest = " " + words(text).joined(separator: " ") + " "
        var counts: [String: Int] = [:]
        for marker in markers {
            let needle = " \(marker) "
            while let range = rest.range(of: needle) {
                counts[marker, default: 0] += 1
                rest.replaceSubrange(range, with: " ")
            }
        }
        return counts
    }

    /// Why an answer is implausible, or nil when it is accepted.
    /// `vocabulary`: the spellings listed in the prompt. Their values count as spoken, so a listed
    /// "iPhone 17" is not an invented number.
    static func rejection(input: String, output: String, style: DictationStyle,
                          vocabulary: [String] = []) -> CleanupGuardRule? {
        if duplicatesTranscript(input: input, output: output) { return .duplicated }
        let inputWords = words(input), outputWords = words(output)
        // Cleanup never needs many more words than were spoken.
        if outputWords.count > inputWords.count + max(2, inputWords.count / 5) { return .grew }
        // Every number, link and address must have been spoken; dropping a corrected one is fine.
        let listed = vocabulary.joined(separator: " \n ")
        if !values(output).isSubset(of: values(input).union(values(listed))) { return .newValue }
        if style == .notes, markerCounts(input) != markerCounts(output) { return .notesMarkers }
        return nil
    }

    /// OpenWhispr's `assertValidCleanupOutput`: the answer is one text of at least six words written
    /// twice in a row, and the speaker did not say most of those words twice. Stutters ("the the") in
    /// the transcript are collapsed first; a "Cleaned transcript:" label line is ignored.
    static func duplicatesTranscript(input: String, output: String) -> Bool {
        func tokens(_ text: String) -> [String] {
            words(text.precomposedStringWithCompatibilityMapping
                .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: ""))
        }
        var spoken: [String] = []
        for token in tokens(input) where token != spoken.last { spoken.append(token) }
        let answer = output.components(separatedBy: .newlines)
            .filter { !isCleanupLabel($0) }
            .flatMap { tokens($0) }
        guard answer.count % 2 == 0, answer.count / 2 >= 6 else { return false }
        let half = answer.count / 2
        let copy = Array(answer[..<half])
        guard copy == Array(answer[half...]) else { return false }
        var counts: [String: Int] = [:]
        for token in spoken { counts[token, default: 0] += 1 }
        var saidTwice = 0
        for token in copy {
            let remaining = counts[token] ?? 0
            guard remaining >= 2 else { continue }
            counts[token] = remaining - 2
            saidTwice += 1
        }
        return saidTwice * 2 <= half
    }

    private static func isCleanupLabel(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        return ["cleaned transcript:", "**cleaned transcript:**", "**cleaned transcript**:"].contains(trimmed)
    }

    static func accepts(input: String, output: String, style: DictationStyle) -> Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rejection(input: input, output: output, style: style) == nil
    }
}
