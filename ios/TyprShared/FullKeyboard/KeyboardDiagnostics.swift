import Foundation

/// Text-free, bounded counters. These describe observed events, not accuracy.
nonisolated struct KeyboardDiagnostics: Codable, Equatable, Sendable {
    enum Counter: String, Codable, CaseIterable, Sendable {
        case boundaries, evidenceComplete, evidenceMissing, evidenceLengthOutOfRange, evidenceUnsupported
        case autoSpatialSameLength, autoSpatialEdit, autoSpellingFallback, autoRule, unchanged
        case refusedLiteralValid, refusedProtected, refusedAmbiguous, refusedIncompleteSearch
        case refusedMissingResource, refusedValidation, refusedBelowMargin, refusedEditNeedsInvalidLiteral
        case undoSpatial, undoSpelling, undoRule, keepChip, manualAlternativePick, manualCompletionPick
        case suggestionDecodes, wordsCounted, wordsKept, correctionsRejected, storeCorruptDiscarded, storeWriteFailed
    }

    enum LatencyKind: Sendable { case boundary, suggestion }

    private(set) var schemaVersion = 1
    private(set) var since: Date
    private(set) var updatedAt: Date
    private(set) var counters: [String: Int] = [:]
    /// Milliseconds: <1, 1–2, 2–5, 5–10, 10–20, 20–50, ≥50.
    private(set) var boundaryMs = Array(repeating: 0, count: 7)
    private(set) var suggestionMs = Array(repeating: 0, count: 7)

    init(now: Date = Date()) { since = now; updatedAt = now }

    subscript(_ counter: Counter) -> Int { counters[counter.rawValue, default: 0] }

    mutating func increment(_ counter: Counter, by amount: Int = 1) {
        guard amount > 0 else { return }
        counters[counter.rawValue] = Self.add(counters[counter.rawValue, default: 0], amount)
        updatedAt = max(since, Date())
    }

    mutating func recordLatency(_ seconds: Double, kind: LatencyKind) {
        guard seconds.isFinite, seconds >= 0 else { return }
        // Compare seconds directly, avoiding overflow when converting a large finite value to ms.
        let index = [0.001, 0.002, 0.005, 0.010, 0.020, 0.050].firstIndex { seconds < $0 } ?? 6
        switch kind {
        case .boundary: boundaryMs[index] = Self.add(boundaryMs[index], 1)
        case .suggestion: suggestionMs[index] = Self.add(suggestionMs[index], 1)
        }
        updatedAt = max(since, Date())
    }

    private static func add(_ current: Int, _ amount: Int) -> Int {
        current + min(amount, Int(Int32.max) - current)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, since, updatedAt, counters, boundaryMs, suggestionMs
    }

    private struct CounterKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ counter: Counter) { stringValue = counter.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        since = try values.decode(Date.self, forKey: .since)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        let decoded = try values.nestedContainer(keyedBy: CounterKey.self, forKey: .counters)
        for counter in Counter.allCases {
            let key = CounterKey(counter)
            if decoded.contains(key) { counters[counter.rawValue] = try decoded.decode(Int.self, forKey: key) }
        }
        boundaryMs = try values.decode([Int].self, forKey: .boundaryMs)
        suggestionMs = try values.decode([Int].self, forKey: .suggestionMs)
        guard schemaVersion == 1, since.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite, updatedAt >= since,
              boundaryMs.count == 7, suggestionMs.count == 7,
              (Array(counters.values) + boundaryMs + suggestionMs).allSatisfy({ (0...Int(Int32.max)).contains($0) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid keyboard diagnostics"))
        }
    }
}
