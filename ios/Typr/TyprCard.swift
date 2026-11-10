import SwiftUI

/// Typr switches. They live in the App Group so the keyboard reads them too.
@MainActor
struct TyprCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var aiCleanup = TyprSettings().aiCleanup
    @State private var cleanupReason = TranscriptCleanupProduction.unavailableReason
    @State private var cleanupLast = TranscriptCleanupProduction.lastSummary
    @State private var hideSuggestionBar = TyprSettings().hideSuggestionBar
    @State private var feedbackStrip = TyprSettings().dictationFeedbackStrip
    @State private var log = DictationLogStore.shared
    @State private var showingLog = false
    @State private var feedbackRouter = TyprFeedbackRouter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typr")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TyprTheme.textMuted)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                row(
                    "AI cleanup",
                    detail: "Apple Intelligence turns your dictation into clear written text: keeps only your final version when you correct yourself, removes ähm and stutters, and fixes misheard words and technical terms. Not in Verbatim. Falls back to the plain transcript when unavailable."
                        + (cleanupReason.map { "\n" + $0 } ?? "")
                        + (cleanupLast.map { "\n" + $0 } ?? ""),
                    isOn: $aiCleanup
                )
                // The last outcome changes while the card is visible (dictating from this screen).
                .task {
                    while !Task.isCancelled {
                        cleanupLast = TranscriptCleanupProduction.lastSummary
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
                .onChange(of: aiCleanup) { _, enabled in
                    TyprSettings().aiCleanup = enabled
                }
                Divider()
                    .overlay(TyprTheme.borderWeak)
                    .padding(.leading, 16)

                row(
                    "Dictation log",
                    detail: "Keeps dictations until you delete them: text stages, vocabulary and feedback, no audio. Off stops collection and keeps saved logs. Export JSON for a copy; app removal and device loss are not covered.",
                    isOn: Binding(get: { log.isEnabled }, set: { log.setEnabled($0) })
                )
                if let problem = log.storageProblem {
                    Text(problem)
                        .font(.system(size: 12))
                        .foregroundStyle(TyprTheme.textMuted)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                }
                Group {
                    Button("Show dictation log (\(log.metadata.count))") { showingLog = true }
                        .font(.system(size: 15))
                        .foregroundStyle(TyprTheme.textBase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                Divider().overlay(TyprTheme.borderWeak).padding(.leading, 16)

                if let notice = log.keyboardFeedbackNotice {
                    Text(notice).font(.system(size: 12)).foregroundStyle(TyprTheme.textMuted)
                        .padding(.horizontal, 16)
                    Button("Retry keyboard feedback") { log.retryKeyboardFeedback() }.padding(.horizontal, 16)
                }
                row("Keyboard dictation feedback",
                    detail: "Good / Problem after this keyboard inserts your dictation. Noted means queued locally, not saved in the archive yet. Pending feedback expires after 30 days; maximum 100. No document text is read for feedback.",
                    isOn: $feedbackStrip)
                    .onChange(of: feedbackStrip) { _, enabled in
                        TyprSettings().dictationFeedbackStrip = enabled
                        log.feedbackSettingsChanged()
                    }
                Divider().overlay(TyprTheme.borderWeak).padding(.leading, 16)

                row(
                    "Hide suggestion bar",
                    detail: "The full keyboard without the bar above the keys, so more of your text stays visible. Autocorrect still applies when you type a space.",
                    isOn: $hideSuggestionBar
                )
                .onChange(of: hideSuggestionBar) { _, enabled in
                    TyprSettings().hideSuggestionBar = enabled
                }
            }
            .background(
                TyprTheme.bgBase,
                in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius, style: .continuous)
            )
        }
        .sheet(isPresented: $showingLog) { DictationLogView(store: log, router: feedbackRouter) }
        // "Feedback in Typr" from the keyboard: the log opens the requested entry itself.
        .onChange(of: feedbackRouter.requestedEntry) { _, id in
            if id != nil { showingLog = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                log.drainKeyboardFeedback(force: true)
                TranscriptCleanupProduction.invalidateAvailability()
                log.setEnabled(TyprSettings().dictationLog)
                aiCleanup = TyprSettings().aiCleanup
                cleanupReason = TranscriptCleanupProduction.unavailableReason
                cleanupLast = TranscriptCleanupProduction.lastSummary
            }
        }
        .onAppear {
            if feedbackRouter.requestedEntry != nil { showingLog = true }
            log.setEnabled(TyprSettings().dictationLog)
            TranscriptCleanupProduction.invalidateAvailability()
            aiCleanup = TyprSettings().aiCleanup
            cleanupReason = TranscriptCleanupProduction.unavailableReason
            cleanupLast = TranscriptCleanupProduction.lastSummary
            hideSuggestionBar = TyprSettings().hideSuggestionBar
        }
    }

    private func row(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(TyprTheme.textBase)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(TyprTheme.textMuted)
            }
        }
        .tint(TyprTheme.success)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
