import SwiftUI

/// Page shell for the typing diagnostics overview and its three detail pages.
/// Every visible page owns a read adapter, so it refreshes on appear, pull-to-refresh and scene activation.
@MainActor
struct KeyboardDiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: KeyboardDiagnosticsModel
    @State private var confirmLearningReset = false
    @State private var confirmStatisticsReset = false
    private let page: KeyboardDiagnosticsPage
    private let context: KeyboardDiagnosticsFixture.Context?
    private typealias Presentation = KeyboardDiagnosticsPresentation

    /// `context` is set only by snapshot scenes; the model then stays entirely in memory.
    init(page: KeyboardDiagnosticsPage = .overview, context: KeyboardDiagnosticsFixture.Context? = nil) {
        self.page = page
        self.context = context
        _model = State(initialValue: context.map {
            KeyboardDiagnosticsModel(fixture: $0.snapshot, learningEnabled: $0.learningEnabled)
        } ?? KeyboardDiagnosticsModel())
    }

    private var now: Date { context?.now ?? Date() }
    private var readout: Presentation.Readout {
        Presentation.make(snapshot: model.snapshot, learningEnabled: model.learningEnabled, now: now)
    }

    private var title: String {
        switch page {
        case .overview: "Typing diagnostics"
        case .wordChecks: "Word checks"
        case .speed: "Speed"
        case .learning: "Learning"
        }
    }

    var body: some View {
        SettingsPage(title: title, subtitle: "") {
            switch page {
            case .overview:
                overview(readout)
            case .wordChecks:
                detailNotice(readout)
                KeyboardDiagnosticsWordChecksView(readout: readout)
            case .speed:
                detailNotice(readout)
                KeyboardDiagnosticsSpeedView(readout: readout)
            case .learning:
                detailNotice(readout)
                KeyboardDiagnosticsLearningView(readout: readout, initialLayoutID: context?.removedLayoutID)
            }
        }
        .refreshable { @MainActor in model.refresh() }
        .onAppear { model.startObserving() }
        .onDisappear { model.stopObserving() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .confirmationDialog("Reset learning?", isPresented: $confirmLearningReset, titleVisibility: .visible) {
            Button("Reset learning", role: .destructive) { model.resetLearning() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes touch calibration, kept words, word counts, next-word contexts, rejected corrections and imported personal words. Turns off contacts and dictation imports without deleting their sources. Statistics stay. The keyboard clears its matching learning before its next save and reloads imports on its next appearance.")
        }
        .confirmationDialog("Reset statistics?", isPresented: $confirmStatisticsReset, titleVisibility: .visible) {
            Button("Reset statistics", role: .destructive) { model.resetStatistics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes counters and speed histograms and starts a new counting period. Learning stays.")
        }
    }

    // MARK: Overview

    @ViewBuilder private func overview(_ readout: Presentation.Readout) -> some View {
        header(readout)
        atAGlance(readout)
        wordChecks(readout)
        afterReplacement(readout)
        learning(readout)
        speed(readout)
        savedData(readout)
    }

    /// Scope: intro, available period, one last-saved line, at most one notice, reading help.
    private func header(_ readout: Presentation.Readout) -> some View {
        let scope = readout.scope
        return DiagnosticsSection {
            DiagnosticsNote("Counts of what the Typr keyboard did and what you did next, collected on this iPhone. They show what happened, not whether a correction was right.")
            if let since = scope.statisticsSince {
                DiagnosticsNote(DiagnosticsCopy.period(since))
            }
            Text(lastSaved(scope))
                .font(.subheadline)
                .foregroundStyle(TyprTheme.textBase)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let notice = scope.notice {
                noticeView(notice)
            }
            if !scope.statisticsAvailable && !scope.learningAvailable {
                DiagnosticsNote(DiagnosticsCopy.noData)
                DiagnosticsNote(DiagnosticsCopy.requirement)
            }
            DiagnosticsDisclosure(title: "How to read this page") { howToRead }
        }
    }

    /// Detail pages repeat only the single warning or information notice.
    @ViewBuilder private func detailNotice(_ readout: Presentation.Readout) -> some View {
        if let notice = readout.scope.notice {
            DiagnosticsSection { noticeView(notice) }
        }
    }

    private func lastSaved(_ scope: Presentation.Scope) -> String {
        guard let savedAt = scope.savedAt else { return "No saved file information available" }
        let relative = DiagnosticsCopy.relative(savedAt, now: now)
        switch scope.savedTimeSource {
        case .both: return "Last saved \(relative)"
        case .statisticsOnly: return "Last saved \(relative) (statistics only)"
        case .learningOnly: return "Last saved \(relative) (learning data only)"
        case .none: return "No saved file information available"
        }
    }

    /// Unreadable data is a warning; a stale file is neutral information. Both say what they mean in text.
    @ViewBuilder private func noticeView(_ notice: Presentation.Scope.Notice) -> some View {
        switch notice {
        case .unreadable:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(TyprTheme.warmMic)
                    .accessibilityHidden(true)
                Text(notice.text)
                    .font(.subheadline)
                    .foregroundStyle(TyprTheme.textBase)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .stale:
            DiagnosticsNote(notice.text)
        }
    }

    @ViewBuilder private var howToRead: some View {
        DiagnosticsNote("A count shows how often something was recorded. 0 means none was recorded, not that everything works or that nothing happened.")
        DiagnosticsNote("Counts cover the available statistics period shown here. Saved learning data can cover a different period. A 0 can also mean the counter didn't exist yet when the statistics period began. Counters added in a later Typr version count only from that update, so they can cover a shorter period than shown here. Small counts can change a lot with a few more events.")
        DiagnosticsNote("Typr can't tell whether an automatic replacement was right. It only sees some actions afterwards, such as an immediate undo.")
        DiagnosticsNote("This page shows only what the keyboard has saved. It can't show anything the keyboard hasn't saved yet, and it can't tell whether Full Access is on right now.")
        DiagnosticsNote("File information and a successful read do not confirm that every saved file was usable. The available statistics period may come from an empty replacement for missing or unusable data, not from a reset.")
        DiagnosticsNote(DiagnosticsCopy.requirement)
    }

    private func atAGlance(_ readout: Presentation.Readout) -> some View {
        DiagnosticsSection(title: "At a glance") {
            if let statistics = readout.statistics {
                let population = statistics.decisions.population
                DiagnosticsValueRow(label: "Words checked", value: Presentation.integer(population))
                DiagnosticsNote("Words Typr checked for autocorrection at a word boundary. Not every word you typed.")
                if population == 0 {
                    DiagnosticsNote(DiagnosticsCopy.noWordChecks)
                } else {
                    DiagnosticsComparisonRow(
                        label: "Replaced automatically", comparison: statistics.automatic, unit: "words",
                        numeratorLabel: "Automatic replacements", emptyText: DiagnosticsCopy.noWordChecks)
                    DiagnosticsNote("Words Typr changed by itself, by any method.")
                }
            } else {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope, showsRequirement: false)
            }
        }
    }

    private func wordChecks(_ readout: Presentation.Readout) -> some View {
        DiagnosticsSection(title: "Word checks") {
            if let statistics = readout.statistics {
                if statistics.decisions.population > 0 {
                    DiagnosticsDecisions(partition: statistics.decisions, heading: "Recorded decisions",
                                         scale: "Full bar = all words checked.")
                }
                DiagnosticsDestinationLink(title: "Word checks in detail", destination: .keyboardDiagnosticsWordChecks)
            } else {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope, showsRequirement: false)
            }
        }
    }

    private func afterReplacement(_ readout: Presentation.Readout) -> some View {
        DiagnosticsSection(title: "After an automatic replacement") {
            if let statistics = readout.statistics {
                DiagnosticsUndoSummary(statistics: statistics)
            } else {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope, showsRequirement: false)
            }
        }
    }

    private func learning(_ readout: Presentation.Readout) -> some View {
        DiagnosticsSection(title: "Learning") {
            DiagnosticsValueRow(label: "Learn from my typing", value: readout.learningEnabled ? "On" : "Off")
            DiagnosticsNote(readout.learningExplanation)
            if let learning = readout.learning {
                DiagnosticsSubheading("Saved now")
                DiagnosticsNote("A limited set of saved entries, not lifetime totals.")
                DiagnosticsValueRow(label: "Words with a saved count", value: Presentation.integer(learning.countedWords))
                DiagnosticsValueRow(label: "Kept words", value: Presentation.integer(learning.keptWords))
                DiagnosticsValueRow(label: "Next-word links", value: Presentation.integer(learning.storedPairs))
                DiagnosticsValueRow(label: "Rejected corrections", value: Presentation.integer(learning.rejectedCorrections))
                if let layout = learning.selectedLayout(id: nil) {
                    DiagnosticsNote(layout.coverageText())
                } else {
                    DiagnosticsNote("No saved tap map to show.")
                }
            } else {
                DiagnosticsUnavailable(area: .learning, scope: readout.scope, showsRequirement: false)
            }
            DiagnosticsDestinationLink(title: "Learning in detail", destination: .keyboardDiagnosticsLearning)
        }
    }

    private func speed(_ readout: Presentation.Readout) -> some View {
        DiagnosticsSection(title: "Speed") {
            if let statistics = readout.statistics {
                DiagnosticsNote("Measured inside the keyboard on this iPhone. This is not typing speed.")
                DiagnosticsLatencySummary(title: "Word check time", latency: statistics.wordCheckTime)
                DiagnosticsLatencySummary(title: "Suggestion search time", latency: statistics.suggestionTime)
                DiagnosticsDestinationLink(title: "Speed in detail", destination: .keyboardDiagnosticsSpeed)
            } else {
                DiagnosticsUnavailable(area: .statistics, scope: readout.scope, showsRequirement: false)
            }
        }
    }

    // MARK: Saved data and reset

    private func savedData(_ readout: Presentation.Readout) -> some View {
        DiagnosticsSection(title: "Saved data and reset") {
            DiagnosticsNote("Typr stores aggregated counters, per-key tap statistics, kept words, word counts, next-word contexts and rejected corrections. Contexts after one or two words, including accepted suggestions, can reveal short phrases. No sentence archive, apps, websites or raw taps are stored.")
            DiagnosticsNote("Kept words, word counts, next-word contexts and rejected word pairs are personal data. They stay on this iPhone and are excluded from backup.")
            DiagnosticsNote("Optional contacts and dictation imports use a separate bounded word list. Manage those sources in Personal names and terms. Reset learning deletes that list and turns off both imports without deleting their sources.")
            // The separate word list has its own synthetic content in snapshot scenes.
            DiagnosticsDestinationLink(title: DiagnosticsCopy.manageWords, destination: .keyboardLearnedWords)
            fileRow("Learning file", readout.scope.learningFile)
            fileRow("Statistics file", readout.scope.statisticsFile)
            DiagnosticsNote("Location: Typr's shared app group on this iPhone.")
            DiagnosticsDisclosure(title: "Saving and loading") { saving(readout) }
            if let problem = model.resetProblem {
                Text(problem)
                    .font(.subheadline)
                    .foregroundStyle(TyprTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Reset learning", role: .destructive) { confirmLearningReset = true }
                .frame(minHeight: 44, alignment: .leading)
            Button("Reset statistics", role: .destructive) { confirmStatisticsReset = true }
                .frame(minHeight: 44, alignment: .leading)
        }
    }

    private func fileRow(_ label: String, _ file: Presentation.File) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DiagnosticsValueRow(label: label, value: file.sizeText())
            DiagnosticsNote(file.modifiedAt.map { "Saved \(DiagnosticsCopy.relative($0, now: now))" }
                ?? "No saved file information available")
        }
    }

    @ViewBuilder private func saving(_ readout: Presentation.Readout) -> some View {
        if let statistics = readout.statistics {
            ForEach(statistics.storageEvents) { row in
                DiagnosticsValueRow(label: row.label, value: Presentation.integer(row.count))
            }
            if let text = statistics.historicalStorageText() {
                DiagnosticsNote(text)
            }
            DiagnosticsNote("These are recorded events, not a current storage check or a count of distinct files. The same data can be counted more than once. These counters can only be saved when saving works. 0 doesn't prove saving is fine.")
        } else {
            DiagnosticsUnavailable(area: .statistics, scope: readout.scope, showsRequirement: false)
        }
    }
}
