import Foundation
import CoreGraphics
import Observation

/// App-side read/reset adapter. Never saves learning or exposes retained words to the view.
@MainActor @Observable
final class KeyboardDiagnosticsModel {
    private(set) var snapshot: KeyboardLearningSnapshot
    private(set) var learningEnabled: Bool
    private(set) var resetProblem: String?
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let fixture: Bool
    @ObservationIgnored private var observer: KeyboardLearningObserver?

    init(directory: URL? = KeyboardLearningStore.sharedDirectory,
         defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.directory = directory
        self.defaults = defaults
        fixture = false
        snapshot = KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults)
        learningEnabled = TyprSettings(defaults: defaults).personalLearning
    }

    /// Snapshot scenes stay entirely in memory, including refresh and reset actions.
    init(fixture: KeyboardLearningSnapshot) {
        directory = nil
        defaults = nil
        self.fixture = true
        snapshot = fixture
        learningEnabled = true
    }

    func startObserving() {
        guard !fixture else { return }
        if observer == nil {
            // Snapshot-driven refresh adapted from AVGVSTVS96/iikb App/Stats/TapsPage.swift (MIT).
            observer = KeyboardLearningObserver { [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stopObserving() {
        observer?.invalidate()
        observer = nil
    }

    func refresh() {
        guard !fixture else { return }
        snapshot = KeyboardLearningStore.readSnapshot(directory: directory, defaults: defaults)
        learningEnabled = TyprSettings(defaults: defaults).personalLearning
    }

    func resetLearning() { reset(learning: true) }
    func resetStatistics() { reset(learning: false) }

    private func reset(learning: Bool) {
        guard !fixture else { return }
        let store = KeyboardLearningStore(directory: directory, defaults: defaults)
        let success = learning ? store.requestLearningReset() : store.requestDiagnosticsReset()
        resetProblem = success ? nil : "Could not reset saved data. Try again when Typr can access its shared storage."
        refresh()
    }
}

nonisolated enum KeyboardDiagnosticsPresentation {
    typealias Counter = KeyboardDiagnostics.Counter
    static let histogramLabels = ["<1 ms", "1–2 ms", "2–5 ms", "5–10 ms", "10–20 ms", "20–50 ms", "≥50 ms"]
    static let decisions: [Counter] = [.autoSpatialSameLength, .autoSpatialEdit, .autoSpellingFallback, .autoRule, .unchanged]
    static let refusals: [Counter] = [.refusedLiteralValid, .refusedProtected, .refusedAmbiguous,
        .refusedIncompleteSearch, .refusedMissingResource, .refusedValidation, .refusedBelowMargin,
        .resourceLoading]
    static let feedback: [Counter] = [.undoSpatial, .undoSpelling, .undoRule, .keepChip,
        .manualAlternativePick, .manualCompletionPick]

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

/// Reconstruct bucket geometry, not hit targets. The personal model already shrinks offsets and sigma.
nonisolated enum KeyboardTouchGeometry {
    static func layout(for signature: KeyboardLayoutSignature) -> KeyboardLayout {
        KeyboardLayout(width: CGFloat(signature.widthBucket),
            orientation: signature.orientation == "landscape" ? .landscape : .portrait,
            layer: .letters, showsGlobe: signature.showsGlobe, showsStrip: signature.showsStrip)
    }

    static func center(for summary: PersonalTypingModel.KeySummary, key: KeyboardKey,
                       layout: KeyboardLayout) -> CGPoint {
        CGPoint(x: key.frame.midX + CGFloat(summary.offsetX) * (key.frame.width + layout.metrics.gap),
                y: key.frame.midY + CGFloat(summary.offsetY) * (key.frame.height + layout.metrics.rowGap))
    }

    // Pitch-to-point display adapted from AVGVSTVS96/iikb
    // Packages/KeyboardModules/Sources/KeyboardCore/Correction/Aim.swift (MIT).
    static func ellipse(for summary: PersonalTypingModel.KeySummary, key: KeyboardKey,
                        layout: KeyboardLayout) -> CGRect {
        let center = center(for: summary, key: key, layout: layout)
        let rx = CGFloat(summary.sigmaX) * (key.frame.width + layout.metrics.gap)
        let ry = CGFloat(summary.sigmaY) * (key.frame.height + layout.metrics.rowGap)
        return CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
    }

    static func title(_ signature: KeyboardLayoutSignature) -> String {
        let orientation = signature.orientation == "landscape" ? "Landscape" : "Portrait"
        return "\(orientation), \(signature.widthBucket) pt, \(signature.showsStrip ? "suggestions" : "no suggestions"), \(signature.showsGlobe ? "globe" : "no globe")"
    }
}
