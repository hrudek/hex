import SwiftUI

/// Content of the "Word checks" detail page. The shell supplies the page, refresh and reset handling.
struct KeyboardDiagnosticsWordChecksView: View {
    let readout: KeyboardDiagnosticsPresentation.Readout

    private typealias Presentation = KeyboardDiagnosticsPresentation

    var body: some View {
        scope
        if let statistics = readout.statistics {
            decisions(statistics)
            afterReplacement(statistics)
            tapData(statistics)
            refusals(statistics)
            byMethod(statistics)
            otherChoices(statistics)
            letterTaps(statistics)
        }
    }

    private var scope: some View {
        DiagnosticsSection {
            if let since = readout.scope.statisticsSince {
                DiagnosticsNote(DiagnosticsCopy.period(since))
            }
            if let statistics = readout.statistics {
                let population = statistics.decisions.population
                if population > 0 {
                    DiagnosticsValueRow(label: "Words checked", value: Presentation.integer(population))
                    DiagnosticsNote("Based on \(Presentation.integer(population)) words checked.")
                } else {
                    DiagnosticsNote(DiagnosticsCopy.noWordChecks)
                }
            } else {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope)
            }
            DiagnosticsNote("A word is counted only when autocorrection is on, the text field allows it and a word is present.")
        }
    }

    @ViewBuilder private func decisions(_ statistics: Presentation.Statistics) -> some View {
        if statistics.decisions.population > 0 || statistics.decisions.sum > 0 {
            decisionsSection(statistics)
        }
    }

    private func decisionsSection(_ statistics: Presentation.Statistics) -> some View {
        let population = Presentation.integer(statistics.decisions.population)
        return DiagnosticsSection {
            DiagnosticsDecisions(
                partition: statistics.decisions,
                heading: statistics.decisions.population > 0
                    ? "What Typr did with each of \(population) words" : "Recorded decisions",
                scale: "Full bar = all \(population) words checked.")
            DiagnosticsComparisonRow(
                label: "Replaced automatically", comparison: statistics.automatic, unit: "words",
                numeratorLabel: "Automatic replacements", denominatorLabel: "Words checked",
                emptyText: DiagnosticsCopy.noWordChecks)
            DiagnosticsNote("Words Typr changed by itself, by any method.")
        }
    }

    private func afterReplacement(_ statistics: Presentation.Statistics) -> some View {
        DiagnosticsSection(title: "After an automatic replacement") {
            DiagnosticsUndoSummary(statistics: statistics)
        }
    }

    private func tapData(_ statistics: Presentation.Statistics) -> some View {
        let evidence = statistics.evidence
        return DiagnosticsSection(title: "Tap data") {
            if evidence.canShowParts, let available = evidence.rows.first(where: { $0.id == .evidenceComplete }) {
                DiagnosticsNote("Tap data was available for \(Presentation.integer(available.count)) of \(Presentation.integer(evidence.population)) words.")
            }
            ForEach(evidence.rows) { row in
                DiagnosticsTrackRow(label: row.label, count: row.count,
                                    population: evidence.canShowParts ? evidence.population : nil)
            }
            if let text = evidence.inconsistencyText() {
                DiagnosticsNote(text)
            }
            DiagnosticsNote("Tap data available doesn't mean the word was learned from or was correct.")
        }
    }

    private func refusals(_ statistics: Presentation.Statistics) -> some View {
        DiagnosticsSection(title: "Why a method declined to replace") {
            DiagnosticsNote("A word has at most one reason here. Not every unchanged word has one, and a later method may still have replaced the word. These counts are not additional words checked.")
            ForEach(statistics.refusalGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    DiagnosticsSubheading(group.title)
                    ForEach(group.rows) { row in
                        DiagnosticsValueRow(label: row.label, value: Presentation.integer(row.count))
                        if row.id == .refusedBelowMargin {
                            DiagnosticsNote(Presentation.belowMarginHelp)
                        }
                    }
                    if group.id == .wordData {
                        DiagnosticsNote("These counts record past checks. They don't show whether word data is available or loading now.")
                    }
                }
            }
        }
    }

    private func byMethod(_ statistics: Presentation.Statistics) -> some View {
        DiagnosticsSection(title: "By method") {
            DiagnosticsNote("Tap-position undos combine same-length and letter-edit replacements.")
            ForEach(statistics.methods) { method in
                DiagnosticsMethodFeedback(method: method)
            }
        }
    }

    private func otherChoices(_ statistics: Presentation.Statistics) -> some View {
        DiagnosticsSection(title: "Your other choices") {
            ForEach(statistics.choices) { row in
                DiagnosticsValueRow(label: row.label, value: Presentation.integer(row.count),
                                    indent: row.id == .personalCompletionPick)
            }
            if statistics.personalCompletionIsSubset {
                DiagnosticsNote("Personal completions are included in completions above. Don't add them.")
            } else {
                DiagnosticsNote("The personal-completion count is larger than the completion count. Both saved counts are shown.")
            }
            DiagnosticsNote("These count choices, not accepted tap examples. One choice can supply several examples or none.")
        }
    }

    private func letterTaps(_ statistics: Presentation.Statistics) -> some View {
        DiagnosticsSection(title: "Letter taps") {
            DiagnosticsValueRow(label: Presentation.counterLabel(.reattributedTaps),
                                value: Presentation.integer(statistics.reattributedTaps))
            DiagnosticsNote("Typr assigned these taps to a different key than the one touched, using its tap model and the letters typed so far. This is counted only with learning and autocorrection on. It counts taps, not words, and isn't a measure of accuracy.")
        }
    }
}
