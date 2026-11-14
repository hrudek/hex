import SwiftUI
import Charts

struct ActivityStatisticsView: View {
    let snapshot: UsageStatisticsSnapshot
    let section: StatisticsSection
    let now: Date
    @Binding var range: StatisticsRange
    @Binding var metric: ActivityMetric

    private var activity: ActivityStatistics { ActivityStatistics(snapshot: snapshot, range: range, now: now) }
    private var kinds: [ActivityKind] {
        switch section {
        case .typing: [.typing]
        case .dictation: [.dictation]
        default: ActivityKind.allCases
        }
    }

    var body: some View {
        let activity = activity
        VStack(alignment: .leading, spacing: 20) {
            if section == .overview { today(activity) }
            Picker("Statistics period", selection: $range) {
                ForEach(StatisticsRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(kinds, id: \.self) { kind in summary(kind, activity: activity) }
            history(activity)
            card {
                DisclosureGroup("About this data") {
                Text("Collected since \(snapshot.startedAt, format: .dateTime.year().month(.abbreviated).day()) · \(snapshot.timeZone)")
                Text("Up to 90 calendar days. Days before collection are unavailable; blank speed values need at least 60 matching seconds.")
                Text("Word completions, five-character standard words and recognized dictation words are different measures. Speeds use summed counts and matching times, not averages of daily speeds.")
                Text("An active typing day has recorded input, deletion or suggestion activity; an active dictation day has a successful capture, including zero-word results.")
                Text("Only recorded activity is shown. Pending keyboard updates may be lost if the extension is terminated.")
                }
            }
            .font(.caption).foregroundStyle(TyprTheme.textMuted)
        }
        .environment(\.calendar, snapshot.calendar)
        .environment(\.timeZone, snapshot.calendar.timeZone)
    }

    private func today(_ activity: ActivityStatistics) -> some View {
        card {
            Text("Today").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(ActivityKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.today.map { kind.words($0).formatted() } ?? "—")
                        .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("\(kind.rawValue) · \(kind.wordLabel)").foregroundStyle(color(kind))
                    Text(activity.today.map { "\(ActivityStatistics.duration(kind.seconds($0))) \(kind == .typing ? "active typing" : "successful recording")" } ?? "Before collection")
                        .font(.caption).foregroundStyle(TyprTheme.textMuted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func summary(_ kind: ActivityKind, activity: ActivityStatistics) -> some View {
        card {
            Text("\(kind.rawValue) · last \(range.rawValue) days").font(.headline).accessibilityAddTraits(.isHeader)
            Text(ActivityStatistics.speedText(kind.speed(activity.totals)))
                .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(kind.speedLabel).foregroundStyle(color(kind))
            Text(kind == .typing
                 ? "Timed direct characters ÷ 5 per active minute; pauses over four seconds excluded."
                 : "Raw recognized words per successful recording minute, before cleanup.")
                .font(.caption).foregroundStyle(TyprTheme.textMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 16) {
                figure(activity.collectedDays > 0 ? kind.words(activity.totals).formatted() : "—", kind.wordLabel)
                figure(activity.collectedDays > 0 ? ActivityStatistics.duration(kind.seconds(activity.totals)) : "—", kind == .typing ? "active typing" : "successful recording")
                figure(activity.collectedDays > 0 ? "\(activity.activeDays(kind))" : "—", "active days")
                figure(activity.averageWords(kind).map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", "words / active day")
                if kind == .dictation { figure(activity.collectedDays > 0 ? activity.totals.dictations.formatted() : "—", "successful dictations") }
            }
            if activity.collectedDays == 0 {
                Text("This period is before collection began.").font(.subheadline).foregroundStyle(TyprTheme.textMuted)
            } else if activity.activeDays(kind) == 0 {
                Text(kind == .typing ? "No recorded typing in this period. Use the Typr keyboard with Full Access to collect activity."
                     : "No successful dictations recorded in this period.")
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
            }
        }
    }

    private func history(_ activity: ActivityStatistics) -> some View {
        card {
            Text("Daily history").font(.headline).accessibilityAddTraits(.isHeader)
            Picker("History measure", selection: $metric) {
                ForEach(ActivityMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart {
                ForEach(activity.days) { day in
                    ForEach(kinds, id: \.self) { kind in
                        if let totals = day.totals {
                            if metric == .words {
                                BarMark(x: .value("Day", day.date, unit: .day),
                                        y: .value("Words", Double(kind.words(totals))))
                                    .foregroundStyle(by: .value("Population", kind.rawValue))
                                    .position(by: .value("Population", kind.rawValue))
                            } else if let speed = kind.speed(totals) {
                                PointMark(x: .value("Day", day.date), y: .value("Words per minute", speed))
                                    .foregroundStyle(by: .value("Population", kind.rawValue))
                                    .symbol(by: .value("Population", kind.rawValue))
                            }
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: kinds.map(\.rawValue), range: kinds.map { color($0) })
            .chartXScale(domain: chartDomain(activity))
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 200)
            .accessibilityLabel("Daily \(metric.rawValue.lowercased()) history. Exact values in daily values below.")
            Text(metric == .words ? "Typing: word completions. Dictation: raw recognized words."
                 : "Typing: five-character standard words/min. Dictation: recognized words/min. No combined speed.")
                .font(.caption).foregroundStyle(TyprTheme.textMuted)
            Text("\(activity.collectedDays) of \(range.rawValue) days in collection. Missing speed points are unavailable, not zero.")
                .font(.caption).foregroundStyle(TyprTheme.textMuted)
            DisclosureGroup("Daily values") {
                ForEach(activity.days.reversed()) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.date, format: .dateTime.month(.abbreviated).day()).font(.subheadline.weight(.semibold))
                        ForEach(kinds, id: \.self) { kind in
                            Text(dailyText(day, kind: kind)).font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func dailyText(_ day: ActivityStatistics.Day, kind: ActivityKind) -> String {
        guard let totals = day.totals else { return "\(kind.rawValue): before collection" }
        if metric == .words { return "\(kind.rawValue): \(kind.words(totals)) \(kind.wordLabel)" }
        return "\(kind.rawValue): \(ActivityStatistics.speedText(kind.speed(totals))) \(kind.speedLabel)"
    }
    private func chartDomain(_ activity: ActivityStatistics) -> ClosedRange<Date> {
        let first = activity.days.first?.date ?? now
        let last = activity.days.last?.date ?? now
        let end = activity.calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return first...end
    }
    private func color(_ kind: ActivityKind) -> Color { kind == .typing ? TyprTheme.agentBlue : TyprTheme.warmMic }
    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(TyprTheme.textMuted)
        }.accessibilityElement(children: .combine)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(TyprTheme.bgBase, in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius))
    }
}
