import UIKit

/// After a dictation, Good / Problem as large tiles over the whole full keyboard, where the
/// recording panel was. `FullKeyboardView` closes it on any tap except Problem, which leaves
/// *Fix in Typr* (opens the app on exactly this entry) and ✕. A rating that could not be queued
/// and, without the suggestion bar, Typr's messages use the same panel. No document proxy here.
///
/// Items are laid out with explicit frames: the panel is built when a result arrives and must
/// not depend on a previous layout pass.
@MainActor
final class TyprFeedbackPanel: UIView {
    enum Content: Equatable {
        /// Good or Problem for the dictation just inserted.
        case ask
        /// After Problem: open this entry in Typr, or close.
        case problem
        /// The rating could not be queued.
        case retry(String)
        /// A Typr message that would otherwise sit in the hidden suggestion bar.
        case notice(String)
    }

    static let openTitle = "Feedback in Typr"
    static let openAccessibilityLabel = "Open this dictation in Typr to add a feedback note"
    static let dismissFeedbackLabel = "Dismiss dictation feedback"
    static let dismissMessageLabel = "Dismiss message"

    var palette = FullKeyboardPalette(isDark: false) { didSet { if palette != oldValue { rebuild() } } }
    var content: Content = .ask { didSet { if content != oldValue { rebuild() } } }
    var metrics = KeyboardMetrics.portrait { didSet { setNeedsLayout() } }
    var horizontalInset: CGFloat = 0 { didSet { setNeedsLayout() } }

    var onGood: (() -> Void)?
    var onProblem: (() -> Void)?
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private let messageWell = UIView()
    private let messageLabel = UILabel()
    private var tiles: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        accessibilityViewIsModal = true

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        messageWell.layer.cornerRadius = 20
        messageWell.layer.cornerCurve = .continuous
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.adjustsFontSizeToFitWidth = true
        messageLabel.minimumScaleFactor = 0.7
        messageWell.addSubview(messageLabel)

        closeButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        for view in [titleLabel, messageWell, closeButton] {
            addSubview(view)
        }
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []
        titleLabel.textColor = palette.textBase
        messageWell.backgroundColor = palette.wellFill
        messageLabel.textColor = palette.textBase
        messageWell.isHidden = true
        configureCloseButton()

        switch content {
        case .ask:
            titleLabel.text = "How was this dictation?"
            closeButton.accessibilityLabel = Self.dismissFeedbackLabel
            tiles = [
                tile("Good", symbol: "hand.thumbsup") { [weak self] in self?.onGood?() },
                tile("Problem", symbol: "hand.thumbsdown") { [weak self] in self?.onProblem?() },
            ]
        case .problem:
            titleLabel.text = "What did you expect differently?"
            closeButton.accessibilityLabel = Self.dismissFeedbackLabel
            tiles = [
                tile(Self.openTitle, symbol: "square.and.pencil", accessibilityLabel: Self.openAccessibilityLabel) {
                    [weak self] in self?.onOpen?()
                },
            ]
        case .retry(let message):
            titleLabel.text = message
            closeButton.accessibilityLabel = Self.dismissFeedbackLabel
            tiles = [tile("Retry feedback", symbol: "arrow.clockwise") { [weak self] in self?.onRetry?() }]
        case .notice(let message):
            titleLabel.text = "Typr"
            messageLabel.text = message
            messageWell.isHidden = false
            closeButton.accessibilityLabel = Self.dismissMessageLabel
        }
        tiles.forEach { addSubview($0) }
        setNeedsLayout()
    }

    private func configureCloseButton() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        config.baseForegroundColor = palette.textBase
        config.background.backgroundColor = palette.chipFill
        config.cornerStyle = .capsule
        config.contentInsets = .zero
        closeButton.configuration = config
    }

    /// A large keycap-styled tile: symbol above its title.
    private func tile(
        _ title: String,
        symbol: String,
        accessibilityLabel: String? = nil,
        action: @escaping @MainActor () -> Void
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        )
        config.imagePlacement = .top
        config.imagePadding = 10
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 16, weight: .semibold)
            return attributes
        }
        config.baseForegroundColor = palette.textBase
        config.background.backgroundColor = palette.keyFill
        config.background.cornerRadius = 16
        let button = UIButton(configuration: config)
        let fill = palette.keyFill
        let pressed = palette.keyPressedFill
        button.configurationUpdateHandler = { button in
            button.configuration?.background.backgroundColor = button.isHighlighted ? pressed : fill
        }
        button.accessibilityLabel = accessibilityLabel ?? title
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let innerLeft = horizontalInset + metrics.side
        let innerRight = bounds.width - horizontalInset - metrics.side
        let innerW = max(120, innerRight - innerLeft)
        let headerTop = metrics.stripTop
        let headerH = KeyboardMetrics.headerHeight

        closeButton.frame = CGRect(x: innerRight - 44, y: headerTop + (headerH - 30) / 2, width: 44, height: 30)
        titleLabel.frame = CGRect(
            x: innerLeft + 8,
            y: headerTop,
            width: max(0, closeButton.frame.minX - innerLeft - 16),
            height: headerH
        )

        let top = headerTop + headerH + 6
        let bottom = bounds.height - metrics.keysBottom
        let area = CGRect(x: innerLeft, y: top, width: innerW, height: max(44, bottom - top))
        messageWell.frame = area
        messageLabel.frame = messageWell.bounds.insetBy(dx: 16, dy: 12)

        let count = CGFloat(max(1, tiles.count))
        let tileW = (area.width - (count - 1) * metrics.gap) / count
        for (index, tile) in tiles.enumerated() {
            tile.frame = CGRect(
                x: area.minX + CGFloat(index) * (tileW + metrics.gap),
                y: area.minY,
                width: tileW,
                height: area.height
            )
        }
    }
}
