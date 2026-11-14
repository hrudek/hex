import Foundation

nonisolated enum KeyboardDiagnosticsPresentation {
    typealias Counter = KeyboardDiagnostics.Counter
    static let decisions: [Counter] = [.autoSpatialSameLength, .autoSpatialEdit, .autoSpellingFallback, .autoRule, .unchanged]
    static let feedback: [Counter] = [.undoSpatial, .undoSpelling, .undoRule, .keepChip,
        .manualAlternativePick, .manualCompletionPick, .personalCompletionPick]

    static func automaticTotal(_ diagnostics: KeyboardDiagnostics) -> Int {
        [.autoSpatialSameLength, .autoSpatialEdit, .autoSpellingFallback, .autoRule]
            .reduce(0) { $0 + diagnostics[$1] }
    }

    static func undoTotal(_ diagnostics: KeyboardDiagnostics) -> Int {
        [.undoSpatial, .undoSpelling, .undoRule].reduce(0) { $0 + diagnostics[$1] }
    }
}

nonisolated enum KeyboardDiagnosticsPage: String, CaseIterable, Sendable {
    case overview, wordChecks, speed, learning
}

// Pages consume make(...) only: no store access, normalization or live permission inference.
extension KeyboardDiagnosticsPresentation {
    struct CountRow: Identifiable, Equatable, Sendable {
        let id: Counter
        let count: Int
        var label: String { KeyboardDiagnosticsPresentation.counterLabel(id) }
    }

    struct Partition: Equatable, Sendable {
        let rows: [CountRow]
        let population: Int
        var sum: Int { rows.reduce(0) { $0 + $1.count } }
        var isConsistent: Bool { sum == population }
        var canShowParts: Bool { population > 0 && isConsistent }
        func inconsistencyText(locale: Locale = .current) -> String? {
            guard !isConsistent else { return nil }
            return "These counts add up to \(KeyboardDiagnosticsPresentation.integer(sum, locale: locale)), not \(KeyboardDiagnosticsPresentation.integer(population, locale: locale)). Some counters may be incomplete."
        }
    }

    struct Comparison: Equatable, Sendable {
        enum Status: Equatable, Sendable { case empty, comparable, incomparable }
        let numerator: Int
        let denominator: Int
        let status: Status

        init(_ numerator: Int, of denominator: Int, allowed: Bool = true) {
            self.numerator = numerator
            self.denominator = denominator
            status = !allowed || numerator > denominator ? .incomparable
                : denominator == 0 ? .empty : .comparable
        }
    }

    struct MethodFeedback: Identifiable, Equatable, Sendable {
        let id: Counter
        let comparison: Comparison
    }

    struct RefusalGroup: Identifiable, Equatable, Sendable {
        enum ID: String, Sendable { case guards, uncertainty, wordData }
        let id: ID
        let title: String
        let rows: [CountRow]
    }

    struct File: Sendable {
        let bytes: Int?
        let modifiedAt: Date?
        var hasMetadata: Bool { bytes != nil || modifiedAt != nil }
        func sizeText() -> String {
            guard let bytes else { return "No file size available" }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    struct Scope: Sendable {
        enum Notice: Equatable, Sendable {
            case unreadable, stale
            var text: String {
                switch self {
                case .unreadable: "Typr couldn't read its saved typing data."
                case .stale: "At least one saved file is more than 24 hours old. Anything typed since then that wasn't saved isn't shown here."
                }
            }
        }
        enum SavedTimeSource: Equatable, Sendable { case both, statisticsOnly, learningOnly, none }
        let learningFile: File
        let statisticsFile: File
        let statisticsAvailable: Bool
        let learningAvailable: Bool
        let statisticsSince: Date?
        let savedAt: Date?
        let savedTimeSource: SavedTimeSource
        let notice: Notice?
    }

    struct Bucket: Identifiable, Equatable, Sendable {
        let id: Int
        let count: Int
        var upperMilliseconds: Int? { [1, 2, 5, 10, 20, 50, nil][id] }
        var label: String {
            ["Under 1 ms", "1 up to 2 ms", "2 up to 5 ms", "5 up to 10 ms",
             "10 up to 20 ms", "20 up to 50 ms", "50 ms or more"][id]
        }
        var tick: String { ["<1", "1–<2", "2–<5", "5–<10", "10–<20", "20–<50", "≥50"][id] }
    }

    struct Latency: Equatable, Sendable {
        let buckets: [Bucket]
        let referenceCount: Int
        let halfBucket: Bucket?
        let highestBucket: Bucket?
        var n: Int { buckets.reduce(0) { $0 + $1.count } }
        var differsFromReference: Bool { n != referenceCount }
        func discrepancyText(locale: Locale = .current) -> String? {
            guard differsFromReference else { return nil }
            return "The histogram contains \(KeyboardDiagnosticsPresentation.integer(n, locale: locale)) measurements; the event counter records \(KeyboardDiagnosticsPresentation.integer(referenceCount, locale: locale)). Both saved counts are shown."
        }
        func halfText(locale: Locale = .current) -> String {
            guard let halfBucket else { return "No measurements recorded in the available statistics." }
            guard let upper = halfBucket.upperMilliseconds else { return "At least half took 50 ms or more." }
            return "At least half took under \(KeyboardDiagnosticsPresentation.integer(upper, locale: locale)) ms."
        }
    }

    struct Statistics: Sendable {
        let decisions: Partition
        let evidence: Partition
        let automatic: Comparison
        let undo: Comparison
        let methods: [MethodFeedback]
        let refusalGroups: [RefusalGroup]
        let choices: [CountRow]
        let personalCompletionIsSubset: Bool
        let learningEvents: [CountRow]
        let acceptedBySource: [LabelCount]
        let rejectedByReason: [LabelCount]
        let storageEvents: [CountRow]
        let reattributedTaps: Int
        let wordCheckTime: Latency
        let suggestionTime: Latency
        var acceptedTotal: Int { acceptedBySource.reduce(0) { $0 + $1.count } }
        var rejectedTotal: Int { rejectedByReason.reduce(0) { $0 + $1.count } }
        func historicalStorageText(locale: Locale = .current) -> String? {
            let count = storageEvents.first { $0.id == .storeCorruptDiscarded }?.count ?? 0
            guard count > 0 else { return nil }
            return "Typr ignored saved data it couldn't use (\(KeyboardDiagnosticsPresentation.integer(count, locale: locale)) times in the available statistics). Data from before that may be missing."
        }
    }

    struct LabelCount: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let count: Int
    }

    struct KeyRow: Identifiable, Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case none, few, twentyOrMore
            var text: String {
                switch self {
                case .none: "No tap examples"
                case .few: "Fewer than 20 tap examples"
                case .twentyOrMore: "20 or more tap examples"
                }
            }
        }
        let id: String // Uppercase A–Z, in chart/table order.
        let n: Int
        let status: Status
        let offset: String?
        let halfLengths: String?
        let direction: String?
        var offsetText: String { offset ?? "Not available" }
        var halfLengthsText: String { halfLengths ?? "Not available" }
        var directionText: String { direction ?? "Not available" }
        func accessibilityLabel(locale: Locale = .current) -> String {
            guard let offset else { return "\(id), no tap examples, model offset not available" }
            return "\(id), \(KeyboardDiagnosticsPresentation.integer(n, locale: locale)) tap examples, model offset \(offset)"
        }
        var shapeAccessibilityLabel: String {
            guard let halfLengths, let direction else { return "\(id), model shape not available" }
            return "\(id), \(halfLengths), \(direction)"
        }
    }

    struct Layout: Identifiable, Sendable {
        let summary: PersonalTypingModel.LayoutSummary
        let title: String
        let keys: [KeyRow]
        var id: String { summary.signature.id }
        var keysWithTwentyExamples: Int { keys.filter { $0.status == .twentyOrMore }.count }
        func coverageText(locale: Locale = .current) -> String {
            "\(KeyboardDiagnosticsPresentation.integer(keysWithTwentyExamples, locale: locale)) of 26 keys with 20 or more tap examples – \(title)"
        }
    }

    struct Learning: Sendable {
        let keptWords: Int
        let countedWords: Int
        let storedPairs: Int
        let rejectedCorrections: Int
        let wordCountTotal: Int
        let pairByteBound: Int
        let layouts: [Layout] // Newest first, then signature ID ascending.
        func selectedLayout(id: String?) -> Layout? {
            layouts.first { $0.id == id } ?? layouts.first
        }
    }

    struct Readout: Sendable {
        let scope: Scope
        let learningEnabled: Bool
        let statistics: Statistics?
        let learning: Learning?
        var learningExplanation: String {
            learningEnabled ? KeyboardDiagnosticsPresentation.learningOnText : KeyboardDiagnosticsPresentation.learningOffText
        }
    }

    static let evidenceCounters: [Counter] = [.evidenceComplete, .evidenceMissing, .evidenceLengthOutOfRange, .evidenceUnsupported]
    static let choiceCounters: [Counter] = [.keepChip, .manualAlternativePick, .manualCompletionPick, .personalCompletionPick]
    static let learningCounters: [Counter] = [.wordsCounted, .wordsKept, .correctionsRejected]
    static let storageCounters: [Counter] = [.storeCorruptDiscarded, .storeWriteFailed, .storeLoadDeferred]
    static let refusalMapping: [(RefusalGroup.ID, String, [Counter])] = [
        (.guards, "Guards", [.refusedLiteralValid, .refusedProtected]),
        (.uncertainty, "Not certain enough to replace", [.refusedAmbiguous, .refusedIncompleteSearch, .refusedBelowMargin, .refusedValidation]),
        (.wordData, "Word data", [.refusedMissingResource, .resourceLoading])]
    static var mappedCounters: Set<Counter> {
        Set([.boundaries, .suggestionDecodes, .reattributedTaps] + decisions + evidenceCounters
            + feedback + learningCounters + storageCounters + refusalMapping.flatMap { $0.2 })
    }

    static let learningOnText = "Typr adapts to your taps, word counts and word contexts. Without Full Access, learning lasts only for the keyboard session and can't be shown here."
    static let learningOffText = "Typr doesn't learn new taps, word counts or word contexts, and doesn't use them for suggestions or tap positions. Saved data stays. Kept words and rejected corrections still prevent unwanted replacements, and undoing a replacement still saves a rejected correction."
    static let learningEventsHelp = "Counts of learning events in the available statistics. Repeating the same word counts again. These are events, not the number of different words. Words you kept and corrections rejected can increase while learning is off."
    static let belowMarginHelp = "No candidate was clearly better, or the candidate would only have completed the word. Can come from tap positions or the spelling check."

    static func make(snapshot: KeyboardLearningSnapshot, learningEnabled: Bool, now: Date,
                     locale: Locale = .current) -> Readout {
        let learningFile = File(bytes: snapshot.learningFile.bytes, modifiedAt: snapshot.learningFile.modifiedAt)
        let statisticsFile = File(bytes: snapshot.diagnosticsFile.bytes, modifiedAt: snapshot.diagnosticsFile.modifiedAt)
        let times = [learningFile.modifiedAt, statisticsFile.modifiedAt].compactMap { $0 }
        let stale = times.contains { now.timeIntervalSince($0) > 86_400 }
        let statisticsAvailable = snapshot.isPersistent && statisticsFile.hasMetadata
        let learningAvailable = snapshot.isPersistent && learningFile.hasMetadata
        let source: Scope.SavedTimeSource = learningFile.modifiedAt != nil
            ? (statisticsFile.modifiedAt != nil ? .both : .learningOnly)
            : (statisticsFile.modifiedAt != nil ? .statisticsOnly : .none)
        let scope = Scope(learningFile: learningFile, statisticsFile: statisticsFile,
            statisticsAvailable: statisticsAvailable, learningAvailable: learningAvailable,
            statisticsSince: statisticsAvailable ? snapshot.diagnostics.since : nil,
            savedAt: times.min(), savedTimeSource: source,
            notice: !snapshot.isPersistent ? .unreadable : stale ? .stale : nil)
        let d = snapshot.diagnostics
        func rows(_ counters: [Counter]) -> [CountRow] { counters.map { CountRow(id: $0, count: d[$0]) } }
        let decision = Partition(rows: rows(decisions), population: d[.boundaries])
        let automatic = automaticTotal(d)
        let methods = [(Counter.undoSpatial, d[.autoSpatialSameLength] + d[.autoSpatialEdit]),
                       (.undoSpelling, d[.autoSpellingFallback]), (.undoRule, d[.autoRule])]
            .map { MethodFeedback(id: $0.0, comparison: Comparison(d[$0.0], of: $0.1, allowed: decision.isConsistent)) }
        let statistics = statisticsAvailable ? Statistics(decisions: decision,
            evidence: Partition(rows: rows(evidenceCounters), population: d[.boundaries]),
            automatic: Comparison(automatic, of: d[.boundaries], allowed: decision.isConsistent),
            undo: Comparison(undoTotal(d), of: automatic, allowed: decision.isConsistent),
            methods: methods,
            refusalGroups: refusalMapping.map { RefusalGroup(id: $0.0, title: $0.1, rows: rows($0.2)) },
            choices: rows(choiceCounters), personalCompletionIsSubset: d[.personalCompletionPick] <= d[.manualCompletionPick],
            learningEvents: rows(learningCounters),
            acceptedBySource: TouchLabelSource.allCases.map { LabelCount(id: $0.rawValue, label: exampleSourceLabel($0), count: d.acceptedBySource[$0.rawValue, default: 0]) },
            rejectedByReason: TouchLabelRejection.allCases.map { LabelCount(id: $0.rawValue, label: exampleRejectionLabel($0), count: d.rejectedByReason[$0.rawValue, default: 0]) },
            storageEvents: rows(storageCounters), reattributedTaps: d[.reattributedTaps],
            wordCheckTime: latency(buckets: d.boundaryMs, referenceCount: d[.boundaries]),
            suggestionTime: latency(buckets: d.suggestionMs, referenceCount: d[.suggestionDecodes])) : nil
        let m = snapshot.model
        let layouts = m.layouts.sorted {
            $0.lastUpdated == $1.lastUpdated ? $0.signature.id < $1.signature.id : $0.lastUpdated > $1.lastUpdated
        }.map { Layout(summary: $0, title: layoutTitle($0.signature, locale: locale), keys: keyRows($0, locale: locale)) }
        let learning = learningAvailable ? Learning(keptWords: m.keptWords, countedWords: m.countedWords,
            storedPairs: m.storedPairs, rejectedCorrections: m.rejectedCorrections,
            wordCountTotal: m.wordCountTotal, pairByteBound: m.pairByteBound, layouts: layouts) : nil
        return Readout(scope: scope, learningEnabled: learningEnabled, statistics: statistics, learning: learning)
    }

    static func latency(buckets: [Int], referenceCount: Int) -> Latency {
        precondition(buckets.count == 7) // Guaranteed by the existing store decoder.
        let rows = buckets.enumerated().map { Bucket(id: $0.offset, count: $0.element) }
        let n = buckets.reduce(0, +)
        let rank = (n + 1) / 2
        var cumulative = 0
        let half = n == 0 ? nil : rows.first { cumulative += $0.count; return cumulative >= rank }
        return Latency(buckets: rows, referenceCount: referenceCount, halfBucket: half,
                       highestBucket: rows.last { $0.count > 0 })
    }

    static func integer(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }

    static func decimal(_ value: Double, locale: Locale = .current) -> String {
        let rounded = roundedHundredth(value)
        return rounded.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    static func roundedHundredth(_ value: Double) -> Double {
        let rounded = (value * 100).rounded() / 100
        return rounded == 0 ? 0 : rounded
    }

    static func offsetText(x: Double, y: Double, locale: Locale = .current) -> String {
        let x = roundedHundredth(x), y = roundedHundredth(y)
        let horizontal = "\(decimal(abs(x), locale: locale)) key spacings \(x < 0 ? "left" : "right")"
        let vertical = "\(decimal(abs(y), locale: locale))\(x == 0 ? " key spacings" : "") \(y < 0 ? "up" : "down")"
        if x == 0 && y == 0 { return "At the key centre" }
        if x == 0 { return vertical }
        if y == 0 { return horizontal }
        return "\(horizontal), \(vertical)"
    }

    static func layoutTitle(_ signature: KeyboardLayoutSignature, locale: Locale = .current) -> String {
        "\(signature.orientation == "landscape" ? "Landscape" : "Portrait"), \(integer(signature.widthBucket, locale: locale)) pt, \(signature.showsStrip ? "suggestion bar" : "no suggestion bar"), \(signature.showsGlobe ? "globe key" : "no globe key")"
    }

    static func keyRows(_ layout: PersonalTypingModel.LayoutSummary, locale: Locale = .current) -> [KeyRow] {
        "abcdefghijklmnopqrstuvwxyz".map { letter in
            let id = String(letter).uppercased()
            guard let key = layout.keys.first(where: { $0.letter == String(letter) }), key.n > 0 else {
                return KeyRow(id: id, n: 0, status: .none, offset: nil, halfLengths: nil, direction: nil)
            }
            let oval = KeyboardTouchGeometry.oval(for: key)
            let direction: String
            if roundedHundredth(oval.major) == roundedHundredth(oval.minor) {
                direction = "No distinct long-axis direction at this precision"
            } else {
                let angle = Int(oval.angleDegrees.rounded())
                direction = angle == 0 ? "Horizontal in key-spacing coordinates"
                    : "About \(integer(abs(angle), locale: locale)) degrees \(angle > 0 ? "clockwise" : "counterclockwise") from horizontal in key-spacing coordinates"
            }
            return KeyRow(id: id, n: key.n, status: key.n >= 20 ? .twentyOrMore : .few,
                offset: offsetText(x: key.offsetX, y: key.offsetY, locale: locale),
                halfLengths: "About \(decimal(oval.major, locale: locale)) and \(decimal(oval.minor, locale: locale)) key spacings",
                direction: direction)
        }
    }

    static func counterLabel(_ counter: Counter) -> String {
        switch counter {
        case .evidenceComplete: "Tap data available"
        case .evidenceMissing: "No tap data, or taps discarded"
        case .evidenceLengthOutOfRange: "Word length outside 3–32 characters"
        case .evidenceUnsupported: "Characters not supported (a–z only)"
        case .autoSpatialSameLength: "Same length"
        case .autoSpatialEdit: "Letter missing, extra or swapped"
        case .autoSpellingFallback: "Replaced by spelling check"
        case .autoRule: "Replaced by a rule or text replacement"
        case .refusedMissingResource: "Word data unavailable"
        case .undoSpatial: "Tap positions"
        case .undoSpelling: "Spelling check"
        case .undoRule: "Rules and text replacements"
        case .manualAlternativePick: "Picked an alternative"
        case .manualCompletionPick: "Picked a completion"
        case .personalCompletionPick: "Of these from your personal words"
        case .suggestionDecodes: "Recorded suggestion searches"
        case .wordsCounted: "Words counted for learning"
        case .wordsKept: "Words you kept"
        case .storeCorruptDiscarded: "Invalid saved data ignored"
        case .storeLoadDeferred: "Delayed learning loads"
        case .reattributedTaps: "Letter taps moved to a neighbouring key"
        case .boundaries: "Words checked"
        case .unchanged: "Left unchanged"
        case .refusedLiteralValid: "Typed word is valid"
        case .refusedProtected: "Protected word, rejected correction, capitals or identifier"
        case .refusedAmbiguous: "Alternatives too close to call"
        case .refusedIncompleteSearch: "Search limit reached"
        case .refusedValidation: "Dictionary did not confirm the replacement"
        case .refusedBelowMargin: "Not enough evidence to replace"
        case .resourceLoading: "Word data still loading"
        case .keepChip: "Kept as typed"
        case .correctionsRejected: "Corrections rejected"
        case .storeWriteFailed: "Save failures or repairs"
        }
    }

    static func exampleSourceLabel(_ source: TouchLabelSource) -> String {
        switch source {
        case .literalValid: "Word left as typed"
        case .keep: "Kept as typed"
        case .undo: "Undone replacement"
        case .manualPick: "Picked alternative"
        }
    }

    static func exampleRejectionLabel(_ reason: TouchLabelRejection) -> String {
        switch reason {
        case .outlier: "Tap too far from the assumed key"
        case .nonFinite: "Position could not be used"
        case .unknownKey: "Key not recognised"
        case .layoutMismatch: "Keyboard layout could not be used"
        case .ambiguousAlignment: "Taps could not be matched to letters"
        case .learningOff: "Learning was switched off"
        }
    }
}