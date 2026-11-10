import SwiftUI

extension DictationFeedbackPresentation {
    var panelContent: TyprFeedbackPanel.Content {
        if let message, message.hasPrefix("Not queued") { return .retry(message) }
        return rating == "bad" ? .problem : .ask
    }
}

/// The dictation-only surface hosts the exact UIKit panel used over the full keyboard.
struct TyprFeedbackTray: UIViewRepresentable {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> TyprFeedbackPanel {
        TyprFeedbackPanel()
    }

    func updateUIView(_ panel: TyprFeedbackPanel, context: Context) {
        panel.palette = FullKeyboardPalette(isDark: colorScheme == .dark)
        panel.content = model.feedback?.panelContent ?? .ask
        panel.onGood = { model.rateFeedback("good") }
        panel.onProblem = { model.rateFeedback("bad") }
        panel.onRetry = {
            guard let feedback = model.feedback else { return }
            model.rateFeedback(feedback.retryRating ?? feedback.rating ?? "bad", issues: feedback.retryIssues)
        }
        panel.onDismiss = { model.dismissFeedback() }
        panel.onOpen = {
            guard let entryID = model.feedback?.offer.entryID else { return }
            model.dismissFeedback()
            model.onOpenURL?(TyprFeedbackLink.url(entryID: entryID))
        }
    }
}
