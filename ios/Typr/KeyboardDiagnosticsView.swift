import SwiftUI

@MainActor
struct KeyboardDiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: KeyboardDiagnosticsModel
    @State private var selectedLayout = ""
    @State private var confirmLearningReset = false
    @State private var confirmStatisticsReset = false
    private let fixture: Bool
    private var snapshot: KeyboardLearningSnapshot { model.snapshot }
    private var diagnostics: KeyboardDiagnostics { snapshot.diagnostics }
    private typealias Presentation = KeyboardDiagnosticsPresentation

    init() {
        let fixture = KeyboardDiagnosticsFixture.isRequested
        self.fixture = fixture
        _model = State(initialValue: fixture
            ? KeyboardDiagnosticsModel(fixture: KeyboardDiagnosticsFixture.snapshot())
            : KeyboardDiagnosticsModel())
    }

    var body: some View {
        SettingsPage(title: "Typing diagnostics", subtitle: "") {
            status
            overview
            decisions
            feedback
            speed
            learning
            storage
        }
        .refreshable { @MainActor in model.refresh() }
        .onAppear { model.startObserving() }
        .onDisappear { model.stopObserving() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .confirmationDialog("Reset learning?", isPresented: $confirmLearningReset, titleVisibility: .visible) {
            Button("Reset learning", role: .destructive) { model.resetLearning() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes touch calibration, kept words, word counts, next-word pairs and rejected corrections. Statistics stay. The keyboard clears its matching session data before its next save.")
        }
        .confirmationDialog("Reset statistics?", isPresented: $confirmStatisticsReset, titleVisibility: .visible) {
            Button("Reset statistics", role: .destructive) { model.resetStatistics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes counters and speed histograms and starts a new counting period. Learning stays.")
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let updated = Presentation.updatedAt(snapshot) {
                if fixture {
                    Text("Updated 2 minutes ago")
                } else {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                }
            } else {
                Text("No saved snapshot yet")
            }
            if let note = Presentation.availability(snapshot, now: fixture ? KeyboardDiagnosticsFixture.now : Date()) {
                Text(note)
            }
            Text("Saved snapshots are not live permission checks. The app cannot confirm whether Full Access is currently on.")
        }
        .font(.footnote).foregroundStyle(TyprTheme.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var overview: some View {
        section("Overview") {
            metric("Words checked", diagnostics[.boundaries].formatted())
            note("Since \(diagnostics.since.formatted(date: .abbreviated, time: .shortened)). Counted at word boundaries, not every keystroke.")
            metric("Touch evidence complete", Presentation.share(diagnostics[.evidenceComplete], of: diagnostics[.boundaries]))
            DisclosureGroup("Missing touch evidence") {
                counterRows([.evidenceMissing, .evidenceLengthOutOfRange, .evidenceUnsupported])
            }
        }
    }

    private var decisions: some View {
        section("Decisions") {
            note("Automatic replacements by path, and words left unchanged.")
            counterBars(Presentation.decisions)
            metric("Reattributed letter taps", diagnostics[.reattributedTaps].formatted())
            note("Near-boundary letter taps attributed using learned aim and the current prefix. Not a measure of accuracy.")
            DisclosureGroup("Paths that declined to replace") {
                counterBars(Presentation.refusals)
                note("A later path may still have replaced the word. These are not additional word boundaries.")
            }
        }
    }

    private var feedback: some View {
        section("Your feedback") {
            metric("Undone after automatic replacement",
                   Presentation.share(Presentation.undoTotal(diagnostics), of: Presentation.automaticTotal(diagnostics)))
            note("Observed undo share, not accuracy. A replacement without an undo is not proof it was correct. Spatial undo counts combine same-length and letter-edit paths.")
            counterRows(Presentation.feedback)
        }
    }

    private var speed: some View {
        section("Speed") {
            Text("Word decision").font(.subheadline.weight(.medium))
            histogram(diagnostics.boundaryMs)
            Text("Suggestions").font(.subheadline.weight(.medium))
            histogram(diagnostics.suggestionMs)
            metric("Suggestion searches", diagnostics[.suggestionDecodes].formatted())
            note("Measured in the keyboard on this device. Background word-data preparation is excluded. Bars show the number of measurements in each latency bucket, not words per minute.")
        }
    }

    private var learning: some View {
        section("Learning") {
            metric("Learn from my typing", model.learningEnabled ? "On" : "Off")
            note(model.learningEnabled
                ? "Adapts to where you tap, words you keep and which word followed which. Without Full Access, learning lasts for the keyboard session only; that session cannot be shown here."
                : "No new touch, word-count or word-pair learning, and no personal influence. Retained aggregates stay; explicit keep protection still works.")
            metric("Storage", snapshot.isPersistent ? "Shared storage available" : "This session only")
            note("Saved on this iPhone when the keyboard has Full Access. Shared storage availability in the app does not prove keyboard access.")
            DisclosureGroup("Trusted touch labels by source") {
                ForEach(TouchLabelSource.allCases, id: \.rawValue) { source in
                    metric(Presentation.sourceLabel(source), (snapshot.diagnostics.acceptedBySource[source.rawValue] ?? 0).formatted())
                }
                note("Automatic replacements alone never teach touch labels, word counts or word pairs.")
            }
            DisclosureGroup("Rejected touch labels") {
                ForEach(TouchLabelRejection.allCases, id: \.rawValue) { reason in
                    metric(Presentation.rejectionLabel(reason), (snapshot.diagnostics.rejectedByReason[reason.rawValue] ?? 0).formatted())
                }
            }
            counterRows([.wordsCounted, .wordsKept, .correctionsRejected])
            note("The event counts above cover the statistics period. Retained learning below may cover a different period and is bounded.")
            metric("Retained counted words", snapshot.model.countedWords.formatted())
            metric("Retained word-count total", snapshot.model.wordCountTotal.formatted())
            metric("Retained next-word pairs", snapshot.model.storedPairs.formatted())
            metric("Next-word pair storage (bound)", Presentation.fileSize(snapshot.model.pairByteBound))
            NavigationLink("Manage learned words", value: SettingsDestination.keyboardLearnedWords)
            metric("Retained kept words", snapshot.model.keptWords.formatted())
            metric("Retained rejected corrections", snapshot.model.rejectedCorrections.formatted())
            touchModel
        }
    }

    @ViewBuilder private var touchModel: some View {
        if snapshot.model.layouts.isEmpty {
            note("No saved touch model yet. Trusted labels build a separate model for each keyboard layout.")
        } else {
            Text("Touch model").font(.subheadline.weight(.medium))
            if snapshot.model.layouts.count > 1 {
                Picker("Stored layout", selection: Binding(get: {
                    snapshot.model.layouts.first(where: { $0.signature.id == selectedLayout })?.signature.id
                        ?? snapshot.model.layouts.first?.signature.id ?? ""
                }, set: { selectedLayout = $0 })) {
                    ForEach(snapshot.model.layouts, id: \.signature.id) { layout in
                        Text(KeyboardTouchGeometry.title(layout.signature)).tag(layout.signature.id)
                    }
                }
                .pickerStyle(.menu)
            }
            if let layout = snapshot.model.layouts.first(where: { $0.signature.id == selectedLayout }) ?? snapshot.model.layouts.first {
                Text(KeyboardTouchGeometry.title(layout.signature))
                    .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                KeyboardTouchModelView(summary: layout)
            }
        }
    }

    private var storage: some View {
        section("Stored data & reset") {
            note("Aggregated counters, per-key offset statistics, kept words, word counts, next-word pairs and rejected corrections. Word pairs only: no sentences, apps, websites or raw taps.")
            note("Kept words, word counts, next-word pairs and rejected word pairs are personal data. They never leave this iPhone and are excluded from backup.")
            metric("Learning file", Presentation.fileSize(snapshot.learningFile.bytes))
            metric("Statistics file", Presentation.fileSize(snapshot.diagnosticsFile.bytes))
            note("Location: Typr's shared app group on this iPhone.")
            counterRows([.storeCorruptDiscarded, .storeWriteFailed, .storeLoadDeferred])
            if diagnostics[.storeCorruptDiscarded] > 0 {
                note("Invalid saved data was discarded. Some aggregates may be unavailable until the keyboard saves again.")
            }
            if let problem = model.resetProblem {
                Text(problem).font(.subheadline).foregroundStyle(TyprTheme.warmMic)
            }
            Button("Reset learning", role: .destructive) { confirmLearningReset = true }
                .foregroundStyle(.red)
                .tint(.red)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Button("Reset statistics", role: .destructive) { confirmStatisticsReset = true }
                .foregroundStyle(.red)
                .tint(.red)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSection(title: title) {
            VStack(alignment: .leading, spacing: 16, content: content).padding(16)
        }
        .foregroundStyle(TyprTheme.textBase)
        .tint(TyprTheme.success)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(TyprTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(value).monospacedDigit().foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func counterRows(_ counters: [KeyboardDiagnostics.Counter]) -> some View {
        ForEach(counters, id: \.rawValue) { counter in
            metric(Presentation.label(counter), diagnostics[counter].formatted())
        }
    }

    private func counterBars(_ counters: [KeyboardDiagnostics.Counter]) -> some View {
        let maximum = counters.map { diagnostics[$0] }.max() ?? 0
        return ForEach(counters, id: \.rawValue) { counter in
            bar(Presentation.label(counter), count: diagnostics[counter], maximum: maximum)
        }
    }

    private func histogram(_ counts: [Int]) -> some View {
        ForEach(Presentation.histogramLabels.indices, id: \.self) { index in
            bar(Presentation.histogramLabels[index], count: counts[index], maximum: counts.max() ?? 0)
        }
    }

    private func bar(_ title: String, count: Int, maximum: Int) -> some View {
        VStack(spacing: 6) {
            metric(title, count.formatted())
            GeometryReader { geometry in
                Capsule().fill(TyprTheme.layer01)
                Capsule().fill(TyprTheme.success.opacity(0.7))
                    .frame(width: geometry.size.width * CGFloat(Presentation.barShare(count, maximum: maximum)))
            }
            .frame(height: 5).accessibilityHidden(true)
        }
    }
}
