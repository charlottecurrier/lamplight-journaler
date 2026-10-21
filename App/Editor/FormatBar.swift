import UIKit

/// The bar above the keyboard. It has formatting buttons, and while a "/" word is being typed it shows
/// the matching slash commands instead.
final class FormatBar: UIInputView {
    var onCommand: (FormatCommand) -> Void = { _ in }
    var onSlash: (SlashCommand) -> Void = { _ in }
    var onDismissKeyboard: () -> Void = {}

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var formatViews: [UIView] = []
    private var showingSlash = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        build()
        setContent(formatViews)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Layout

    private func build() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        var dismissConfiguration = UIButton.Configuration.plain()
        dismissConfiguration.image = UIImage(systemName: "keyboard.chevron.compact.down")
        dismissConfiguration.baseForegroundColor = Palette.inkSecondary.uiColor
        let dismiss = UIButton(configuration: dismissConfiguration, primaryAction: UIAction { [weak self] _ in
            self?.onDismissKeyboard()
        })
        dismiss.accessibilityLabel = "Hide keyboard"
        dismiss.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(dismiss)
        NSLayoutConstraint.activate([
            dismiss.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            dismiss.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismiss.widthAnchor.constraint(equalToConstant: 44),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        formatViews = [
            headingButton(),
            symbolButton("bold", "Bold", .bold),
            symbolButton("italic", "Italic", .italic),
            symbolButton("strikethrough", "Strikethrough", .strike),
            symbolButton("highlighter", "Highlight", .highlight),
            divider(),
            symbolButton("list.bullet", "Bulleted list", .bullet),
            symbolButton("list.number", "Numbered list", .numbered),
            symbolButton("checklist", "Checklist", .checklist),
            symbolButton("text.quote", "Quote", .quote),
            divider(),
            symbolButton("link", "Link", .link),
            symbolButton("minus", "Divider", .divider),
            divider(),
            symbolButton("decrease.indent", "Outdent", .outdent),
            symbolButton("increase.indent", "Indent", .indent),
        ]
    }

    private func setContent(_ views: [UIView]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            stack.addArrangedSubview(view)
        }
        scrollView.setContentOffset(.zero, animated: false)
    }

    // MARK: Buttons

    private func symbolButton(_ symbol: String, _ label: String, _ command: FormatCommand) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = Palette.ink.uiColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onCommand(command)
        })
        button.accessibilityLabel = label
        return button
    }

    private func headingButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "textformat.size")
        configuration.baseForegroundColor = Palette.ink.uiColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: configuration)
        let levels: [(Int, String)] = [(1, "Heading 1"), (2, "Heading 2"), (3, "Heading 3"), (0, "Body Text")]
        button.menu = UIMenu(children: levels.map { level, title in
            UIAction(title: title) { [weak self] _ in self?.onCommand(.heading(level)) }
        })
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "Heading"
        return button
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = Palette.line.uiColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 20),
        ])
        let spacer = UIStackView(arrangedSubviews: [line])
        spacer.isLayoutMarginsRelativeArrangement = true
        spacer.layoutMargins = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        return spacer
    }

    // MARK: Slash commands

    /// Shows the commands that match what is being typed, or the formatting buttons again when there are none.
    func showSlashSuggestions(_ commands: [SlashCommand]) {
        if commands.isEmpty {
            guard showingSlash else { return }
            showingSlash = false
            setContent(formatViews)
            return
        }
        showingSlash = true
        let buttons: [UIView] = commands.prefix(14).map { command in
            var configuration = UIButton.Configuration.tinted()
            configuration.title = command.title
            configuration.baseForegroundColor = Palette.accent.uiColor
            configuration.baseBackgroundColor = Palette.accent.uiColor
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.onSlash(command)
            })
            button.accessibilityLabel = "\(command.title), slash \(command.rawValue)"
            return button
        }
        setContent(buttons)
    }
}
