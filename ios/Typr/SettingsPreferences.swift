import SwiftUI

/// The settings index owns log routing even when no detail page is open.
@MainActor
struct SettingsPreferences: View {
    @Environment(\.scenePhase) private var scenePhase
    let dictation: DictationController
    @State private var aiCleanup = TyprSettings().aiCleanup
    @State private var cleanupReason = TranscriptCleanupProduction.unavailableReason
    @State private var cleanupLast = TranscriptCleanupProduction.lastSummary
    @State private var feedbackStrip = TyprSettings().dictationFeedbackStrip
    @State private var log = DictationLogStore.shared
    @State private var showingLog = false
    @State private var feedbackRouter = TyprFeedbackRouter.shared

    var body: some View {
        SettingsSection(title: "Make it yours") {
            NavigationLink(value: SettingsDestination.keyboard) {
                SettingsLink(title: "Keyboard", detail: "Layout, suggestions and autocorrect", icon: "keyboard")
            }
            SettingsDivider()
            NavigationLink(value: SettingsDestination.writing) {
                SettingsLink(title: "Writing", detail: "AI cleanup and custom vocabulary", icon: "textformat")
            }
            SettingsDivider()
            NavigationLink(value: SettingsDestination.history) {
                SettingsLink(title: "History & feedback", detail: "Dictation log, exports and ratings", icon: "clock.arrow.circlepath")
            }
        }
        .buttonStyle(.plain)
        .navigationDestination(for: SettingsDestination.self) { destination in
            SettingsPage(title: destination.title, subtitle: destination.subtitle) {
                switch destination {
                case .keyboard: KeyboardSettingsCard()
                case .writing:
                    cleanupSection
                    VocabularySettingsCard()
                case .history:
                    historySection
                    feedbackSection
                case .speechEngine: SpeechEngineCard(dictation: dictation)
                }
            }
        }
        .sheet(isPresented: $showingLog) { DictationLogView(store: log, router: feedbackRouter) }
        .onChange(of: feedbackRouter.requestedEntry) { _, id in
            if id != nil { showingLog = true }
        }
        .onAppear {
            refresh()
            if feedbackRouter.requestedEntry != nil { showingLog = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                log.drainKeyboardFeedback(force: true)
                refresh()
            }
        }
    }

    private var cleanupSection: some View {
        SettingsSection(title: "AI cleanup") {
            SettingsToggle(title: "Clean up dictations", detail: "Clearer text with on-device Apple Intelligence. Skipped in Verbatim; plain transcript if unavailable.", isOn: $aiCleanup)
                .onChange(of: aiCleanup) { _, enabled in TyprSettings().aiCleanup = enabled }
            if let reason = cleanupReason {
                statusNote(reason)
            }
            if let last = cleanupLast {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("Last result").font(.caption.weight(.medium)).foregroundStyle(TyprTheme.textMuted)
                    Text(last).font(.subheadline).foregroundStyle(TyprTheme.textBase)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            SettingsDivider()
            DisclosureGroup("What changes?") {
                Text("Keeps your final version after self-corrections, removes fillers and stutters, and fixes misheard words and technical terms. Your vocabulary supplies preferred spellings. Processing stays on this iPhone.")
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    .padding(.top, 8)
            }
            .font(.subheadline).foregroundStyle(TyprTheme.textBase).padding(18)
        }
        .task {
            while !Task.isCancelled {
                cleanupLast = TranscriptCleanupProduction.lastSummary
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var historySection: some View {
        SettingsSection(title: "Dictation log") {
            SettingsToggle(title: "Keep dictation history", detail: "Saves text stages, used vocabulary and feedback. No audio. Kept until you delete it; switching off keeps existing entries.",
                           isOn: Binding(get: { log.isEnabled }, set: { log.setEnabled($0) }))
            if let problem = log.storageProblem { statusNote(problem) }
            SettingsDivider()
            Button { showingLog = true } label: {
                SettingsLink(title: "Open dictation log", detail: "Review, rate, export or delete entries", icon: "text.book.closed", value: "\(log.metadata.count) entries")
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Text("Export JSON to keep a copy. History is not protected against app removal or device loss.")
                .font(.subheadline).foregroundStyle(TyprTheme.textMuted).padding(18)
        }
    }

    private var feedbackSection: some View {
        SettingsSection(title: "Keyboard feedback") {
            SettingsToggle(title: "Rate after dictating", detail: "Show Good / Problem after the keyboard inserts a dictation. No document text is read for feedback.", isOn: $feedbackStrip)
                .onChange(of: feedbackStrip) { _, enabled in
                    TyprSettings().dictationFeedbackStrip = enabled
                    log.feedbackSettingsChanged()
                }
            if let notice = log.keyboardFeedbackNotice {
                statusNote(notice)
                Button("Retry keyboard feedback") { log.retryKeyboardFeedback() }
                    .frame(minHeight: 44).padding(.horizontal, 18)
            }
            SettingsDivider()
            DisclosureGroup("How feedback is saved") {
                Text("Noted means queued on this iPhone, not yet saved in the archive. Up to 100 pending ratings are kept for 30 days.")
                    .font(.subheadline).foregroundStyle(TyprTheme.textMuted).padding(.top, 8)
            }
            .font(.subheadline).foregroundStyle(TyprTheme.textBase).padding(18)
        }
    }

    private func statusNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.bottom, 14)
    }

    private func refresh() {
        log.setEnabled(TyprSettings().dictationLog)
        TranscriptCleanupProduction.invalidateAvailability()
        aiCleanup = TyprSettings().aiCleanup
        feedbackStrip = TyprSettings().dictationFeedbackStrip
        cleanupReason = TranscriptCleanupProduction.unavailableReason
        cleanupLast = TranscriptCleanupProduction.lastSummary
    }
}
