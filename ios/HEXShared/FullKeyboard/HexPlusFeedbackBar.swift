import UIKit

/// Good / Problem / dismiss in the existing suggestion strip; after Problem, one button opens the
/// app's feedback editor for exactly this entry. Undo is a separate sibling, never replaced by this
/// bar. No document proxy is available here.
///
/// Items are laid out with explicit frames, not a stack view's fitting size: the bar is built while
/// hidden and filled later, when the keyboard inserts a dictation, and must not depend on a
/// previous zero-size layout pass.
@MainActor
final class HexPlusFeedbackBar: UIScrollView {
    static let openTitle = "Fix in Typr"
    static let openAccessibilityLabel = "Open this dictation in Typr to enter what you said"
    private static let spacing: CGFloat = 8

    private var items: [(view: UIView, width: CGFloat)] = []
    private var presentation: DictationFeedbackPresentation?
    private var lastDark: Bool?
    var onRating: ((String, [String]?) -> Void)?
    var onDismiss: (() -> Void)?
    var onOpenEntry: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        alwaysBounceHorizontal = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(_ value: DictationFeedbackPresentation?, palette: FullKeyboardPalette) {
        guard presentation != value || lastDark != palette.isDark else { return }
        presentation = value; lastDark = palette.isDark
        items.forEach { $0.view.removeFromSuperview() }
        items = []
        isHidden = value == nil
        guard let value else { return }
        button("Good", symbol: value.rating == "good" ? "hand.thumbsup.fill" : "hand.thumbsup", palette: palette) { [weak self] in
            self?.onRating?("good", nil)
        }
        button("Problem", symbol: value.rating == "bad" ? "hand.thumbsdown.fill" : "hand.thumbsdown", palette: palette) { [weak self] in
            self?.onRating?("bad", nil)
        }
        if value.rating == "bad" {
            let entryID = value.offer.entryID
            button(Self.openTitle, symbol: "square.and.pencil", palette: palette, showTitle: true,
                   accessibilityLabel: Self.openAccessibilityLabel) { [weak self] in
                self?.onOpenEntry?(entryID)
            }
        }
        button("Dismiss dictation feedback", symbol: "xmark", palette: palette) { [weak self] in self?.onDismiss?() }
        if let message = value.message {
            let label = UILabel(); label.font = .systemFont(ofSize: 11); label.text = message
            label.textColor = palette.textMuted
            add(label, width: ceil(label.intrinsicContentSize.width))
            if message.hasPrefix("Not queued") {
                button("Retry feedback", symbol: "arrow.clockwise", palette: palette) { [weak self] in
                    self?.onRating?(value.retryRating ?? value.rating ?? "bad", value.retryIssues)
                }
            }
        }
        setNeedsLayout()
    }

    private func add(_ view: UIView, width: CGFloat) {
        addSubview(view)
        items.append((view, width))
    }

    private func button(_ title: String, symbol: String, palette: FullKeyboardPalette, showTitle: Bool = false,
                        accessibilityLabel: String? = nil, action: @escaping @MainActor () -> Void) {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        config.baseForegroundColor = palette.textBase
        config.contentInsets = .init(top: 0, leading: 4, bottom: 0, trailing: 4)
        if showTitle {
            config.title = title; config.imagePadding = 4
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 13, weight: .medium)
                return attributes
            }
            config.background.backgroundColor = palette.chipFill
            config.background.cornerRadius = 14
            config.contentInsets = .init(top: 0, leading: 10, bottom: 0, trailing: 10)
        }
        button.configuration = config
        button.accessibilityLabel = accessibilityLabel ?? title
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        let fitting = button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 33)).width
        add(button, width: max(44, ceil(fitting)))
    }

    /// Total width of all items (the scrollable content width).
    var contentWidth: CGFloat {
        items.reduce(0) { $0 + $1.width } + Self.spacing * CGFloat(max(0, items.count - 1))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        for item in items {
            let isButton = item.view is UIButton
            let height = isButton && (item.view as? UIButton)?.configuration?.title != nil
                ? min(28, bounds.height) : bounds.height
            item.view.frame = CGRect(x: x, y: (bounds.height - height) / 2, width: item.width, height: height)
            x += item.width + Self.spacing
        }
        contentSize = CGSize(width: max(bounds.width, contentWidth), height: bounds.height)
    }
}
