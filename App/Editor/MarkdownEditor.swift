import SwiftUI
import UIKit

// MARK: - The text view

/// A text view that knows a few keyboard shortcuts for formatting.
final class MarkdownUITextView: UITextView {
    var onFormat: ((FormatCommand) -> Void)?
    var onAppearanceChange: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MarkdownUITextView, _) in
            view.onAppearanceChange?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private struct Shortcut {
        let id: String
        let title: String
        let input: String
        let modifiers: UIKeyModifierFlags
        let command: FormatCommand
    }

    private static let shortcuts: [Shortcut] = [
        Shortcut(id: "bold", title: "Bold", input: "b", modifiers: [.command], command: .bold),
        Shortcut(id: "italic", title: "Italic", input: "i", modifiers: [.command], command: .italic),
        Shortcut(id: "strike", title: "Strikethrough", input: "x", modifiers: [.command, .shift], command: .strike),
        Shortcut(id: "highlight", title: "Highlight", input: "h", modifiers: [.command, .shift], command: .highlight),
        Shortcut(id: "link", title: "Link", input: "k", modifiers: [.command], command: .link),
        Shortcut(id: "h1", title: "Heading 1", input: "1", modifiers: [.command, .alternate], command: .heading(1)),
        Shortcut(id: "h2", title: "Heading 2", input: "2", modifiers: [.command, .alternate], command: .heading(2)),
        Shortcut(id: "h3", title: "Heading 3", input: "3", modifiers: [.command, .alternate], command: .heading(3)),
        Shortcut(id: "body", title: "Body Text", input: "0", modifiers: [.command, .alternate], command: .heading(0)),
        Shortcut(id: "bullet", title: "Bulleted List", input: "8", modifiers: [.command, .shift], command: .bullet),
        Shortcut(id: "numbered", title: "Numbered List", input: "7", modifiers: [.command, .shift], command: .numbered),
        Shortcut(id: "checklist", title: "Checklist", input: "l", modifiers: [.command, .shift], command: .checklist),
        Shortcut(id: "indent", title: "Indent", input: "]", modifiers: [.command], command: .indent),
        Shortcut(id: "outdent", title: "Outdent", input: "[", modifiers: [.command], command: .outdent),
        Shortcut(id: "outdentTab", title: "Outdent", input: "\t", modifiers: [.shift], command: .outdent),
    ]

    override var keyCommands: [UIKeyCommand]? {
        guard isEditable else { return super.keyCommands }
        let ours: [UIKeyCommand] = Self.shortcuts.map { shortcut in
            let command = UIKeyCommand(
                title: shortcut.title,
                action: #selector(handleShortcut(_:)),
                input: shortcut.input,
                modifierFlags: shortcut.modifiers,
                propertyList: shortcut.id
            )
            command.discoverabilityTitle = shortcut.title
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
        return ours + (super.keyCommands ?? [])
    }

    @objc private func handleShortcut(_ sender: UIKeyCommand) {
        guard let id = sender.propertyList as? String,
              let shortcut = Self.shortcuts.first(where: { $0.id == id }) else { return }
        onFormat?(shortcut.command)
    }
}

// MARK: - Talking to the editor from SwiftUI

/// Lets the toolbar and menus around the editor change the text: format it, add a template, bring up the keyboard.
final class MarkdownEditorController {
    fileprivate weak var coordinator: MarkdownEditor.Coordinator?

    @MainActor func apply(_ command: FormatCommand) { coordinator?.apply(command) }
    @MainActor func insertTemplate(_ markdown: String) { coordinator?.insertTemplate(markdown) }
    @MainActor func focus() { coordinator?.focus() }
    @MainActor func dismissKeyboard() { coordinator?.dismissKeyboard() }
}

// MARK: - The SwiftUI view

/// Writing and reading with live Markdown.
///
/// `text` is the Markdown as saved in the entry file. Inside the editor, list markers become symbols (see EditorText).
/// Typing "# " makes a heading, "**word**" makes bold, "- " starts a list, and so on.
struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    var isEditable = true
    /// Keeps the line being written near the middle of the screen.
    var isFocusMode = false
    /// Bring up the keyboard when the editor appears.
    var wantsFocus = false
    /// Where the caret starts, as a UTF-16 offset in editor text. Defaults to the end.
    var initialCaret: Int?
    var controller: MarkdownEditorController?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MarkdownUITextView {
        let view = MarkdownUITextView(usingTextLayoutManager: false)
        context.coordinator.configure(view)
        controller?.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: MarkdownUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller?.coordinator = coordinator
        coordinator.update(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownUITextView, context: Context) -> CGSize? {
        // For reading, the text takes the height it needs. For writing, it fills the space it is given.
        guard !isEditable else { return nil }
        let width = proposal.width ?? 600
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    static func dismantleUIView(_ view: MarkdownUITextView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MarkdownEditor

        private weak var textView: MarkdownUITextView?
        private var formatBar: FormatBar?
        private var isApplyingEdit = false
        private var cachedText = ""
        private var cachedDocument: MarkdownDocument?
        private var didFocus = false
        private var pendingInsertion: NSRange?
        private var sizeObserver: NSObjectProtocol?
        private var lastFocusMode = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        // MARK: Setup

        func configure(_ view: MarkdownUITextView) {
            textView = view
            view.delegate = self
            view.backgroundColor = .clear
            view.isEditable = parent.isEditable
            view.isSelectable = true
            view.isScrollEnabled = parent.isEditable
            view.alwaysBounceVertical = parent.isEditable
            view.keyboardDismissMode = .interactive
            view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: parent.isEditable ? 40 : 8, right: 0)
            view.textContainer.lineFragmentPadding = 0
            view.tintColor = Palette.accent.uiColor
            view.linkTextAttributes = [
                .foregroundColor: Palette.accent.uiColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            // Smart dashes would turn "---" into a long dash and break dividers.
            view.smartDashesType = .no
            view.accessibilityLabel = parent.isEditable ? "Entry text" : "Entry"
            if !parent.isEditable {
                view.dataDetectorTypes = .link
            }

            view.onFormat = { [weak self] command in self?.apply(command) }
            view.onAppearanceChange = { [weak self] in self?.restyle() }

            if parent.isEditable {
                let bar = FormatBar()
                bar.onCommand = { [weak self] command in self?.apply(command) }
                bar.onSlash = { [weak self] command in self?.runSlash(command) }
                bar.onDismissKeyboard = { [weak self] in self?.dismissKeyboard() }
                view.inputAccessoryView = bar
                formatBar = bar
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)

            sizeObserver = NotificationCenter.default.addObserver(
                forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restyle() }
            }

            view.text = EditorText.fromMarkdown(parent.text)
            restyle()
        }

        func tearDown() {
            if let sizeObserver {
                NotificationCenter.default.removeObserver(sizeObserver)
            }
            sizeObserver = nil
        }

        /// Called whenever SwiftUI updates the view.
        func update(_ view: MarkdownUITextView) {
            if view.isEditable != parent.isEditable {
                view.isEditable = parent.isEditable
            }

            // The text was changed from outside, such as by a checklist tap in the reader or a new template.
            if EditorText.toMarkdown(view.text) != parent.text {
                let selection = view.selectedRange
                view.text = EditorText.fromMarkdown(parent.text)
                let length = (view.text as NSString).length
                let location = min(selection.location, length)
                view.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
                restyle()
            }

            if parent.isFocusMode != lastFocusMode {
                lastFocusMode = parent.isFocusMode
                updateFocusInsets(view)
                if parent.isFocusMode { centerCaret(view) }
            }

            if parent.wantsFocus, parent.isEditable, !didFocus {
                didFocus = true
                let caret = parent.initialCaret
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    let length = (view.text as NSString).length
                    let location = min(max(caret ?? length, 0), length)
                    view.becomeFirstResponder()
                    view.selectedRange = NSRange(location: location, length: 0)
                    self.restyle()
                    if self.parent.isFocusMode { self.centerCaret(view) }
                }
            }
        }

        // MARK: Styling

        func restyle() {
            guard let view = textView, view.markedTextRange == nil else { return }
            let text = view.text ?? ""
            let document: MarkdownDocument
            if let cached = cachedDocument, cachedText == text {
                document = cached
            } else {
                document = MarkdownDocument(text)
                cachedDocument = document
                cachedText = text
            }
            let editing = parent.isEditable && view.isFirstResponder
            MarkdownStyler.apply(
                to: view.textStorage, document: document, selection: editing ? view.selectedRange : nil
            )
            view.typingAttributes = MarkdownStyler.typingAttributes(document: document, caret: view.selectedRange.location)
        }

        // MARK: Delegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.isEditable, !isApplyingEdit, textView.markedTextRange == nil else { return true }

            let replaced = range.location..<(range.location + range.length)
            if let edit = MarkdownEditing.intercept(text: textView.text, range: replaced, replacement: text) {
                apply(edit)
                return false
            }
            // Pasted or dictated text can be Markdown. It is tidied after it lands.
            if text.utf16.count > 1 {
                pendingInsertion = NSRange(location: range.location, length: text.utf16.count)
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            tidyPastedText(in: textView)
            changed(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingEdit else { return }
            restyle()
            updateSlashSuggestions(textView)
            if parent.isFocusMode { centerCaret(textView) }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            restyle()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            restyle()
        }

        private func tidyPastedText(in view: UITextView) {
            guard let range = pendingInsertion else { return }
            pendingInsertion = nil
            let nsText = view.text as NSString
            guard range.location + range.length <= nsText.length else { return }
            let inserted = nsText.substring(with: range)
            let converted = EditorText.fromMarkdown(inserted)
            guard converted != inserted else { return }
            isApplyingEdit = true
            view.textStorage.replaceCharacters(in: range, with: converted)
            view.selectedRange = NSRange(location: range.location + (converted as NSString).length, length: 0)
            isApplyingEdit = false
        }

        /// The text changed: save it, restyle it, and update the bar.
        private func changed(_ view: UITextView) {
            let markdown = EditorText.toMarkdown(view.text)
            if markdown != parent.text {
                parent.text = markdown
            }
            restyle()
            updateSlashSuggestions(view)
            if parent.isFocusMode { centerCaret(view) }
        }

        // MARK: Edits

        /// Makes an edit the engine asked for, in a way that can be undone.
        func apply(_ edit: TextEdit) {
            guard let view = textView else { return }
            isApplyingEdit = true
            let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
            if let start = view.position(from: view.beginningOfDocument, offset: range.location),
               let end = view.position(from: start, offset: range.length),
               let textRange = view.textRange(from: start, to: end) {
                view.replace(textRange, withText: edit.replacement)
            } else {
                view.textStorage.replaceCharacters(in: range, with: edit.replacement)
            }
            view.selectedRange = NSRange(location: edit.selection.lowerBound, length: edit.selection.count)
            isApplyingEdit = false
            changed(view)
        }

        func apply(_ command: FormatCommand) {
            guard let view = textView, parent.isEditable else { return }
            let selection = view.selectedRange
            let range = selection.location..<(selection.location + selection.length)
            if let edit = MarkdownEditing.apply(command, to: view.text, selection: range) {
                apply(edit)
            }
        }

        func insertTemplate(_ markdown: String) {
            guard let view = textView, parent.isEditable else { return }
            let edit = TemplateText.insertionEdit(
                templateEditorText: EditorText.fromMarkdown(markdown),
                into: view.text,
                caret: view.selectedRange.location
            )
            apply(edit)
            view.becomeFirstResponder()
        }

        func focus() {
            textView?.becomeFirstResponder()
        }

        func dismissKeyboard() {
            textView?.resignFirstResponder()
        }

        // MARK: Slash commands

        private func updateSlashSuggestions(_ view: UITextView) {
            guard let bar = formatBar else { return }
            let selection = view.selectedRange
            guard selection.length == 0 else {
                bar.showSlashSuggestions([])
                return
            }
            bar.showSlashSuggestions(SlashCommand.suggestions(in: view.text, caret: selection.location))
        }

        private func runSlash(_ command: SlashCommand) {
            guard let view = textView else { return }
            let document = MarkdownDocument(view.text)
            guard let token = SlashCommand.typedToken(in: document, caret: view.selectedRange.location),
                  let edit = command.edit(in: document, token: token.range) else { return }
            apply(edit)
        }

        // MARK: Checklist taps

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = textView else { return }
            var point = recognizer.location(in: view)
            point.x -= view.textContainerInset.left
            point.y -= view.textContainerInset.top

            let layout = view.layoutManager
            guard layout.numberOfGlyphs > 0 else { return }
            let glyph = layout.glyphIndex(for: point, in: view.textContainer)
            let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer)
            // Only a tap on the box itself counts, not on the empty space after a short line.
            guard box.insetBy(dx: -10, dy: -6).contains(point) else { return }
            let character = layout.characterIndexForGlyph(at: glyph)

            let selection = view.selectedRange
            guard let edit = MarkdownEditing.toggleCheckbox(
                in: view.text, near: character, keeping: selection.location..<(selection.location + selection.length)
            ) else { return }

            // A checklist can be ticked even while reading. Replace just the symbol, and leave the caret alone.
            isApplyingEdit = true
            view.textStorage.replaceCharacters(
                in: NSRange(location: edit.range.lowerBound, length: edit.range.count), with: edit.replacement
            )
            view.selectedRange = selection
            isApplyingEdit = false
            changed(view)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // MARK: Focus mode

        private func updateFocusInsets(_ view: UITextView) {
            guard view.isScrollEnabled else { return }
            let height = view.bounds.height
            view.contentInset.top = parent.isFocusMode ? height * 0.35 : 0
            view.contentInset.bottom = parent.isFocusMode ? height * 0.45 : 0
        }

        /// Scrolls so the line being written sits a little above the middle of the screen.
        private func centerCaret(_ view: UITextView) {
            guard view.isScrollEnabled, let range = view.selectedTextRange else { return }
            let caret = view.caretRect(for: range.end)
            let height = view.bounds.height
            let wanted = caret.midY - height * 0.4
            let minimum = -view.adjustedContentInset.top
            let maximum = max(minimum, view.contentSize.height + view.adjustedContentInset.bottom - height)
            view.setContentOffset(
                CGPoint(x: view.contentOffset.x, y: min(max(wanted, minimum), maximum)), animated: false
            )
        }

        // MARK: Gestures

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
