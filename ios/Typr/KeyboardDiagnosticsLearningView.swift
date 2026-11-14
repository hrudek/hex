import SwiftUI

/// Content of the "Learning" detail page: preference, saved model, learning events,
/// tap examples, tap map and technical totals.
struct KeyboardDiagnosticsLearningView: View {
    @State private var selectedLayoutID: String?
    let readout: KeyboardDiagnosticsPresentation.Readout

    private typealias Presentation = KeyboardDiagnosticsPresentation

    /// `initialLayoutID` lets a snapshot scene start with a selection that no longer exists.
    init(readout: KeyboardDiagnosticsPresentation.Readout, initialLayoutID: String? = nil) {
        self.readout = readout
        _selectedLayoutID = State(initialValue: initialLayoutID)
    }

    var body: some View {
        status
        if let learning = readout.learning {
            savedNow(learning)
        }
        events
        if let learning = readout.learning {
            tapMap(learning)
            technicalTotals(learning)
        }
        DiagnosticsSection {
            DiagnosticsDestinationLink(title: DiagnosticsCopy.manageWords, destination: .keyboardLearnedWords)
        }
    }

    private var status: some View {
        DiagnosticsSection(title: "Status") {
            DiagnosticsValueRow(label: "Learn from my typing", value: readout.learningEnabled ? "On" : "Off")
            DiagnosticsNote(readout.learningExplanation)
            if readout.learning == nil {
                DiagnosticsUnavailable(area: .learning, scope: readout.scope)
            }
        }
    }

    private func savedNow(_ learning: Presentation.Learning) -> some View {
        DiagnosticsSection(title: "Saved now") {
            DiagnosticsNote("What the saved model holds. It can cover a different period than the events above. Older entries can be dropped.")
            DiagnosticsValueRow(label: "Words with a saved count", value: Presentation.integer(learning.countedWords))
            DiagnosticsValueRow(label: "Kept words", value: Presentation.integer(learning.keptWords))
            DiagnosticsValueRow(label: "Next-word links", value: Presentation.integer(learning.storedPairs))
            DiagnosticsValueRow(label: "Rejected corrections", value: Presentation.integer(learning.rejectedCorrections))
            DiagnosticsNote("Words with a saved count and kept words share a maximum of 2,000 different words. The sets can overlap; don't add them.")
            DiagnosticsNote("Next-word links: at most 512 in total, after one or two words.")
            DiagnosticsNote("Rejected corrections: at most 512 saved pairs.")
        }
    }

    private var events: some View {
        DiagnosticsSection(title: "Learning events") {
            if let statistics = readout.statistics {
                if let since = readout.scope.statisticsSince {
                    DiagnosticsNote(DiagnosticsCopy.period(since))
                }
                DiagnosticsNote(Presentation.learningEventsHelp)
                ForEach(statistics.learningEvents) { row in
                    DiagnosticsValueRow(label: row.label, value: Presentation.integer(row.count))
                }
                DiagnosticsDisclosure(title: "Tap examples") { tapExamples(statistics) }
            } else {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope)
            }
        }
    }

    private func tapExamples(_ statistics: Presentation.Statistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DiagnosticsNote("An example pairs one tap with one letter. Typr learns tap positions only from accepted examples.")
            DiagnosticsNote("Automatic replacements alone never teach tap positions, word counts or word contexts. Examples come from your typing and choices.")
            DiagnosticsValueRow(label: "Accepted", value: Presentation.integer(statistics.acceptedTotal))
            ForEach(statistics.acceptedBySource) { row in
                DiagnosticsValueRow(label: row.label, value: Presentation.integer(row.count), indent: true)
            }
            DiagnosticsNote("A word left as typed can also be one whose earlier correction you rejected. These are accepted tap examples, not counts of choices or different words.")
            DiagnosticsValueRow(label: "Rejected", value: Presentation.integer(statistics.rejectedTotal))
            ForEach(statistics.rejectedByReason) { row in
                DiagnosticsValueRow(label: row.label, value: Presentation.integer(row.count), indent: true)
            }
            DiagnosticsNote("Rejected examples are those Typr offered to the model and the model refused. Taps never offered aren't counted.")
        }
    }

    private func tapMap(_ learning: Presentation.Learning) -> some View {
        DiagnosticsSection(title: "Tap map") {
            if let layout = learning.selectedLayout(id: selectedLayoutID) {
                if learning.layouts.count > 1 {
                    Picker("Layout", selection: Binding(
                        get: { layout.id },
                        set: { selectedLayoutID = $0 })
                    ) {
                        ForEach(learning.layouts) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44, alignment: .leading)
                } else {
                    DiagnosticsSubheading(layout.title)
                }
                DiagnosticsNote("Typr keeps at most four layouts. The width is the saved layout bucket, not a measurement of this screen.")
                DiagnosticsNote(layout.coverageText())
                KeyboardTouchModelView(model: layout)
            } else {
                DiagnosticsNote("No saved tap map to show.")
            }
        }
    }

    private func technicalTotals(_ learning: Presentation.Learning) -> some View {
        DiagnosticsSection {
            DiagnosticsDisclosure(title: "Technical model totals") {
                DiagnosticsValueRow(label: "Sum of retained word counts", value: Presentation.integer(learning.wordCountTotal))
                DiagnosticsNote("Counts are capped at 10,000 per word and older entries can be dropped. This is not the number of words you have typed.")
                DiagnosticsValueRow(label: "Estimated upper bound for encoded next-word data",
                                    value: "\(Presentation.integer(learning.pairByteBound)) bytes")
                DiagnosticsNote("A conservative bound for the encoded data, not a measured file size or memory use.")
            }
        }
    }
}
