import Combine
import SwiftUI

/// Hex+ switches. They live in the App Group so the keyboard reads them too.
@MainActor
struct HexPlusCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var aiCleanup = HexPlusSettings().aiCleanup
    @State private var showCleanupModel = HexPlusSettings().showCleanupModel
    @State private var modelInfo = HexPlusModelInfoReader.production.read()
    @State private var cleanupReason = TranscriptCleanupProduction.unavailableReason
    @State private var cleanupLast = TranscriptCleanupProduction.lastSummary
    @State private var germanAutocorrect = HexPlusSettings().germanAutocorrect
    @State private var keyboardSwitchKey = HexPlusSettings().keyboardSwitchKey
    @State private var feedbackStrip = HexPlusSettings().dictationFeedbackStrip
    @State private var log = DictationLogStore.shared
    @State private var showingLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hex+")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HexTheme.textMuted)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                row(
                    "AI cleanup",
                    detail: "Apple Intelligence keeps only your final version when you correct yourself, removes ähm and stutters, and fixes misheard words. Not in Verbatim. Falls back to the plain transcript when unavailable."
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
                    HexPlusSettings().aiCleanup = enabled
                    modelInfo = HexPlusModelInfoReader.production.read()
                }
                Divider()
                    .overlay(HexTheme.borderWeak)
                    .padding(.leading, 16)

                row(
                    "Show AI cleanup model",
                    detail: showCleanupModel
                        ? modelInfo.lines.joined(separator: "\n")
                        : "Shows which Apple Intelligence model cleans up your dictations",
                    isOn: $showCleanupModel
                )
                .onChange(of: showCleanupModel) { _, enabled in
                    HexPlusSettings().showCleanupModel = enabled
                    if enabled { modelInfo = HexPlusModelInfoReader.production.read() }
                }

                Divider()
                    .overlay(HexTheme.borderWeak)
                    .padding(.leading, 16)

                row(
                    "Dictation log",
                    detail: "Keeps dictations until you delete them: text stages, vocabulary and feedback, no audio. Off stops collection and keeps saved logs. Export JSON for a copy; app removal and device loss are not covered.",
                    isOn: Binding(get: { log.isEnabled }, set: { log.setEnabled($0) })
                )
                if let problem = log.storageProblem {
                    Text(problem)
                        .font(.system(size: 12))
                        .foregroundStyle(HexTheme.textMuted)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                }
                Group {
                    Button("Show dictation log (\(log.metadata.count))") { showingLog = true }
                        .font(.system(size: 15))
                        .foregroundStyle(HexTheme.textBase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                Divider().overlay(HexTheme.borderWeak).padding(.leading, 16)

                if let notice = log.keyboardFeedbackNotice {
                    Text(notice).font(.system(size: 12)).foregroundStyle(HexTheme.textMuted)
                        .padding(.horizontal, 16)
                    Button("Retry keyboard feedback") { log.retryKeyboardFeedback() }.padding(.horizontal, 16)
                }
                row("Keyboard dictation feedback",
                    detail: "Good / Problem after this keyboard inserts your dictation. Noted means queued locally, not saved in the archive yet. Pending feedback expires after 30 days; maximum 100. No document text is read for feedback.",
                    isOn: $feedbackStrip)
                    .onChange(of: feedbackStrip) { _, enabled in
                        HexPlusSettings().dictationFeedbackStrip = enabled
                        log.feedbackSettingsChanged()
                    }
                Divider().overlay(HexTheme.borderWeak).padding(.leading, 16)

                row(
                    "German autocorrect",
                    detail: "Turns ae, oe, ue into ä, ö, ü and fixes German typos (full keyboard)",
                    isOn: $germanAutocorrect
                )
                .onChange(of: germanAutocorrect) { _, enabled in
                    HexPlusSettings().germanAutocorrect = enabled
                }

                Divider()
                    .overlay(HexTheme.borderWeak)
                    .padding(.leading, 16)

                row(
                    "Keyboard switch key",
                    detail: "A key on both keyboards switches between the full keyboard and the dictation bar. On the full keyboard, hold it briefly.",
                    isOn: $keyboardSwitchKey
                )
                .onChange(of: keyboardSwitchKey) { _, enabled in
                    HexPlusSettings().keyboardSwitchKey = enabled
                }
            }
            .background(
                HexTheme.bgBase,
                in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous)
            )
        }
        .sheet(isPresented: $showingLog) { DictationLogView(store: log) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                log.drainKeyboardFeedback(force: true)
                TranscriptCleanupProduction.invalidateAvailability()
                log.setEnabled(HexPlusSettings().dictationLog)
                aiCleanup = HexPlusSettings().aiCleanup
                showCleanupModel = HexPlusSettings().showCleanupModel
                cleanupReason = TranscriptCleanupProduction.unavailableReason
                cleanupLast = TranscriptCleanupProduction.lastSummary
                modelInfo = HexPlusModelInfoReader.production.read()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            // Separate defaults instances back the sibling card; do not filter by object.
            // Hop delivery to the main run loop without carrying Notification into a Task.
            MainActor.assumeIsolated {
                modelInfo = HexPlusModelInfoReader.production.read()
            }
        }
        .onAppear {
            log.setEnabled(HexPlusSettings().dictationLog)
            TranscriptCleanupProduction.invalidateAvailability()
            aiCleanup = HexPlusSettings().aiCleanup
            showCleanupModel = HexPlusSettings().showCleanupModel
            cleanupReason = TranscriptCleanupProduction.unavailableReason
            cleanupLast = TranscriptCleanupProduction.lastSummary
            modelInfo = HexPlusModelInfoReader.production.read()
            germanAutocorrect = HexPlusSettings().germanAutocorrect
            keyboardSwitchKey = HexPlusSettings().keyboardSwitchKey
        }
    }

    private func row(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HexTheme.textBase)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(HexTheme.textMuted)
            }
        }
        .tint(HexTheme.success)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
