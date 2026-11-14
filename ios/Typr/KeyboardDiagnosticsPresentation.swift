import Foundation

nonisolated enum KeyboardDiagnosticsPresentation {
    typealias Counter = KeyboardDiagnostics.Counter
    static let histogramLabels = ["<1 ms", "1–2 ms", "2–5 ms", "5–10 ms", "10–20 ms", "20–50 ms", "≥50 ms"]
    static let decisions: [Counter] = [.autoSpatialSameLength, .autoSpatialEdit, .autoSpellingFallback, .autoRule, .unchanged]
    static let refusals: [Counter] = [.refusedLiteralValid, .refusedProtected, .refusedAmbiguous,
        .refusedIncompleteSearch, .refusedMissingResource, .refusedValidation, .refusedBelowMargin,
        .resourceLoading]
    static let feedback: [Counter] = [.undoSpatial, .undoSpelling, .undoRule, .keepChip,
        .manualAlternativePick, .manualCompletionPick, .personalCompletionPick]

    /// Counts, not an accuracy estimate; even an empty denominator remains visible.
    static func share(_ numerator: Int, of denominator: Int) -> String {
        "\(numerator.formatted()) of \(denominator.formatted())"
    }

    static func automaticTotal(_ diagnostics: KeyboardDiagnostics) -> Int {
        [.autoSpatialSameLength, .autoSpatialEdit, .autoSpellingFallback, .autoRule]
            .reduce(0) { $0 + diagnostics[$1] }
    }

    static func undoTotal(_ diagnostics: KeyboardDiagnostics) -> Int {
        [.undoSpatial, .undoSpelling, .undoRule].reduce(0) { $0 + diagnostics[$1] }
    }

    static func barShare(_ count: Int, maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return max(0, min(1, Double(count) / Double(maximum)))
    }

    /// Exhaustive on purpose: a new engine counter must receive plain-language copy.
    static func label(_ counter: Counter) -> String {
        switch counter {
        case .boundaries: "Words checked"
        case .evidenceComplete: "Complete touch evidence"
        case .evidenceMissing: "No evidence or invalidated taps"
        case .evidenceLengthOutOfRange: "Word length outside supported range"
        case .evidenceUnsupported: "Unsupported input"
        case .autoSpatialSameLength: "Spatial: same length"
        case .autoSpatialEdit: "Spatial: missing, extra or swapped letter"
        case .autoSpellingFallback: "Spelling fallback"
        case .autoRule: "Rules and text replacements"
        case .unchanged: "Left unchanged"
        case .refusedLiteralValid: "Typed word is valid"
        case .refusedProtected: "Protected word, rejected correction, capitals or identifier"
        case .refusedAmbiguous: "Alternatives too close to call"
        case .refusedIncompleteSearch: "Search limit reached"
        case .refusedMissingResource: "Dictionary resource unavailable"
        case .refusedValidation: "Dictionary did not confirm the replacement"
        case .refusedBelowMargin: "Not enough evidence to replace"
        case .resourceLoading: "Word data still loading"
        case .undoSpatial: "Undid spatial replacement"
        case .undoSpelling: "Undid spelling replacement"
        case .undoRule: "Undid rule or text replacement"
        case .keepChip: "Kept as typed"
        case .manualAlternativePick: "Picked alternative"
        case .manualCompletionPick: "Picked completion"
        case .suggestionDecodes: "Suggestion searches"
        case .wordsCounted: "Word choices counted"
        case .wordsKept: "Words explicitly kept"
        case .correctionsRejected: "Corrections rejected"
        case .storeCorruptDiscarded: "Invalid saved files discarded"
        case .storeWriteFailed: "Save failures or repairs"
        case .storeLoadDeferred: "Deferred learning loads"
        case .personalCompletionPick: "Picked personal completion"
        case .reattributedTaps: "Reattributed letter taps"
        }
    }

    static func sourceLabel(_ source: TouchLabelSource) -> String {
        switch source {
        case .literalValid: "Valid word left as typed"
        case .keep: "Explicit keep"
        case .undo: "Undo of replacement"
        case .manualPick: "Picked alternative"
        }
    }

    static func rejectionLabel(_ reason: TouchLabelRejection) -> String {
        switch reason {
        case .outlier: "Too far from intended key"
        case .nonFinite: "Invalid position"
        case .unknownKey: "Unsupported key or field"
        case .layoutMismatch: "Layout changed"
        case .ambiguousAlignment: "Uncertain letter alignment"
        case .learningOff: "Learning switched off"
        }
    }

    static func updatedAt(_ snapshot: KeyboardLearningSnapshot) -> Date? {
        [snapshot.learningFile.modifiedAt, snapshot.diagnosticsFile.modifiedAt].compactMap { $0 }.max()
    }

    static func availability(_ snapshot: KeyboardLearningSnapshot, now: Date) -> String? {
        guard let updated = updatedAt(snapshot) else {
            return "Full Access is off or the keyboard hasn't saved data yet."
        }
        if !snapshot.isPersistent || now.timeIntervalSince(updated) > 24 * 60 * 60 {
            return "Showing the last saved snapshot. Full Access may be off, or the keyboard has not saved recently."
        }
        return nil
    }

    static func fileSize(_ bytes: Int?) -> String {
        guard let bytes else { return "Not saved yet" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

