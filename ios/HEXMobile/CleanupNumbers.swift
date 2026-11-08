import Foundation

/// Desktop processor.rs::numbers_only, plus the explicitly scoped iOS German vocabulary.
enum CleanupNumbers {
    private static let english: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion"
    ]
    // No compound-number parser: einundzwanzig (unlike twenty-one) is intentionally not covered.
    private static let german: Set<String> = [
        "null", "eins", "ein", "eine", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn",
        "elf", "zwölf", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig",
        "hundert", "tausend", "million", "millionen", "milliarde", "milliarden"
    ]
    private static let joiners: Set<String> = ["and", "point", "minus", "negative", "und", "punkt", "komma"]

    static func only(_ transcript: String) -> Bool {
        var anyNumber = false
        // Split only whitespace and ASCII hyphen, exactly like desktop (not all punctuation).
        for token in transcript.split(whereSeparator: { $0.isWhitespace || $0 == "-" }) {
            // Rust char::is_alphanumeric is Unicode-aware. Only the numeric-body check is ASCII.
            let word = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if word.isEmpty { continue }
            let key = word.lowercased()
            if word.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || $0 == "." || $0 == "," })
                || english.contains(key) || german.contains(key) {
                anyNumber = true
            } else if !joiners.contains(key) {
                return false
            }
        }
        return anyNumber
    }
}
