import SwiftUI

struct SettingsPreferences: View {
    var body: some View {
        SettingsSection(title: "Preferences") {
            NavigationLink(value: SettingsDestination.keyboard) {
                SettingsLink(title: "Keyboard", detail: "Layout, suggestions and autocorrect", icon: "keyboard")
            }
            SettingsDivider(leading: 52)
            NavigationLink(value: SettingsDestination.textProcessing) {
                SettingsLink(title: "AI & vocabulary", detail: "AI cleanup and preferred spellings", icon: "wand.and.stars")
            }
            SettingsDivider(leading: 52)
            NavigationLink(value: SettingsDestination.history) {
                SettingsLink(title: "History & feedback", detail: "Dictation log, exports and ratings", icon: "clock.arrow.circlepath")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Refreshes cleanup availability while this page is visible.
@MainActor
struct TextProcessingSettingsCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var aiCleanup = TyprSettings().aiCleanup
    @State private var cleanupReason = TranscriptCleanupProduction.unavailableReason
    @State private var customPrompt = CleanupPromptPreferences().isCustom

    var body: some View {
        VStack(spacing: 24) {
            SettingsSection(title: "AI cleanup") {
                SettingsToggle(title: "Clean up dictations", detail: "Clearer text with on-device Apple Intelligence. Skipped in Verbatim; plain transcript if unavailable.", isOn: $aiCleanup)
                    .onChange(of: aiCleanup) { _, enabled in TyprSettings().aiCleanup = enabled }
                if let reason = cleanupReason {
                    Text(reason).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                }
                SettingsDivider()
                NavigationLink(value: SettingsDestination.cleanupPrompt) {
                    SettingsLink(title: "Cleanup prompt", detail: "Edit the instructions used for AI cleanup",
                                 icon: "text.quote", value: customPrompt ? "Custom" : "Default")
                }
                .buttonStyle(.plain)
            }
            VocabularySettingsCard()
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        TranscriptCleanupProduction.invalidateAvailability()
        aiCleanup = TyprSettings().aiCleanup
        cleanupReason = TranscriptCleanupProduction.unavailableReason
        customPrompt = CleanupPromptPreferences().isCustom
    }
}

/// Observes the archive directly; the navigation root owns presentation and deep links.
@MainActor
struct HistorySettingsCard: View {
    let openLog: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedbackStrip = TyprSettings().dictationFeedbackStrip
    @State private var log = DictationLogStore.shared

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSection(title: "Dictation log") {
                    SettingsToggle(title: "Keep dictation history", detail: "Saves text stages, used vocabulary and feedback. No audio.",
                                   isOn: Binding(get: { log.isEnabled }, set: { log.setEnabled($0) }))
                    if let problem = log.storageProblem { statusNote(problem) }
                    SettingsDivider()
                    Button(action: openLog) {
                        SettingsLink(title: "Open dictation log", detail: "Review, rate, export or delete entries", value: "\(log.metadata.count) entries")
                    }
                    .buttonStyle(.plain)
                }
                Text("Kept until you delete it; switching off keeps saved entries. Export JSON to keep a copy. App removal or device loss is not covered.")
                    .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            SettingsSection(title: "Keyboard feedback") {
                SettingsToggle(title: "Rate after dictating", detail: "Show Good / Problem after the keyboard inserts a dictation. No document text is read for feedback.", isOn: $feedbackStrip)
                    .onChange(of: feedbackStrip) { _, enabled in
                        TyprSettings().dictationFeedbackStrip = enabled
                        log.feedbackSettingsChanged()
                    }
                if let notice = log.keyboardFeedbackNotice {
                    SettingsDivider()
                    statusNote(notice)
                    SettingsDivider()
                    Button { log.retryKeyboardFeedback() } label: {
                        HStack {
                            Text("Retry keyboard feedback")
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.clockwise").accessibilityHidden(true)
                        }
                        .font(.body).foregroundStyle(TyprTheme.textBase)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
                SettingsDivider()
                DisclosureGroup("How feedback is saved") {
                    Text("Noted means queued on this iPhone, not yet saved in the archive. Up to 100 pending ratings are kept for 30 days.")
                        .font(.subheadline).foregroundStyle(TyprTheme.textMuted).padding(.top, 8)
                }
                .disclosureGroupStyle(SettingsDisclosureStyle())
                .padding(.horizontal, 16)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func statusNote(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(TyprTheme.warmMic)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private func refresh() {
        log.setEnabled(TyprSettings().dictationLog)
        feedbackStrip = TyprSettings().dictationFeedbackStrip
    }
}
