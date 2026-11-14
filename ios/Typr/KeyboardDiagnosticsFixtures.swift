import Foundation

/// Synthetic, in-memory dashboard data; never seeds the shared store or preferences.
@MainActor
enum KeyboardDiagnosticsFixture {
    static let now = Date(timeIntervalSince1970: 1_750_000_000)
    static var isRequested: Bool { requested(arguments: ProcessInfo.processInfo.arguments) }

    static func requested(arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "--snap-state"), index + 1 < arguments.count else { return false }
        return arguments[index + 1] == "settings-keyboard-diagnostics"
    }

    static func snapshot() -> KeyboardLearningSnapshot {
        var state = PersonalTypingModel.State()
        let portrait = KeyboardLayout(width: 392, showsGlobe: true, showsStrip: false)
        let landscape = KeyboardLayout(width: 848, orientation: .landscape, showsGlobe: true)
        for (index, layout) in [portrait, landscape].enumerated() {
            let signature = KeyboardLayoutSignature(layout)
            var stats = PersonalTypingModel.LayoutStats(signature: signature, lastUpdated: now.addingTimeInterval(-120))
            for (index, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
                stats.keys[String(letter)] = PersonalTypingModel.TouchStats(
                    n: index % 5 == 0 ? 12 : 40 + index,
                    meanX: index % 2 == 0 ? 0.12 : -0.08, meanY: 0.06,
                    varianceX: 0.075, varianceY: 0.09)
            }
            if index == 1 { stats.keys = ["a": stats.keys["a"], "e": stats.keys["e"]].compactMapValues { $0 } }
            state.layouts[signature.id] = stats
        }
        state.kept = ["hello": now, "world": now]
        state.counts = ["hello": .init(count: 12, lastUpdated: now), "world": .init(count: 8, lastUpdated: now)]
        state.rejected = [.init(typed: "cat", replacement: "car")]
        let counters: [(KeyboardDiagnostics.Counter, Int)] = [
            (.boundaries, 1000), (.evidenceComplete, 820), (.evidenceMissing, 120),
            (.evidenceLengthOutOfRange, 40), (.evidenceUnsupported, 20),
            (.autoSpatialSameLength, 110), (.autoSpatialEdit, 25), (.autoSpellingFallback, 35),
            (.autoRule, 80), (.unchanged, 750), (.refusedLiteralValid, 510), (.refusedProtected, 90),
            (.refusedAmbiguous, 40), (.refusedIncompleteSearch, 5), (.refusedMissingResource, 2),
            (.refusedValidation, 18), (.refusedBelowMargin, 45), (.resourceLoading, 4),
            (.undoSpatial, 6), (.undoSpelling, 2), (.undoRule, 1), (.keepChip, 16),
            (.manualAlternativePick, 28), (.manualCompletionPick, 42), (.personalCompletionPick, 11),
            (.suggestionDecodes, 3200),
            (.wordsCounted, 750), (.wordsKept, 16), (.correctionsRejected, 9)]
        // Decode the same public schema to keep even updatedAt deterministic; normal counter
        // recording deliberately uses the wall clock. No fixture file is read or written.
        let payload: [String: Any] = ["schemaVersion": 1,
            "acceptedBySource": ["literalValid": 960, "keep": 80, "undo": 24, "manualPick": 100],
            "rejectedByReason": ["outlier": 18, "ambiguousAlignment": 6, "layoutMismatch": 2],
            "since": now.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSinceReferenceDate,
            "updatedAt": now.addingTimeInterval(-120).timeIntervalSinceReferenceDate,
            "counters": Dictionary(uniqueKeysWithValues: counters.map { ($0.0.rawValue, $0.1) }),
            "boundaryMs": [28, 24, 20, 16, 12, 8, 4], "suggestionMs": [56, 48, 40, 32, 24, 16, 8]]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let diagnostics = data.flatMap { try? JSONDecoder().decode(KeyboardDiagnostics.self, from: $0) }
            ?? KeyboardDiagnostics(now: now)
        return KeyboardLearningSnapshot(model: PersonalTypingModel.summarize(state), diagnostics: diagnostics,
            learningFile: .init(bytes: 18_432, modifiedAt: now.addingTimeInterval(-120)),
            diagnosticsFile: .init(bytes: 2048, modifiedAt: now.addingTimeInterval(-120)), isPersistent: true)
    }
}

