import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct TyprDictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TyprDictationActivityAttributes.self) { context in
            LockScreenBanner(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color(red: 0x11 / 255.0, green: 0x13 / 255.0, blue: 0x16 / 255.0))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let isRecording = !context.isStale && context.state.stage == .recording
            let isCooling = !context.isStale && context.state.stage == .transcribing
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LockScreenBanner(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                TyprDotMatrixBadge(columns: 9, rows: 5, pitch: 2.2, cooling: isCooling)
                    .padding(.leading, 2)
            } compactTrailing: {
                if isRecording {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(TyprTheme.warmPearl)
                        .frame(maxWidth: 44, alignment: .trailing)
                        .padding(.trailing, 3)
                } else {
                    Image(systemName: isCooling ? "ellipsis" : "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCooling ? TyprTheme.agentBlue : TyprTheme.textBase)
                        .padding(.trailing, 4)
                }
            } minimal: {
                TyprDotMatrixBadge(columns: 7, rows: 5, pitch: 2.1, cooling: isCooling)
            }
            .keylineTint(isRecording ? TyprTheme.warmPearl : TyprTheme.agentBlue)
        }
    }
}

private struct LockScreenBanner: View {
    let state: TyprDictationActivityAttributes.ContentState
    let isStale: Bool

    private var activeStage: TyprDictationActivityAttributes.Stage {
        isStale ? .copied : state.stage
    }

    var body: some View {
        HStack(spacing: 12) {
            if activeStage == .copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TyprTheme.success)
                    .frame(width: 28, height: 28)
                    .background(TyprTheme.layer02, in: Circle())
                Text("Copied")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TyprTheme.textBase)
            } else {
                TyprDotMatrixBadge(
                    columns: activeStage == .recording ? 25 : 19,
                    rows: 7,
                    pitch: 2.5,
                    cooling: activeStage == .transcribing
                )

                if activeStage == .recording {
                    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(TyprTheme.textMuted)
                }
            }

            Spacer(minLength: 8)

            if activeStage == .recording {
                HStack(spacing: 6) {
                    Button(intent: CancelTyprDictationIntent()) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TyprTheme.textMuted)
                            .frame(width: 34, height: 34)
                            .background(TyprTheme.layer02, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")

                    Button(intent: StopTyprDictationIntent()) {
                        Text("Done")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TyprTheme.textContrast)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(TyprTheme.bgContrast, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Finish dictation")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
