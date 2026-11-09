import SwiftUI

/// Only categorical controls; never a text field or a replacement for document input.
struct HexPlusFeedbackTray: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if model.hasFullAccess, let feedback = model.feedback {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { model.onFeedbackRating?("good", nil) } label: {
                        Label("Good", systemImage: feedback.rating == "good" ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }.accessibilityLabel("Rate inserted dictation Good")
                    Button { model.onFeedbackRating?("bad", nil) } label: {
                        Label("Problem", systemImage: feedback.rating == "bad" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }.accessibilityLabel("Rate inserted dictation Problem")
                    Button { model.dismissFeedback() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss dictation feedback")
                    if let message = feedback.message {
                        Text(message).accessibilityLabel(message)
                        if message.hasPrefix("Not queued") {
                            Button("Retry feedback") { model.onFeedbackRating?(feedback.retryRating ?? feedback.rating ?? "bad", feedback.retryIssues) }
                        }
                    }
                    if feedback.rating == "bad" {
                        ForEach(DictationIssue.choices, id: \.0) { code, title in
                            Button {
                                var issues = feedback.issues
                                if issues.contains(code) { issues.removeAll { $0 == code } } else { issues.append(code) }
                                model.onFeedbackRating?("bad", issues)
                            } label: {
                                Label(title, systemImage: feedback.issues.contains(code) ? "checkmark.circle.fill" : "circle")
                            }.accessibilityLabel("\(title), \(feedback.issues.contains(code) ? "selected" : "not selected")")
                        }
                    }
                    Button("Style") {
                        model.dismissFeedback(); model.setActiveTray(.style, reduceMotion: reduceMotion)
                    }
                }.frame(height: 26).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HexTheme.textBase).buttonStyle(FeedbackTapTarget())
            }
        }
    }
}

private struct FeedbackTapTarget: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 26).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
