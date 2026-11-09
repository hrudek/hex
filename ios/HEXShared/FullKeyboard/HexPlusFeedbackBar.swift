import UIKit

/// Horizontal optional categories stay in the existing suggestion strip. Undo is a
/// separate sibling, never replaced by this bar. No document proxy is available here.
@MainActor
final class HexPlusFeedbackBar: UIScrollView {
    private let stack = UIStackView()
    private var presentation: DictationFeedbackPresentation?
    private var lastDark: Bool?
    var onRating: ((String, [String]?) -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        stack.axis = .horizontal; stack.spacing = 10
        addSubview(stack)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(_ value: DictationFeedbackPresentation?, palette: FullKeyboardPalette) {
        guard presentation != value || lastDark != palette.isDark else { return }
        presentation = value; lastDark = palette.isDark
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        isHidden = value == nil
        guard let value else { return }
        button("Good", symbol: value.rating == "good" ? "hand.thumbsup.fill" : "hand.thumbsup", palette: palette) { [weak self] in
            self?.onRating?("good", nil)
        }
        button("Problem", symbol: value.rating == "bad" ? "hand.thumbsdown.fill" : "hand.thumbsdown", palette: palette) { [weak self] in
            self?.onRating?("bad", nil)
        }
        button("Dismiss dictation feedback", symbol: "xmark", palette: palette) { [weak self] in self?.onDismiss?() }
        if let message = value.message {
            let label = UILabel(); label.font = .systemFont(ofSize: 11); label.text = message
            label.textColor = palette.textMuted
            label.widthAnchor.constraint(equalToConstant: label.intrinsicContentSize.width).isActive = true
            stack.addArrangedSubview(label)
            if message.hasPrefix("Not queued") {
                button("Retry feedback", symbol: "arrow.clockwise", palette: palette) { [weak self] in
                    self?.onRating?(value.retryRating ?? value.rating ?? "bad", value.retryIssues)
                }
            }
        }
        if value.rating == "bad" {
            for (code, title) in DictationIssue.choices {
                let selected = value.issues.contains(code)
                button(title, symbol: selected ? "checkmark.circle.fill" : "circle", palette: palette, showTitle: true) { [weak self] in
                    var issues = value.issues
                    if selected { issues.removeAll { $0 == code } } else { issues.append(code) }
                    self?.onRating?("bad", issues)
                }
            }
        }
        setNeedsLayout()
    }
    private func button(_ title: String, symbol: String, palette: FullKeyboardPalette, showTitle: Bool = false,
                        action: @escaping @MainActor () -> Void) {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        config.baseForegroundColor = palette.textBase
        config.contentInsets = .init(top: 0, leading: 4, bottom: 0, trailing: 4)
        if showTitle { config.title = title; config.imagePadding = 4 }
        button.configuration = config; button.accessibilityLabel = title
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: max(showTitle ? 80 : 44, button.intrinsicContentSize.width)).isActive = true
        stack.addArrangedSubview(button)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stack.frame = CGRect(x: 0, y: 0, width: size.width, height: bounds.height)
        stack.layoutIfNeeded()
        contentSize = CGSize(width: max(bounds.width, size.width), height: bounds.height)
    }
}
