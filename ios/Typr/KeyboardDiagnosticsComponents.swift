import SwiftUI

/// Building blocks shared by the typing diagnostics pages. Only pieces that more than one page
/// uses live here. Numbers, comparisons and bucket data always come from the presentation layer.
typealias DiagnosticsReadout = KeyboardDiagnosticsPresentation.Readout

private typealias Presentation = KeyboardDiagnosticsPresentation

/// Approved wording used on more than one page (plan section 5).
enum DiagnosticsCopy {
    static let requirement = "Typr saves these counts only when you use the full keyboard with Full Access on. This page can't check whether that's the case."
    static let noData = "No saved typing data available."
    static let noStatistics = "No saved statistics available."
    static let noLearning = "No saved learning data available."
    static let noWordChecks = "No word checks recorded in the available statistics."
    static let noAutomatic = "No automatic replacements recorded in the available statistics."
    static let noMeasurements = "No measurements recorded in the available statistics."
    static let notComparable = "These saved counts can't be compared as parts of one total."
    static let undoHelp = "This counts immediate undos after automatic replacements, not accuracy. Fixing a word by hand isn't counted, and a replacement that wasn't undone wasn't necessarily wanted."
    static let manageWords = "Manage learned words"

    enum Area { case statistics, learning }

    /// Nil when the requested area has data. Both areas missing share one text.
    static func unavailableText(_ area: Area, scope: KeyboardDiagnosticsPresentation.Scope) -> String? {
        if !scope.statisticsAvailable && !scope.learningAvailable { return noData }
        switch area {
        case .statistics: return scope.statisticsAvailable ? nil : noStatistics
        case .learning: return scope.learningAvailable ? nil : noLearning
        }
    }

    static func period(_ date: Date) -> String {
        "Available statistics period starts \(date.formatted(date: .abbreviated, time: .shortened))."
    }

    static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// A titled card. Pages place all content of one topic inside a single section.
struct DiagnosticsSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        SettingsSection(title: title) {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .foregroundStyle(TyprTheme.textBase)
        .tint(TyprTheme.success)
    }
}

/// Sub-heading inside a card; VoiceOver treats it as a heading.
struct DiagnosticsSubheading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TyprTheme.textBase)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Explanatory text. Increase Contrast raises the text to the primary ink.
struct DiagnosticsNote: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(contrast == .increased ? TyprTheme.textBase : TyprTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label and value in one VoiceOver element: `<label>, <value>`. Stacks vertically at accessibility sizes.
struct DiagnosticsValueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let label: String
    let value: String
    var indent = false

    var body: some View {
        rowContent
            .font(.subheadline)
            .padding(.leading, indent ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label), \(value)")
    }

    @ViewBuilder private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                labelText
                valueText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                labelText
                Spacer(minLength: 0)
                valueText.multilineTextAlignment(.trailing)
            }
        }
    }

    private var labelText: some View {
        Text(label).foregroundStyle(TyprTheme.textBase).fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value).monospacedDigit()
            .foregroundStyle(contrast == .increased ? TyprTheme.textBase : TyprTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Value row with a proportional track. The track is decoration; the number carries the meaning.
/// Pass `population` only when the presentation layer allows showing parts of one total.
struct DiagnosticsTrackRow: View {
    let label: String
    let count: Int
    var population: Int? = nil
    var indent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DiagnosticsValueRow(label: label, value: Presentation.integer(count), indent: indent)
            if let population, population > 0 {
                let fraction = min(1, max(0, Double(count) / Double(population)))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TyprTheme.layer02)
                        Capsule().fill(TyprTheme.agentBlue)
                            .frame(width: geometry.size.width * CGFloat(fraction))
                    }
                }
                .frame(height: 6)
                .padding(.leading, indent ? 16 : 0)
                .accessibilityHidden(true)
            }
        }
    }
}

/// The five recorded decisions with the tap-position group. Used on the overview and in detail.
/// Tracks appear only when the parts add up to the population (`canShowParts`).
struct DiagnosticsDecisions: View {
    let partition: KeyboardDiagnosticsPresentation.Partition
    let heading: String
    /// Scale sentence shown only when the parts add up to the population.
    let scale: String

    var body: some View {
        if partition.population == 0 && partition.sum == 0 {
            DiagnosticsNote(DiagnosticsCopy.noWordChecks)
        } else {
            let population: Int? = partition.canShowParts ? partition.population : nil
            let spatial = partition.rows.filter { $0.id == .autoSpatialSameLength || $0.id == .autoSpatialEdit }
            let others = partition.rows.filter { $0.id != .autoSpatialSameLength && $0.id != .autoSpatialEdit }
            VStack(alignment: .leading, spacing: 12) {
                DiagnosticsSubheading(heading)
                DiagnosticsSubheading("Replaced using tap positions")
                DiagnosticsNote("Typr compares where you tapped with the key positions to find a likely word.")
                ForEach(spatial) { row in
                    DiagnosticsTrackRow(label: row.label, count: row.count, population: population, indent: true)
                }
                ForEach(others) { row in
                    DiagnosticsTrackRow(label: row.label, count: row.count, population: population)
                }
                if partition.canShowParts {
                    DiagnosticsNote(scale)
                } else if let text = partition.inconsistencyText() {
                    DiagnosticsNote(text)
                }
            }
        }
    }
}

/// `<x> of <y> <unit>` when the saved counts can be compared; absolute counts or the empty text otherwise.
struct DiagnosticsComparisonRow: View {
    let label: String
    let comparison: KeyboardDiagnosticsPresentation.Comparison
    let unit: String
    /// Label for the compared count when it is shown on its own.
    let numeratorLabel: String
    /// Label for the base count when it is shown on its own; nil when the base is shown elsewhere.
    var denominatorLabel: String? = nil
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch comparison.status {
            case .comparable:
                DiagnosticsValueRow(
                    label: label,
                    value: "\(Presentation.integer(comparison.numerator)) of \(Presentation.integer(comparison.denominator)) \(unit)")
            case .empty:
                DiagnosticsValueRow(label: label, value: Presentation.integer(comparison.numerator))
                DiagnosticsNote(emptyText)
            case .incomparable:
                if let denominatorLabel {
                    DiagnosticsValueRow(label: denominatorLabel, value: Presentation.integer(comparison.denominator))
                }
                DiagnosticsValueRow(label: numeratorLabel, value: Presentation.integer(comparison.numerator))
                DiagnosticsNote(DiagnosticsCopy.notComparable)
            }
        }
    }
}

/// Undone count with its explanation. Used on the overview and in Word checks.
struct DiagnosticsUndoSummary: View {
    let statistics: KeyboardDiagnosticsPresentation.Statistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiagnosticsComparisonRow(
                label: "Undone", comparison: statistics.undo, unit: "replacements",
                numeratorLabel: "Recorded undos", denominatorLabel: "Automatic replacements",
                emptyText: DiagnosticsCopy.noAutomatic)
            DiagnosticsNote(DiagnosticsCopy.undoHelp)
        }
    }
}

/// Empty-state text for an area without saved data, plus the requirement when nothing is saved at all.
struct DiagnosticsUnavailable: View {
    let area: DiagnosticsCopy.Area
    let scope: KeyboardDiagnosticsPresentation.Scope
    /// The overview states the requirement once in its header; detail pages state it here.
    var showsRequirement = true

    var body: some View {
        if let text = DiagnosticsCopy.unavailableText(area, scope: scope) {
            VStack(alignment: .leading, spacing: 8) {
                DiagnosticsNote(text)
                if showsRequirement && !scope.statisticsAvailable && !scope.learningAvailable {
                    DiagnosticsNote(DiagnosticsCopy.requirement)
                }
            }
        }
    }
}

/// Quiet disclosure. Content stays hidden until opened, except where an accessibility-size
/// text alternative must be open (`openAtAccessibilitySizes`) or the caller asks for it.
struct DiagnosticsDisclosure<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var userExpanded: Bool?
    let title: String
    var openAtAccessibilitySizes = false
    var startsOpen = false
    @ViewBuilder var content: Content

    private var expanded: Binding<Bool> {
        Binding(
            get: { userExpanded ?? (startsOpen || (openAtAccessibilitySizes && dynamicTypeSize.isAccessibilitySize)) },
            set: { userExpanded = $0 })
    }

    var body: some View {
        DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .disclosureGroupStyle(SettingsDisclosureStyle())
    }
}

/// Plain navigation row with a visible label that Voice Control and VoiceOver can use as is.
struct DiagnosticsLinkRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.body).foregroundStyle(TyprTheme.textBase)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TyprTheme.textFaint)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// One row of a two-column text table.
struct DiagnosticsTableRow: Identifiable {
    let id: String
    let first: String
    let second: String
    let accessibilityLabel: String
}

/// Two-column table (for example duration class and measurements). Column titles stay visible;
/// at accessibility sizes each row stacks and names the second column inline.
struct DiagnosticsTable: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Heading above the table; nil when a disclosure or section heading already names it.
    let title: String?
    let firstColumn: String
    let secondColumn: String
    let rows: [DiagnosticsTableRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { DiagnosticsSubheading(title) }
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(firstColumn)
                    Spacer(minLength: 0)
                    Text(secondColumn).multilineTextAlignment(.trailing)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(TyprTheme.textMuted)
                .accessibilityHidden(true)
            }
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    @ViewBuilder private func rowView(_ row: DiagnosticsTableRow) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.first).foregroundStyle(TyprTheme.textBase)
                    Text("\(secondColumn): \(row.second)").foregroundStyle(TyprTheme.textMuted).monospacedDigit()
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.first).foregroundStyle(TyprTheme.textBase)
                    Spacer(minLength: 0)
                    Text(row.second).foregroundStyle(TyprTheme.textMuted).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// Latency class table: seven rows in stored order, the class behind the half-of-measurements
/// summary carries an extra spoken note.
struct DiagnosticsLatencyTable: View {
    let latency: KeyboardDiagnosticsPresentation.Latency

    var body: some View {
        DiagnosticsTable(
            title: nil, firstColumn: "Duration class", secondColumn: "Measurements",
            rows: latency.buckets.map { bucket in
                let count = Presentation.integer(bucket.count)
                let marked = bucket.id == latency.halfBucket?.id
                return DiagnosticsTableRow(
                    id: String(bucket.id), first: bucket.label, second: count,
                    accessibilityLabel: "\(bucket.label), \(count) measurements"
                        + (marked ? ". Class used for the half-of-measurements summary." : ""))
            })
    }
}

/// Group heading with the half-of-measurements sentence and its own measurement count.
struct DiagnosticsLatencySummary: View {
    let title: String
    let latency: KeyboardDiagnosticsPresentation.Latency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticsSubheading(title)
            Text(latency.halfText())
                .font(.subheadline)
                .foregroundStyle(TyprTheme.textBase)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if latency.n > 0 {
                DiagnosticsNote("Based on \(Presentation.integer(latency.n)) measurements.")
            }
        }
    }
}

/// Link row to a settings destination. The visible title is the accessibility label.
struct DiagnosticsDestinationLink: View {
    let title: String
    let destination: SettingsDestination

    var body: some View {
        NavigationLink(value: destination) {
            DiagnosticsLinkRow(title: title)
        }
        .buttonStyle(.plain)
    }
}
