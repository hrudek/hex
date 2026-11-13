import Foundation

/// Bounded translation of iikb Corrector.missedSpaces / Run.keep (MIT, © 2026
/// Bassim Shahidy, 09a2e9cdfbe851adff6c4646333c0a3f74ba8765). Cache each span's
/// readings once; retain a small beam at each endpoint. This lexical fallback
/// never fabricates taps or grants automatic authority.
nonisolated enum KeyboardMultipartSegmenter {
    static let maximumParts = 4
    static let beamWidth = 3
    static let maximumVisits = 131_072
    static let maximumVisitsPerStart = 8_192
    static let maximumPartLetters = 20
    static let maximumLetters = 32
    static let noveltyBaseline = log(1e-24)
    static let editPenalty = log(0.05)

    struct Reading: Equatable, Sendable {
        let word: String
        let score: Double
        let supportedEdit: Bool
    }
    struct Run: Equatable, Sendable {
        let words: [String]
        let score: Double
        let supportedEdits: Int
    }
    struct Result: Sendable {
        let runs: [Run]
        let visits: Int
        let cells: Int
        let cachedReadings: Int
        let exhausted: Bool
    }

    /// Conservative element/string payload, not allocator overhead or RSS. Shared
    /// validated trie data is borrowed. DFS depth ≤21, one ≤21-cell row per frame;
    /// endpoint caches ≤32×33×3, run beams ≤5×33×3. No cross-call cache.
    static var maximumPayloadBytes: Int {
        let readings = maximumLetters * (maximumLetters + 1) * beamWidth
        let readingBytes = MemoryLayout<Reading>.stride + maximumPartLetters * 2
        let runs = (maximumParts + 1) * (maximumLetters + 1) * beamWidth
        let runBytes = MemoryLayout<Run>.stride + maximumParts * (MemoryLayout<String>.stride + 40)
        let frames = (maximumPartLetters + 2) * (64 + 21 * MemoryLayout<Int>.stride)
        // Include bucket-array elements, frozen 32×30 densities, input and
        // temporary alignment rows/strings with a conservative 32 KiB allowance.
        return readings * readingBytes + runs * runBytes + frames + 32_768
    }

    static func retrieve(_ token: String, sources: [SpatialWordLexicon], shortWords: [String],
                         touch: KeyboardTouchWord, calibration: SpatialTouchCalibration?) -> Result {
        let letters = Array(token)
        guard (6...maximumLetters).contains(letters.count), !sources.isEmpty,
              PersonalLexiconSnapshot.normalize(touch.text) == token,
              touch.samples.count == letters.count else {
            return Result(runs: [], visits: 0, cells: 0, cachedReadings: 0, exhausted: false)
        }
        let count = letters.count
        var visits = 0, cells = 0, exhausted = false
        // Freeze relative letter likelihoods once. A changed label must be ≥10×
        // likelier than the literal; mere dictionary segmentation cannot split OOV compounds.
        var gains: [[Double]] = []
        for sample in touch.samples {
            let literal = KeyboardBoundaryTouch.letterDensity(sample.point, key: sample.key,
                                                              layout: touch.layout, calibration: calibration)
            let row: [Double] = SpatialWordLexicon.alphabet.map { letter in
                guard let key = touch.layout.key(.character(String(letter))),
                      let score = KeyboardBoundaryTouch.letterDensity(sample.point, key: key,
                                                                      layout: touch.layout, calibration: calibration),
                      let literal else { return -Double.infinity }
                return score - literal
            }
            gains.append(row)
        }
        let supportedPositions = gains.filter { row in row.contains { $0 >= log(10) } }.count
        guard supportedPositions >= 2 else {
            return Result(runs: [], visits: 0, cells: 0, cachedReadings: 0, exhausted: false)
        }
        func support(_ word: String, start: Int, used: Int, edits: Int) -> Double? {
            if edits == 0 { return 0 }
            let part = Array(letters[start..<(start + used)])
            guard let aligned = SpatialWordDecoder.align(word: word, taps: part) else { return nil }
            // A transposition has two real taps; keep their observed positions for
            // likelihood comparison, never use the alignment as a training label.
            let alignment: [Int?] = word.count == used ? (0..<used).map { Optional($0) } : aligned
            var gain = 0.0
            for (index, letter) in word.enumerated() {
                guard let offset = alignment[index], part[offset] != letter else { continue }
                guard let label = SpatialWordLexicon.alphabet.firstIndex(of: letter) else { return nil }
                let delta = gains[start + offset][label]
                guard delta >= log(10) else { return nil }
                gain += delta
            }
            // An insertion/deletion pays its edit penalty but contributes no
            // invented tap likelihood. Two OTHER supported parts are still required.
            return min(gain, log(1_000))
        }
        // Flat, fixed-size start/end buckets; input length is capped before allocation.
        let width = count + 1
        var cache = Array(repeating: [Reading](), count: count * width)
        func keep(_ reading: Reading, start: Int, end: Int) {
            let index = start * width + end
            if let old = cache[index].firstIndex(where: { $0.word == reading.word }) {
                guard cache[index][old].score < reading.score else { return }
                cache[index].remove(at: old)
            }
            cache[index].append(reading)
            cache[index].sort { $0.score == $1.score ? $0.word < $1.word : $0.score > $1.score }
            if cache[index].count > beamWidth { cache[index].removeLast() }
        }
        for start in 0..<(count - 1) {
            let length = min(maximumPartLetters, count - start)
            // Original Typr closed-class supplement (≤46 union entries, ≤2 letters).
            for word in shortWords.prefix(46) where word.count <= length {
                let used = word.count
                let part = letters[start..<(start + used)]
                let edits = zip(part, word).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
                guard edits <= 1, let gain = support(word, start: start, used: used, edits: edits) else { continue }
                let score = 0.35 * log(0.01) + Double(edits) * editPenalty + gain
                keep(Reading(word: word, score: score, supportedEdit: gain > 0), start: start, end: start + used)
            }
            let initial: [Int] = Array(0...length)
            let before = visits
            for lexicon in sources {
                func walk(_ index: Int, prefix: String, row: [Int], previousRow: [Int]?,
                          previousLetter: Character?, depth: Int) {
                    guard visits < maximumVisits, visits - before < maximumVisitsPerStart else {
                        exhausted = true
                        return
                    }
                    visits += 1
                    guard let node = lexicon.node(index) else { return }
                    let letter = SpatialWordLexicon.alphabet[node.label]
                    var next = [Int](repeating: 0, count: length + 1)
                    next[0] = depth
                    var minimum = depth
                    for offset in 1...length {
                        let cost = letters[start + offset - 1] == letter ? 0 : 1
                        let replace = row[offset - 1] + cost
                        let insert = row[offset] + 1
                        let delete = next[offset - 1] + 1
                        next[offset] = min(replace, min(insert, delete))
                        if offset > 1, let previousRow, let previousLetter,
                           letter == letters[start + offset - 2],
                           previousLetter == letters[start + offset - 1] {
                            next[offset] = min(next[offset], previousRow[offset - 2] + 1)
                        }
                        minimum = min(minimum, next[offset])
                        cells += 1
                    }
                    guard minimum <= 1 else { return }
                    let word = prefix + String(letter)
                    if node.count > 0 {
                        let prior = 0.35 * log(node.count / lexicon.total)
                        for used in 1...length where next[used] <= 1 {
                            guard let gain = support(word, start: start, used: used, edits: next[used]) else { continue }
                            let score = prior + Double(next[used]) * editPenalty + gain
                            let reading = Reading(word: word, score: score, supportedEdit: gain > 0)
                            keep(reading, start: start, end: start + used)
                        }
                    }
                    guard depth < maximumPartLetters else { return }
                    for child in node.children {
                        walk(child, prefix: word, row: next, previousRow: row,
                             previousLetter: letter, depth: depth + 1)
                    }
                }
                if let root = lexicon.node(0) {
                    for child in root.children {
                        walk(child, prefix: "", row: initial, previousRow: nil, previousLetter: nil, depth: 1)
                    }
                }
            }
            if visits >= maximumVisits { break }
        }
        var beams = Array(repeating: [Run](), count: (maximumParts + 1) * width)
        beams[0] = [Run(words: [], score: 0, supportedEdits: 0)]
        func retain(_ run: Run, at index: Int) {
            if beams[index].contains(where: { $0.words == run.words }) { return }
            beams[index].append(run)
            beams[index].sort {
                if $0.score == $1.score { return $0.words.joined(separator: " ") < $1.words.joined(separator: " ") }
                return $0.score > $1.score
            }
            if beams[index].count > beamWidth { beams[index].removeLast() }
        }
        for parts in 0..<maximumParts {
            for start in 0..<count {
                let runs = beams[parts * width + start]
                guard !runs.isEmpty else { continue }
                let limit = min(count, start + maximumPartLetters)
                for end in (start + 1)...limit {
                    for reading in cache[start * width + end] {
                        for run in runs {
                            let penalty = parts == 0 ? 0 : KeyboardBoundaryDecoder.missingSpacePenalty
                            let score = run.score + reading.score + penalty
                            let edited = run.supportedEdits + (reading.supportedEdit ? 1 : 0)
                            let extended = Run(words: run.words + [reading.word], score: score, supportedEdits: edited)
                            retain(extended, at: (parts + 1) * width + end)
                        }
                    }
                }
            }
        }
        var finished: [Run] = []
        for parts in 3...maximumParts { finished += beams[parts * width + count] }
        finished = finished.filter { $0.supportedEdits >= 2 }
        finished.sort {
            if $0.score == $1.score { return $0.words.joined(separator: " ") < $1.words.joined(separator: " ") }
            return $0.score > $1.score
        }
        let retained = cache.reduce(0) { $0 + $1.count }
        return Result(runs: Array(finished.prefix(beamWidth)), visits: visits, cells: cells,
                      cachedReadings: retained, exhausted: exhausted)
    }
}
