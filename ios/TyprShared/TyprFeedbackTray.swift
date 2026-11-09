import SwiftUI

/// Only rating controls and a link into the app; never a text field or a replacement for document input.
/// Problem details (what was recognized, what AI made of it, what was meant) are entered in the app,
/// where the texts can be read: the keyboard cannot show them usefully.
struct TyprFeedbackTray: View {
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
                    if feedback.rating == "bad" {
                        Button {
                            let url = TyprFeedbackLink.url(entryID: feedback.offer.entryID)
                            model.dismissFeedback()
                            model.onOpenURL?(url)
                        } label: {
                            Label(TyprFeedbackPanel.openTitle, systemImage: "square.and.pencil")
                        }.accessibilityLabel(TyprFeedbackPanel.openAccessibilityLabel)
                    }
                    Button { model.dismissFeedback() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss dictation feedback")
                    if let message = feedback.message {
                        Text(message).accessibilityLabel(message)
                        if message.hasPrefix("Not queued") {
                            Button("Retry feedback") { model.onFeedbackRating?(feedback.retryRating ?? feedback.rating ?? "bad", feedback.retryIssues) }
                        }
                    }
                    Button("Style") {
                        model.dismissFeedback(); model.setActiveTray(.style, reduceMotion: reduceMotion)
                    }
                }.frame(height: 26).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TyprTheme.textBase).buttonStyle(FeedbackTapTarget())
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
