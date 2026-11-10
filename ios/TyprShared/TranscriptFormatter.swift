import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

nonisolated enum DictationStyle: String, Codable, CaseIterable, Sendable {
    case polished
    // Keep the old stored value for the renamed lowercase style (settings, links and logs).
    case casual = "casualCapitalized"
    case veryCasual = "casual"
    case notes
    case verbatim

    var label: String {
        switch self {
        case .polished: "Polished"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        case .notes: "Notes"
        case .verbatim: "Verbatim"
        }
    }

    var shortHint: String {
        switch self {
        case .polished: "Clean punctuation and filler trim"
        case .casual: "Natural capitalization, no trailing period"
        case .veryCasual: "Lowercase texting, no trailing period"
        case .notes: "Spoken bullets and line breaks"
        case .verbatim: "Exact words from the model"
        }
    }

    var next: DictationStyle {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .polished }
        return all[(index + 1) % all.count]
    }
}

nonisolated enum TranscriptFormatter {
    static func format(_ raw: String, style: DictationStyle) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch style {
        case .verbatim:
            return collapseHorizontalSpaces(in: trimmed)

        case .polished:
            let cleaned = stripStandaloneFillers(in: trimmed)
            return polishSentences(cleaned)

        case .casual, .veryCasual:
            let cleaned = stripStandaloneFillers(in: trimmed)
            var result = fixSpacingBeforePunctuation(in: collapseHorizontalSpaces(in: cleaned))
            result = style == .veryCasual ? result.lowercased() : capitalizeSentenceStarts(in: result)
            // Both chat styles omit the final period, regardless of sentence count.
            // Internal punctuation and final question/exclamation marks stay unchanged.
            if result.hasSuffix(".") {
                result.removeLast()
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)

        case .notes:
            let cleaned = stripStandaloneFillers(in: trimmed)
            return formatNotes(cleaned)
        }
    }

    /// Joins dictated text cleanly with existing text around the insertion cursor.
    static func insertionText(
        for formatted: String,
        beforeContext: String?,
        afterContext: String?
    ) -> String {
        guard !formatted.isEmpty else { return "" }
        var output = formatted

        if let before = beforeContext, let lastChar = before.last {
            let needsLeadingSpace = !lastChar.isWhitespace
                && lastChar != "("
                && lastChar != "["
                && lastChar != "{"
                && lastChar != "\""
                && lastChar != "“"
                && !output.hasPrefix("\n")
                && !isClosingPunctuation(output.first)
            if needsLeadingSpace {
                output = " " + output
            }
        }

        if let after = afterContext, let firstChar = after.first {
            let needsTrailingSpace = !firstChar.isWhitespace
                && !isClosingPunctuation(firstChar)
                && !output.hasSuffix("\n")
                && !output.hasSuffix(" ")
            if needsTrailingSpace {
                output += " "
            }
        }

        return output
    }

    private static func isClosingPunctuation(_ character: Character?) -> Bool {
        guard let character else { return false }
        return ".,!?;:)]}”".contains(character)
    }

    /// Hesitation sounds that are never a word in German or English (äh, ähm, öhm, hm, mhm).
    private static let universalFillers = #"äh+m*|ähm+|öh+m*|eh+m+|hm+|mhm+"#
    /// English hesitation sounds that are real German words ("um 13 Uhr", "was er sagt"),
    /// so they are stripped only from text that reads as English.
    private static let englishFillers = #"um+|uh+|er+|ah+"#

    private static let germanMarkers: Set<String> = [
        "der", "die", "das", "und", "ist", "nicht", "ich", "du", "wir", "ein", "eine", "einen",
        "zu", "mit", "auf", "für", "den", "dem", "des", "sich", "es", "auch", "noch", "dass",
        "wenn", "aber", "oder", "wie", "was", "bitte", "mal", "habe", "hab", "sind", "wird",
        "kann", "soll", "uhr", "nein", "ja", "danach", "dann", "schon", "hier", "mir", "dir",
        "uns", "von", "im", "bei", "nach", "über", "ob", "weil", "eigentlich", "vielleicht",
        "gut", "danke", "hallo", "jetzt", "heute", "morgen", "sehr", "kommt", "komme", "gibt", "geht",
        "muss", "mach", "machen",
    ]
    private static let englishMarkers: Set<String> = [
        "the", "and", "is", "are", "to", "of", "you", "it", "that", "this", "with", "for",
        "i", "i'm", "we", "they", "a", "an", "on", "at", "be", "was", "have", "not", "can",
        "will", "what", "please", "let's", "my", "your", "just", "do", "don't", "so",
        "good", "great", "sounds", "yeah", "yes", "thanks", "thank", "hello", "today", "tomorrow",
    ]

    /// Decides whether English filler words may be removed. English only when the text has no
    /// umlaut/ß and more English than German function words; a tie asks
    /// the on-device language recognizer. Mixed German with English terms stays German.
    static func readsAsEnglish(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains(where: { "äöüß".contains($0) }) { return false }
        var german = 0
        var english = 0
        for word in lowered.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
            let key = word.replacingOccurrences(of: "’", with: "'")
            if germanMarkers.contains(key) { german += 1 }
            if englishMarkers.contains(key) { english += 1 }
        }
        if english != german { return english > german }
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .german]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english
        #else
        return false
        #endif
    }

    private static func stripStandaloneFillers(in text: String) -> String {
        let fillers = readsAsEnglish(text) ? universalFillers + "|" + englishFillers : universalFillers
        let pattern = #"(?i)(?:^|(?<=[\s,]))(?:"# + fillers + #")(?=(?:[\s,.!?]|$)),?\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        return collapseHorizontalSpaces(in: stripped)
    }

    private static func polishSentences(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var normalized = fixSpacingBeforePunctuation(in: collapseHorizontalSpaces(in: text))
        normalized = capitalizeSentenceStarts(in: normalized)
        if let last = normalized.last, !".!?…\"”)]".contains(last) {
            normalized.append(".")
        }
        return normalized
    }

    private static func formatNotes(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var working = text
        let replacements: [(String, String)] = [
            (#"(?i)\bnew paragraph\b[,.]?\s*"#, "\n\n"),
            (#"(?i)\bnew line\b[,.]?\s*"#, "\n"),
            (#"(?i)(?:^|\s+)(?:bullet point|next bullet|bullet)\b[:,-]?\s*"#, "\n- "),
        ]
        for (pattern, template) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: template)
            }
        }
        let lines = working
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmedLine = collapseHorizontalSpaces(in: line)
                if trimmedLine.hasPrefix("- ") {
                    let body = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    return body.isEmpty ? "" : "- " + capitalizeFirstLetter(fixSpacingBeforePunctuation(in: body))
                }
                return capitalizeFirstLetter(fixSpacingBeforePunctuation(in: trimmedLine))
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseHorizontalSpaces(in text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fixSpacingBeforePunctuation(in text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"\s+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"^[,;:]+\s*"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeSentenceStarts(in text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true
        for index in chars.indices {
            let ch = chars[index]
            if capitalizeNext && ch.isLetter {
                for upper in String(ch).uppercased() {
                    chars[index] = upper
                    break
                }
                capitalizeNext = false
            } else if ch == "." {
                // "bzw. in die", "z. B. die": an abbreviation's period does not end a sentence.
                capitalizeNext = !endsAbbreviation(chars, periodAt: index)
            } else if "!?".contains(ch) || ch == "\n" {
                capitalizeNext = true
            } else if !ch.isWhitespace && ch != "\"" && ch != "“" && ch != "(" {
                capitalizeNext = false
            }
        }
        return String(chars)
    }

    /// Common German and English abbreviations whose period is not a sentence end,
    /// written without inner spaces and lowercased ("z. B." is checked as "z.b.").
    private static let abbreviations: Set<String> = [
        "bzw.", "ca.", "usw.", "etc.", "ggf.", "evtl.", "vgl.", "bspw.", "inkl.", "exkl.", "zzgl.",
        "sog.", "z.b.", "d.h.", "u.a.", "o.ä.", "u.u.", "z.t.", "z.zt.", "i.d.r.", "s.o.", "s.u.",
        "e.g.", "i.e.", "vs.", "approx.", "nr.", "dr.", "prof.", "mr.", "mrs.", "ms.", "st.",
    ]

    /// Whether the period at `index` closes a known abbreviation, or the lowercase first
    /// letter of a spaced one ("d." in "d. h."). Only suppresses capitalization; text the
    /// speaker or model already capitalized is never lowercased.
    private static func endsAbbreviation(_ chars: [Character], periodAt index: Int) -> Bool {
        func token(endingAt end: Int) -> (text: String, start: Int)? {
            var start = end
            while start > 0, chars[start - 1].isLetter || chars[start - 1] == "." { start -= 1 }
            guard start < end else { return nil }
            return (String(chars[start...end]), start)
        }
        guard let last = token(endingAt: index), last.text.count > 1 else { return false }
        let word = last.text.lowercased()
        if abbreviations.contains(word) { return true }
        if word.count == 2, let letter = last.text.first, letter.isLowercase { return true }
        // "z. B." / "d. h.": join with the previous token across one space.
        if last.start >= 2, chars[last.start - 1] == " ",
           let previous = token(endingAt: last.start - 2), previous.text.hasSuffix(".") {
            return abbreviations.contains((previous.text + last.text).lowercased())
        }
        return false
    }

    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        var result = text
        let upper = String(result[index]).uppercased()
        result.replaceSubrange(index...index, with: upper)
        return result
    }
}
