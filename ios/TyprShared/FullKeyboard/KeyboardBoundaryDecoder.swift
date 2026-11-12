import Foundation

/// Exact two-part run segmentation and whole-vs-split comparison translated from iikb's
/// Correction/Corrector.swift and Typing/TypingEngine+Words.swift at
/// 09a2e9cdfbe851adff6c4646333c0a3f74ba8765 (MIT, © 2026 Bassim Shahidy).
/// No space-tap reinterpretation, per-part decoding, multiword beam or automatic authority.
nonisolated enum KeyboardBoundaryDecoder {
    typealias Language = SpatialWordDecoder.Language
    static let maxLetters = 32
    static let maxPartLetters = 20
    static let resultLimit = 3
    // One whole, two per split point, eight whole competitors and up to two join
    // readings, each in at most two tries (including rejected split endpoints).
    static let maximumLexicalQueries = 74
    static let maximumTrieEdgeChecks = maximumLexicalQueries * maxLetters * 30 * 2
    static let missingSpacePenalty = log(0.01)
    static let joinMargin = log(100.0)

    struct Job: Equatable, Sendable {
        let token: String
        let previous: String?
        let languages: Set<Language>
        let personal: PersonalLexiconSnapshot
        /// Explicit keeps protect whole literals even with personal ranking off.
        let kept: Set<String>
    }

    struct Candidate: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case split, join }
        let kind: Kind
        /// Exact suffix owned by the chip. A join includes the preceding token and one space.
        let original: String
        let replacement: String
        let score: Double
        let baseline: Double
    }

    struct Retrieval: Sendable {
        let job: Job
        let candidates: [Candidate]
        let lexicalQueries: Int
    }

    /// Hand-curated closed-class words (Typr original work, not third-party data).
    /// Only words filtered out by the bundled ≥3-letter resource policy. Equal
    /// .01 pseudo-probability, not fabricated corpus counts; longer function words use TSW1.
    private static let germanShort: Set<String> = [
        "ab", "am", "an", "da", "du", "er", "es", "im", "in", "ja", "je", "ob", "so", "um", "wo", "zu"
    ]
    private static let englishShort: Set<String> = [
        "a", "i", "am", "an", "as", "at", "be", "by", "do", "he", "if", "in", "is", "it", "me", "my",
        "no", "of", "oh", "on", "or", "so", "to", "up", "us", "we"
    ]
    private static let shortPrior = log(0.01)

    static var shortWordPayloadBytes: Int {
        (germanShort.count + englishShort.count) * MemoryLayout<String>.stride
            + germanShort.reduce(0) { $0 + $1.utf8.count } + englishShort.reduce(0) { $0 + $1.utf8.count }
    }

    static var maximumCandidatePayloadBytes: Int {
        // Original join suffix keeps RAW Unicode: two ≤64-byte inputs plus a space.
        // Replacement is NFC (≤32 two-byte letters plus space). Do not assume the raw
        // original was NFC. Excludes allocator/container overhead, not RSS.
        (resultLimit + 1) * (MemoryLayout<Candidate>.stride + 129 + 65)
    }

    static func isEligible(_ token: String) -> Bool {
        guard token.utf8.count <= 64, (1...maxLetters).contains(token.count) else { return false }
        let lower = PersonalLexiconSnapshot.normalize(token)
        guard lower.allSatisfy({ SpatialWordLexicon.alphabet.contains($0) }) else { return false }
        // Internal capitals, acronyms and non-letter identifiers have no boundary interpretation.
        return token == token.lowercased() || (token.first?.isUppercase == true
            && String(token.dropFirst()) == token.dropFirst().lowercased())
    }

    static func retrieve(_ job: Job, lexicons: [Language: SpatialWordLexicon],
                         whole: SpatialWordDecoder.Outcome? = nil) -> Retrieval {
        var queries = 0
        var found: [Candidate] = []
        func result() -> Retrieval { Retrieval(job: job, candidates: found, lexicalQueries: queries) }
        func retain(_ candidate: Candidate) {
            found.append(candidate)
            found.sort {
                let a = ($0.score * 1e9).rounded(), b = ($1.score * 1e9).rounded()
                return a == b ? $0.replacement < $1.replacement : a > b
            }
            if found.count > resultLimit { found.removeLast() }
        }
        guard !job.languages.isEmpty, job.languages.allSatisfy({ lexicons[$0] != nil }),
              isEligible(job.token), job.personal.scan.complete else { return result() }
        let sources = Language.allCases.filter { job.languages.contains($0) }
        let floor = sources.compactMap { lexicons[$0].map { log(1 / $0.total) } }.max() ?? 0
        func prior(_ word: String) -> Double? {
            queries += 1
            precondition(queries <= maximumLexicalQueries)
            var best: Double?
            for language in sources {
                var value = lexicons[language]?.logPrior(for: word)
                let short = language == .german ? germanShort : englishShort
                if short.contains(word) { value = max(value ?? -.infinity, shortPrior) }
                if let value { best = max(best ?? -.infinity, value) }
            }
            if job.personal.isKept(word) || (job.personal.counts[word] ?? 0) >= 2 {
                best = max(best ?? -.infinity, log(0.0001))
            }
            return best.map { $0 + job.personal.bonus(for: word) }
        }
        let token = PersonalLexiconSnapshot.normalize(job.token)
        let wholePrior = prior(token)
        let protected = job.kept.contains(token) || (job.personal.counts[token] ?? 0) > 0
        if !protected, token.count >= 3 {
            // Corpus membership is not spelling validity (the packs contain e.g. "inthe").
            // A known whole must lose on score too; MainActor separately vetoes valid literals.
            var baseline = wholePrior ?? floor
            if case .result(let reading) = whole {
                // Convert the existing .35-weighted whole-word score to full lexical log
                // probability; the unchanged letters' spatial density cancels for exact splits.
                for candidate in reading.candidates.prefix(8) where !candidate.isCompletion {
                    queries += 1
                    let p = sources.compactMap { lexicons[$0]?.logPrior(for: candidate.word) }.max() ?? floor
                    baseline = max(baseline, candidate.score - reading.literalSpatialScore + 0.65 * p)
                }
            }
            let letters = Array(token)
            for point in 1..<letters.count {
                guard point <= maxPartLetters, letters.count - point <= maxPartLetters else { continue }
                let left = String(letters[..<point]), right = String(letters[point...])
                guard let a = prior(left), let b = prior(right) else { continue }
                let score = a + b + missingSpacePenalty
                guard score > baseline else { continue }
                retain(Candidate(kind: .split, original: job.token,
                                       replacement: left + " " + right, score: score, baseline: baseline))
            }
        }
        // Exact removal of one gratuitous space. Without contextual evidence TWO known parts
        // always win protection, irrespective of the joined word's frequency ("some thing").
        if let previous = job.previous, isEligible(previous), previous.count + token.count <= maxLetters {
            let first = PersonalLexiconSnapshot.normalize(previous)
            let personalProtection = job.kept.contains(first) || job.kept.contains(token)
                || (job.personal.counts[first] ?? 0) > 0 || (job.personal.counts[token] ?? 0) > 0
            if !personalProtection {
                let firstPrior = prior(first)
                let secondPrior = wholePrior
                if firstPrior == nil || secondPrior == nil, let joined = prior(first + token) {
                    let apart = (firstPrior ?? floor) + (secondPrior ?? floor)
                    let score = joined + missingSpacePenalty
                    if score - apart >= joinMargin {
                        retain(Candidate(kind: .join, original: previous + " " + job.token,
                                               replacement: first + token, score: score, baseline: apart))
                    }
                }
            }
        }
        return result()
    }
}
