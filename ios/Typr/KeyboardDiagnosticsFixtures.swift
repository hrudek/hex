import Foundation

/// Exact, finite scene grammar. Parsing has no actor, UI, settings or store dependency.
nonisolated enum KeyboardDiagnosticsFixture {
    enum State: String, CaseIterable, Sendable {
        case populated, empty, zero, statisticsOnly, learningOnly, unreadable, stale, invalid
        case small, learningOff, inconsistent, unsampled, singleLayout, removedLayout

        var suffix: String {
            switch self {
            case .populated: ""
            case .statisticsOnly: "-statistics-only"
            case .learningOnly: "-learning-only"
            case .learningOff: "-learning-off"
            case .singleLayout: "-single-layout"
            case .removedLayout: "-removed-layout"
            default: "-\(rawValue)"
            }
        }
    }

    struct Scene: Equatable, Sendable {
        let page: KeyboardDiagnosticsPage
        let state: State
        var name: String {
            let base = "settings-keyboard-diagnostics"
            let pageSuffix: String
            switch page {
            case .overview: pageSuffix = ""
            case .wordChecks: pageSuffix = "-word-checks"
            case .speed: pageSuffix = "-speed"
            case .learning: pageSuffix = "-learning"
            }
            return base + pageSuffix + state.suffix
        }
    }

    struct Context: Sendable {
        let page: KeyboardDiagnosticsPage
        let state: State
        let snapshot: KeyboardLearningSnapshot
        let now: Date
        let learningEnabled: Bool
        /// For a deterministic test of selection fallback after a layout disappears.
        let removedLayoutID: String?

        func navigating(to page: KeyboardDiagnosticsPage) -> Context {
            Context(page: page, state: state, snapshot: snapshot, now: now,
                    learningEnabled: learningEnabled, removedLayoutID: removedLayoutID)
        }
    }

    static let now = Date(timeIntervalSince1970: 1_750_000_000)
    static let scenes = KeyboardDiagnosticsPage.allCases.flatMap { page in
        State.allCases.map { Scene(page: page, state: $0) }
    }
    private static let lookup = Dictionary(uniqueKeysWithValues: scenes.map { ($0.name, $0) })

    static func scene(named name: String) -> Scene? { lookup[name] }

    static func scene(arguments: [String]) -> Scene? {
        guard let index = arguments.firstIndex(of: "--snap-state"), index + 1 < arguments.count else { return nil }
        return scene(named: arguments[index + 1])
    }

    @MainActor
    static func context(for scene: Scene) -> Context {
        let removedID = scene.state == .removedLayout
            ? snapshot(state: .populated).model.layouts.first { $0.signature.orientation == "landscape" }?.signature.id : nil
        return Context(page: scene.page, state: scene.state, snapshot: snapshot(state: scene.state), now: now,
                       learningEnabled: scene.state != .learningOff, removedLayoutID: removedID)
    }

    @MainActor
    static func context(arguments: [String]) -> Context? {
        scene(arguments: arguments).map { context(for: $0) }
    }

    /// Synthetic aggregates only; never seeds shared storage or preferences.
    @MainActor
    static func snapshot(state variant: State) -> KeyboardLearningSnapshot {
        var state = PersonalTypingModel.State()
        let portrait = KeyboardLayout(width: 392, showsGlobe: true, showsStrip: false)
        let landscape = KeyboardLayout(width: 848, orientation: .landscape, showsGlobe: true)
        for (index, layout) in [portrait, landscape].enumerated() {
            let signature = KeyboardLayoutSignature(layout)
            var stats = PersonalTypingModel.LayoutStats(signature: signature, lastUpdated: now.addingTimeInterval(index == 0 ? -120 : -240))
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
        state.bigrams?.record("world", after: "hello", earlier: "say")
        var counters: [KeyboardDiagnostics.Counter: Int] = [
            .boundaries: 1000, .evidenceComplete: 820, .evidenceMissing: 120,
            .evidenceLengthOutOfRange: 40, .evidenceUnsupported: 20,
            .autoSpatialSameLength: 110, .autoSpatialEdit: 25, .autoSpellingFallback: 35,
            .autoRule: 80, .unchanged: 750, .refusedLiteralValid: 510, .refusedProtected: 90,
            .refusedAmbiguous: 40, .refusedIncompleteSearch: 5, .refusedMissingResource: 2,
            .refusedValidation: 18, .refusedBelowMargin: 45, .resourceLoading: 4,
            .undoSpatial: 6, .undoSpelling: 2, .undoRule: 1, .keepChip: 16,
            .manualAlternativePick: 28, .manualCompletionPick: 42, .personalCompletionPick: 11,
            .suggestionDecodes: 3200, .wordsCounted: 750, .wordsKept: 16, .correctionsRejected: 9,
            .reattributedTaps: 12, .storeCorruptDiscarded: 0, .storeWriteFailed: 0, .storeLoadDeferred: 0]
        var boundary = [250, 200, 180, 160, 110, 70, 30]
        var suggestion = [800, 640, 560, 480, 400, 240, 80]
        var accepted = ["literalValid": 960, "keep": 80, "undo": 24, "manualPick": 100]
        var rejected = ["outlier": 18, "nonFinite": 1, "unknownKey": 2,
                        "ambiguousAlignment": 6, "layoutMismatch": 2, "learningOff": 3]
        var learningFile = KeyboardLearningSnapshot.FileInfo(bytes: 18_432, modifiedAt: now.addingTimeInterval(-120))
        var statisticsFile = KeyboardLearningSnapshot.FileInfo(bytes: 2048, modifiedAt: now.addingTimeInterval(-120))
        let missing = KeyboardLearningSnapshot.FileInfo(bytes: nil, modifiedAt: nil)
        switch variant {
        case .empty:
            state = .init(); counters = [:]; boundary = Array(repeating: 0, count: 7)
            suggestion = boundary; accepted = [:]; rejected = [:]
            learningFile = missing; statisticsFile = missing
        case .zero:
            counters = [:]; boundary = Array(repeating: 0, count: 7); suggestion = boundary
            accepted = [:]; rejected = [:]
        case .statisticsOnly: learningFile = missing; state = .init()
        case .learningOnly:
            statisticsFile = missing; counters = [:]; boundary = Array(repeating: 0, count: 7)
            suggestion = boundary; accepted = [:]; rejected = [:]
        case .stale: learningFile = .init(bytes: 18_432, modifiedAt: now.addingTimeInterval(-86_401))
        case .invalid: counters[.storeCorruptDiscarded] = 2
        case .small:
            counters = [.boundaries: 1, .evidenceMissing: 1, .unchanged: 1, .suggestionDecodes: 2]
            boundary = [0, 0, 1, 0, 0, 0, 0]; suggestion = [1, 0, 0, 0, 0, 0, 1]
            accepted = [:]; rejected = [:]
        case .inconsistent:
            counters[.autoSpatialSameLength] = Int(Int32.max)
            counters[.autoSpatialEdit] = Int(Int32.max)
            counters[.evidenceMissing] = Int(Int32.max)
            counters[.undoSpatial] = Int(Int32.max); counters[.undoSpelling] = 36
            counters[.undoRule] = 81; counters[.personalCompletionPick] = 43
            boundary = Array(repeating: Int(Int32.max), count: 7)
            suggestion = [1, 0, 0, 0, 0, 0, 0]
        case .singleLayout, .removedLayout:
            state.layouts = state.layouts.filter { $0.value.signature.orientation == "portrait" }
        case .populated, .unreadable, .learningOff, .unsampled: break
        }
        // Decode the public schema to avoid wall-clock timestamps in recording methods.
        // A broken synthetic payload is a programming error, never a real-store fallback.
        let payload: [String: Any] = ["schemaVersion": 1,
            "acceptedBySource": accepted, "rejectedByReason": rejected,
            "since": now.addingTimeInterval(-7 * 86_400).timeIntervalSinceReferenceDate,
            "updatedAt": now.addingTimeInterval(-120).timeIntervalSinceReferenceDate,
            "counters": Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) }),
            "boundaryMs": boundary, "suggestionMs": suggestion]
        let diagnostics = try! JSONDecoder().decode(KeyboardDiagnostics.self,
            from: JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        var summary = PersonalTypingModel.summarize(state)
        if variant == .unsampled {
            let layouts = summary.layouts.map { layout in
                PersonalTypingModel.LayoutSummary(signature: layout.signature, lastUpdated: layout.lastUpdated,
                    keys: [0, 19, 20, 256].enumerated().map { index, n in
                        PersonalTypingModel.KeySummary(letter: ["a", "b", "c", "d"][index], n: n,
                            offsetX: 0.12, offsetY: -0.06, sigmaX: 0.3, sigmaY: 0.2, covarianceXY: 0.02)
                    })
            }
            summary = .init(layouts: layouts, keptWords: summary.keptWords, countedWords: summary.countedWords,
                wordCountTotal: summary.wordCountTotal, rejectedCorrections: summary.rejectedCorrections,
                storedPairs: summary.storedPairs, pairByteBound: summary.pairByteBound)
        }
        return KeyboardLearningSnapshot(model: summary, diagnostics: diagnostics,
            learningFile: learningFile, diagnosticsFile: statisticsFile, isPersistent: variant != .unreadable)
    }
}
