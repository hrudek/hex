import Foundation

/// A light plausibility check on the model's answer, like other on-device dictation cleaners (Yap
/// accepts an answer when most of its words were already spoken). Cleanup only deletes, fixes or
/// re-punctuates the speaker's words, so an answer that grows, brings new numbers or links, or is
/// mostly new words is the model answering or inventing; the plain transcript is pasted instead.
/// Not a semantic guarantee: a wrong word swap or a dropped clause can still pass.
enum CleanupGuard {
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
    /// `vocabulary`: the owner's Custom vocabulary. Its words and values count as spoken, so a
    /// misheard name the model fixes to a listed spelling is not a "new word".
    static func rejection(input: String, output: String, style: DictationStyle,
                          vocabulary: [String] = []) -> CleanupGuardRule? {
        let inputWords = words(input), outputWords = words(output)
        // Cleanup never needs many more words than were spoken.
        if outputWords.count > inputWords.count + max(2, inputWords.count / 5) { return .grew }
        // Every number, link and address must have been spoken; dropping a corrected one is fine.
        let listed = vocabulary.joined(separator: " \n ")
        if !values(output).isSubset(of: values(input).union(values(listed))) { return .newValue }
        // Mostly the speaker's own words: at most a few misheard-word fixes (30 %, at least one).
        let spoken = Set(inputWords).union(words(listed))
        let new = outputWords.filter { !spoken.contains($0) }.count
        if new > max(1, outputWords.count * 3 / 10) { return .newWords }
        if style == .notes, markerCounts(input) != markerCounts(output) { return .notesMarkers }
        return nil
    }

    static func accepts(input: String, output: String, style: DictationStyle) -> Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rejection(input: input, output: output, style: style) == nil
    }
}
