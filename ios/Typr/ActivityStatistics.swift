import Foundation

nonisolated enum StatisticsSection: String, CaseIterable {
    case overview = "Overview", typing = "Typing", dictation = "Dictation", taps = "Taps"
}

nonisolated enum StatisticsRange: Int, CaseIterable {
    case week = 7, month = 30, quarter = 90
    var title: String { "\(rawValue)D" }
}

nonisolated enum ActivityMetric: String, CaseIterable {
    case words = "Words", speed = "Speed"
}

nonisolated enum ActivityKind: String, CaseIterable {
    case typing = "Typing", dictation = "Dictation"

    func words(_ totals: UsageTotals) -> UInt64 {
        self == .typing ? totals.completedWords : totals.dictatedWords
    }
    func seconds(_ totals: UsageTotals) -> Double {
        self == .typing ? totals.typingSeconds : totals.recordingSeconds
    }
    func speed(_ totals: UsageTotals) -> Double? {
        self == .typing ? totals.typingWPM : totals.dictationWPM
    }
    func isActive(_ totals: UsageTotals) -> Bool {
        if self == .dictation { return totals.dictations > 0 }
        return totals.directGraphemes > 0 || totals.deletions > 0 || totals.suggestions > 0
            || totals.completedWords > 0 || totals.typingSeconds > 0
    }
    var wordLabel: String { self == .typing ? "word completions" : "recognized words" }
    var speedLabel: String { self == .typing ? "standard words/min" : "recognized words/min" }
}

/// A calendar-day presentation, not reconstructed history. Nil totals precede collection.
nonisolated struct ActivityStatistics {
    struct Day: Identifiable {
        let id: String
        let date: Date
        let totals: UsageTotals?
    }
    let days: [Day]
    let totals: UsageTotals
    let today: UsageTotals?
    let calendar: Calendar

    init(snapshot: UsageStatisticsSnapshot, range: StatisticsRange, now: Date) {
        calendar = snapshot.calendar
        let end = snapshot.calendar.startOfDay(for: now)
        let start = snapshot.calendar.startOfDay(for: snapshot.startedAt)
        let stored = Dictionary(uniqueKeysWithValues: snapshot.days.map { ($0.id, $0.totals) })
        days = (0..<range.rawValue).reversed().compactMap { offset in
            guard let date = snapshot.calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let id = snapshot.dayID(date)
            return Day(id: id, date: date, totals: date < start ? nil : (stored[id] ?? UsageTotals()))
        }
        totals = days.compactMap(\.totals).reduce(into: UsageTotals()) { $0.add($1) }
        today = days.last?.totals
    }

    var collectedDays: Int { days.filter { $0.totals != nil }.count }
    func activeDays(_ kind: ActivityKind) -> Int {
        days.compactMap(\.totals).filter { kind.isActive($0) }.count
    }
    func averageWords(_ kind: ActivityKind) -> Double? {
        let count = activeDays(kind)
        return count > 0 ? Double(kind.words(totals)) / Double(count) : nil
    }
    static func speedText(_ speed: Double?) -> String {
        speed.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"
    }
    static func duration(_ seconds: Double) -> String {
        let seconds = Int(seconds.rounded(.down))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}
