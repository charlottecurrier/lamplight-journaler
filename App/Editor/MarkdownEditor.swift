import SwiftUI
import UIKit

// MARK: - The text view

/// Draws what the text itself can't: the thin rule that runs from a section's title to the edge of the page,
/// and the photos placed in the text.
final class RuleLayoutManager: NSLayoutManager {
    /// The picture for a photo's file name, or nil while it is still coming down.
    var mediaImage: ((String) -> UIImage?)?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        drawRules(storage: storage, glyphsToShow: glyphsToShow, origin: origin)
        drawPictures(storage: storage, glyphsToShow: glyphsToShow, origin: origin)
    }

    /// A picture line is as tall as its photo and its own text is hidden. The photo is drawn in that space, as wide
    /// as fits. A photo that hasn't loaded yet is a quiet block the same size.
    private func drawPictures(storage: NSTextStorage, glyphsToShow: NSRange, origin: CGPoint) {
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, glyphRange, _ in
            let characters = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characters.length > 0, characters.location < storage.length,
                  let file = storage.attribute(.mediaFile, at: characters.location, effectiveRange: nil) as? String
            else { return }
            let active = (storage.attribute(.mediaActive, at: characters.location, effectiveRange: nil) as? Bool) ?? false

            // The line is the photo and its padding.
            let box = CGRect(
                x: origin.x + rect.minX, y: origin.y + rect.minY + MediaLayout.padding,
                width: rect.width, height: rect.height - 2 * MediaLayout.padding
            )
            guard box.height > 1 else { return }
            var frame = box
            let radius: CGFloat = 12
            if let image = self.mediaImage?(file), image.size.width > 0, image.size.height > 0 {
                let scale = min(box.width / image.size.width, box.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                frame = CGRect(x: box.midX - size.width / 2, y: box.minY, width: size.width, height: size.height)
                UIGraphicsGetCurrentContext()?.saveGState()
                UIBezierPath(roundedRect: frame, cornerRadius: radius).addClip()
                image.draw(in: frame)
                UIGraphicsGetCurrentContext()?.restoreGState()
            } else {
                Palette.surfaceRaised.uiColor.setFill()
                UIBezierPath(roundedRect: frame, cornerRadius: radius).fill()
            }
            if active {
                let outline = UIBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerRadius: radius)
                outline.lineWidth = 2
                Palette.accent.uiColor.setStroke()
                outline.stroke()
            }
        }
    }

    private func drawRules(storage: NSTextStorage, glyphsToShow: NSRange, origin: CGPoint) {
        let text = storage.string as NSString

        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, usedRect, _, glyphRange, _ in
            let characters = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characters.length > 0, characters.location < storage.length,
                  let color = storage.attribute(.sectionRule, at: characters.location, effectiveRange: nil) as? UIColor
            else { return }

            // One rule per section, on the last line of its title.
            let paragraph = text.paragraphRange(for: NSRange(location: characters.location, length: 0))
            var paragraphEnd = NSMaxRange(paragraph)
            while paragraphEnd > paragraph.location, text.character(at: paragraphEnd - 1) == 0x0A { paragraphEnd -= 1 }
            guard NSMaxRange(characters) >= paragraphEnd else { return }

            let left = origin.x + usedRect.maxX + 12
            let right = origin.x + rect.maxX
            guard right - left > 12 else { return }

            // Level with the middle of the lower-case letters in the title: the line's baseline, less half an x-height.
            // The title is the largest text on the line, since its dashes are hidden at a tiny size.
            var xHeight: CGFloat = 0
            storage.enumerateAttribute(.font, in: characters) { value, _, _ in
                if let font = value as? UIFont { xHeight = max(xHeight, font.xHeight) }
            }
            let baseline = rect.minY + self.location(forGlyphAt: glyphRange.location).y
            let scale = max(UITraitCollection.current.displayScale, 1)
            let y = ((origin.y + baseline - xHeight / 2) * scale).rounded() / scale
            color.setFill()
            UIRectFill(CGRect(x: left, y: y, width: right - left, height: 1 / scale))
        }
    }
}

/// A text view that knows a few keyboard shortcuts for formatting.
final class MarkdownUITextView: UITextView {
    var onFormat: ((FormatCommand) -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onLayout: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MarkdownUITextView, _) in
            view.onAppearanceChange?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    /// The text view draws the caret as tall as the whole line, which includes the space a heading or a section
    /// title has above and below it. That left the caret hanging above the text it belonged to.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let length = textStorage.length
        let caret = offset(from: beginningOfDocument, to: position)
        let text = textStorage.string as NSString
        // A page with no text has no style to take the caret's size from, so the text view draws it at its own small
        // default until a letter is typed. Draw it as tall as a line of body text. Done here, where the caret is
        // sized, so it holds however the page came to be empty.
        if length == 0 {
            rect.size.height = max(rect.height, ceil(MarkdownStyler.bodyFont().lineHeight))
            return rect
        }
        // An empty last line has no text to fit the caret to.
        guard caret >= 0, !(caret == length && text.character(at: length - 1) == 0x0A) else { return rect }
        let index = min(caret, length - 1)
        guard let style = textStorage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle,
              style.paragraphSpacingBefore > 0 || style.paragraphSpacing > 0
        else { return rect }

        let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
        var lineGlyphs = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: &lineGlyphs)
        let line = layoutManager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
        // Space before is left out of the first line of a paragraph, and space after is on its last line. The very
        // first paragraph of the text has no space before it.
        let before = (line.location == paragraph.location && paragraph.location > 0) ? style.paragraphSpacingBefore : 0
        let after = NSMaxRange(line) >= NSMaxRange(paragraph) ? style.paragraphSpacing : 0
        if before + after > 0, rect.height > before + after + 8 {
            rect.origin.y += before
            rect.size.height -= before + after
        }
        return rect
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
    /// Puts photos into the text at the caret, each on a line of its own.
    @MainActor func insertPhotos(_ photos: [PhotoRef]) { coordinator?.insertPhotos(photos) }
}

/// What the editor needs to show the photos placed in the text.
struct MediaContext {
    /// The entry's photos. A picture line in the text names one of them by file name.
    var photos: [PhotoRef]
    /// A photo already loaded, or nil. Used while drawing, so it must be quick.
    var cached: (PhotoRef, CGFloat) -> UIImage?
    /// Loads a photo as an image about this many pixels on its long edge. Nil if it can't be read yet.
    var load: (PhotoRef, CGFloat) async -> UIImage?
    /// Called when a photo in the text is tapped.
    var onOpen: (PhotoRef) -> Void
    /// Changes when files may have finished coming down from iCloud, so photos that failed are tried again.
    var refreshToken: Int
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
    /// When reading, a tap on the text calls this with the tapped spot, as a UTF-16 offset in editor text.
    var onTapToEdit: ((Int) -> Void)?
    /// The photos placed in the text. Without this, a picture line is shown as the plain text it is in the file.
    var media: MediaContext?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MarkdownUITextView {
        // Built with its own text layout, so the layout manager above can draw section rules.
        let storage = NSTextStorage()
        let layoutManager = RuleLayoutManager()
        storage.addLayoutManager(layoutManager)
        // Long entries are laid out as they are shown, not all at once, as in a text view's own layout.
        layoutManager.allowsNonContiguousLayout = true
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = MarkdownUITextView(frame: .zero, textContainer: container)
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
        // Photos in the text are as wide as the page, so their height depends on this width.
        context.coordinator.noteWidth(width, restyleNow: true)
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
        /// The Markdown this view stands for, as last exchanged with SwiftUI. Tells an outside change from our own.
        private var syncedText = ""
        private var styledSignature: StyleSignature?
        private var sizeObserver: NSObjectProtocol?
        private var lastFocusMode = false

        // Photos placed in the text.
        private var photosByFile: [String: PhotoRef] = [:]
        private var aspects: [String: CGFloat] = [:]
        /// Photos put into the text a moment ago, which the entry the editor was given may not list yet.
        private var justInserted: [String: PhotoRef] = [:]
        private var loading = Set<UUID>()
        private var failed = Set<UUID>()
        private var mediaToken = 0
        /// How wide the page is, which is how wide a photo is drawn. Zero until it is known.
        private var mediaWidth: CGFloat = 0
        private var isSnapping = false
        private var lastCaret = 0
        private static let pictureSize: CGFloat = 1600

        /// What the last styling pass looked at. If none of it changed, the text needs no new styling.
        private struct StyleSignature: Equatable {
            var text: String
            var activeLines: [Int]
            var editing: Bool
            var media: MediaLayout?
        }

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
            view.onAppearanceChange = { [weak self] in self?.restyle(force: true) }
            view.onLayout = { [weak self, weak view] in
                guard let self, let view else { return }
                if self.updateFocusInsets(view), self.parent.isFocusMode { self.centerCaret(view) }
                self.noteWidth(view.bounds.width - view.textContainerInset.left - view.textContainerInset.right, restyleNow: false)
            }
            if let layout = view.layoutManager as? RuleLayoutManager {
                layout.mediaImage = { [weak self] file in
                    // Text is drawn on the main thread. If it ever isn't, draw the quiet block rather than trap.
                    guard Thread.isMainThread else { return nil }
                    return MainActor.assumeIsolated { self?.image(forFile: file) }
                }
            }

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
                MainActor.assumeIsolated { self?.restyle(force: true) }
            }

            syncedText = parent.text
            view.text = EditorText.fromMarkdown(parent.text)
            syncMedia()
            restyle(force: true)
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

            // Photos may have been added or loaded since last time, which changes how tall their lines are.
            if syncMedia() { restyle(force: true) }

            // The text was changed from outside, such as by a checklist tap in the reader or a new template.
            if parent.text != syncedText {
                syncedText = parent.text
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
                    self.beginEditing(view, caret: caret, attemptsLeft: 4)
                }
            }
        }

        /// The screen change the view is part of, if one is under way: on a phone, the page sliding in.
        private func transition(around view: UIView) -> UIViewControllerTransitionCoordinator? {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController { return controller.transitionCoordinator }
                responder = current.next
            }
            return nil
        }

        /// Brings up the keyboard. If the view isn't on screen yet, tries again a moment later.
        ///
        /// While the page is still sliding in, it waits for the slide to end. Loading the keyboard is slow the
        /// first time, and doing it mid-slide made the slide stutter on a phone.
        private func beginEditing(_ view: MarkdownUITextView, caret: Int?, attemptsLeft: Int, afterSlide: Bool = false) {
            if !afterSlide, let slide = transition(around: view) {
                let waiting = slide.animate(alongsideTransition: nil) { [weak self, weak view] _ in
                    guard let self, let view, !view.isFirstResponder else { return }
                    self.beginEditing(view, caret: caret, attemptsLeft: attemptsLeft, afterSlide: true)
                }
                // If the slide can't be waited on, don't leave the page without its keyboard.
                if waiting { return }
            }
            let length = (view.text as NSString).length
            let location = min(max(caret ?? length, 0), length)
            if view.becomeFirstResponder() {
                view.selectedRange = NSRange(location: location, length: 0)
                restyle()
                if parent.isFocusMode { centerCaret(view) }
            } else if attemptsLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.beginEditing(view, caret: caret, attemptsLeft: attemptsLeft - 1)
                }
            }
        }

        // MARK: Photos in the text

        /// The text's analysis, kept while the text stays the same.
        private func analysis(for text: String) -> MarkdownDocument {
            if let cached = cachedDocument, cachedText == text { return cached }
            let document = MarkdownDocument(text)
            cachedDocument = document
            cachedText = text
            return document
        }

        /// Where photos in the text are drawn, or nil if this editor has no photos to show. Until the page's width
        /// is known a plausible one is used, so picture lines never show their text for a moment.
        private func mediaLayout() -> MediaLayout? {
            guard parent.media != nil else { return nil }
            return MediaLayout(width: mediaWidth > 1 ? mediaWidth : 600, aspect: aspects)
        }

        /// Takes in the photos SwiftUI last handed over. Returns true if something that changes the layout did.
        @discardableResult
        private func syncMedia() -> Bool {
            guard let media = parent.media else {
                photosByFile = [:]
                aspects = [:]
                return false
            }
            var map = Dictionary(media.photos.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
            for (name, photo) in justInserted {
                if map[name] != nil { justInserted[name] = nil } else { map[name] = photo }
            }
            photosByFile = map
            let newAspects = map.mapValues { CGFloat($0.aspectRatio) }
            var changed = newAspects != aspects
            aspects = newAspects
            if media.refreshToken != mediaToken {
                mediaToken = media.refreshToken
                failed.removeAll()
                invalidatePictures()
                changed = true
            }
            return changed
        }

        /// The page's width changed, such as by turning the iPad. Photos are drawn as wide as the page.
        func noteWidth(_ width: CGFloat, restyleNow: Bool) {
            guard parent.media != nil, width.isFinite, width > 1, abs(width - mediaWidth) > 0.5 else { return }
            mediaWidth = width
            if restyleNow {
                restyle(force: true)
            } else {
                // Called while the view is being laid out, so the text is restyled right after.
                DispatchQueue.main.async { [weak self] in self?.restyle(force: true) }
            }
        }

        /// The loaded image for a photo in the text. While it is still coming, nil, and it is asked for.
        private func image(forFile file: String) -> UIImage? {
            guard let media = parent.media, let photo = photosByFile[file] else { return nil }
            if let image = media.cached(photo, Self.pictureSize) { return image }
            if !loading.contains(photo.id), !failed.contains(photo.id) {
                loading.insert(photo.id)
                Task { @MainActor [weak self] in
                    let image = await media.load(photo, Self.pictureSize)
                    guard let self else { return }
                    self.loading.remove(photo.id)
                    if image == nil { self.failed.insert(photo.id) }
                    self.invalidatePictures()
                }
            }
            return nil
        }

        private func invalidatePictures() {
            guard let view = textView else { return }
            view.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: view.textStorage.length))
        }

        func insertPhotos(_ photos: [PhotoRef]) {
            guard let view = textView, parent.isEditable, !photos.isEmpty else { return }
            for photo in photos {
                justInserted[photo.fileName] = photo
                photosByFile[photo.fileName] = photo
                aspects[photo.fileName] = CGFloat(photo.aspectRatio)
            }
            let edit = MediaLine.insertionEdit(
                fileNames: photos.map(\.fileName), into: view.text, caret: view.selectedRange.location
            )
            apply(edit)
            view.becomeFirstResponder()
            view.scrollRangeToVisible(view.selectedRange)
        }

        /// The text of a picture line is hidden, so the caret and any selection are kept out of it. A caret goes to
        /// the end of the line, or the start if it was moving backwards.
        private func keepSelectionOutOfPictures(_ view: UITextView) {
            defer { lastCaret = view.selectedRange.location }
            guard parent.media != nil, MediaLine.mayContain(view.text) else { return }
            let pictures = analysis(for: view.text).lines.filter { $0.kind == .media }.map(\.range)
            guard !pictures.isEmpty else { return }

            let selection = view.selectedRange
            let start = selection.location
            let end = selection.location + selection.length
            var target: NSRange?
            if selection.length == 0 {
                if let picture = pictures.first(where: { $0.lowerBound < start && start < $0.upperBound }) {
                    target = NSRange(location: start < lastCaret ? picture.lowerBound : picture.upperBound, length: 0)
                }
            } else {
                let newStart = pictures.first(where: { $0.lowerBound < start && start < $0.upperBound })?.lowerBound ?? start
                let newEnd = pictures.first(where: { $0.lowerBound < end && end < $0.upperBound })?.upperBound ?? end
                if newStart != start || newEnd != end {
                    target = NSRange(location: newStart, length: newEnd - newStart)
                }
            }
            guard let target else { return }
            isSnapping = true
            view.selectedRange = target
            isSnapping = false
        }

        /// The photo under a point, if the point is on a picture line.
        private func photo(at location: CGPoint, in view: UITextView) -> PhotoRef? {
            guard parent.media != nil, view.layoutManager.numberOfGlyphs > 0 else { return nil }
            var point = location
            point.x -= view.textContainerInset.left
            point.y -= view.textContainerInset.top
            let layout = view.layoutManager
            let glyph = layout.glyphIndex(for: point, in: view.textContainer)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            guard rect.contains(point) else { return nil }
            let index = layout.characterIndexForGlyph(at: glyph)
            guard index < view.textStorage.length,
                  let file = view.textStorage.attribute(.mediaFile, at: index, effectiveRange: nil) as? String
            else { return nil }
            return photosByFile[file]
        }

        // MARK: Styling

        /// Styles the text. Skipped when neither the text nor the lines the cursor touches have changed.
        func restyle(force: Bool = false) {
            guard let view = textView, view.markedTextRange == nil else { return }
            let text = view.text ?? ""
            // A photo makes its line much taller than a line of text. Laying out only what is on screen guesses at
            // those heights, so scrolling and typing below photos would jump. Text with photos is laid out whole.
            let withPhotos = MediaLine.mayContain(text)
            if view.layoutManager.allowsNonContiguousLayout == withPhotos {
                view.layoutManager.allowsNonContiguousLayout = !withPhotos
            }
            let document = analysis(for: text)
            let editing = parent.isEditable && view.isFirstResponder
            let selection = view.selectedRange
            let range = selection.location..<(selection.location + selection.length)
            let active = editing ? document.lines.indices.filter { document.isActive($0, selection: range) } : []
            let media = mediaLayout()
            let signature = StyleSignature(text: text, activeLines: active, editing: editing, media: media)
            if force || signature != styledSignature {
                let previous = styledSignature
                styledSignature = signature
                if !force, let previous, previous.text == signature.text, previous.media == signature.media {
                    // Only the caret moved. Style the lines it left and the lines it came to, and leave the rest of
                    // the page alone. Styling all of the text again for every key press threw away the layout of the
                    // whole page, which moved the page by itself.
                    let changed = Set(previous.activeLines).symmetricDifference(active).sorted()
                    MarkdownStyler.restyle(
                        lines: changed, in: view.textStorage, document: document, active: Set(active), media: media
                    )
                } else {
                    MarkdownStyler.apply(
                        to: view.textStorage, document: document, selection: editing ? selection : nil, media: media
                    )
                }
            }
        }

        /// Typed text takes the style of the line the caret is on, not of the character before it, which could be
        /// bold, or a hidden marker with no size. This is set when something is about to be typed, and only if the
        /// text view's own choice would differ. It isn't set when the caret moves: setting it makes the text view
        /// scroll to somewhere it isn't going and back, which threw the page off on every arrow press.
        private func setTypingStyle(for view: UITextView, at caret: Int) {
            let wanted = MarkdownStyler.typingAttributes(document: analysis(for: view.text), caret: caret)
            guard !Self.sameTypingStyle(view.typingAttributes, wanted, traits: view.traitCollection) else { return }
            view.typingAttributes = wanted
        }

        /// Whether two sets of typing attributes look the same to someone reading: size, weight and slant, color, and
        /// the marks that stand out (highlight, strike, underline, link, spacing between letters).
        private static func sameTypingStyle(
            _ a: [NSAttributedString.Key: Any], _ b: [NSAttributedString.Key: Any], traits: UITraitCollection
        ) -> Bool {
            if let fa = a[.font] as? UIFont, let fb = b[.font] as? UIFont {
                guard abs(fa.pointSize - fb.pointSize) < 0.01,
                      fa.fontDescriptor.symbolicTraits == fb.fontDescriptor.symbolicTraits,
                      fa.familyName == fb.familyName else { return false }
            } else if (a[.font] == nil) != (b[.font] == nil) {
                return false
            }
            func components(_ color: Any?) -> [CGFloat]? {
                guard let color = color as? UIColor else { return nil }
                var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
                color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                return [red, green, blue, alpha]
            }
            for key in [NSAttributedString.Key.foregroundColor, .backgroundColor] {
                switch (components(a[key]), components(b[key])) {
                case (nil, nil): continue
                case let (x?, y?): if zip(x, y).contains(where: { abs($0 - $1) > 0.01 }) { return false }
                default: return false
                }
            }
            for key in [NSAttributedString.Key.strikethroughStyle, .underlineStyle, .kern, .link] {
                if (a[key] == nil) != (b[key] == nil) { return false }
                if let x = a[key] as? NSNumber, let y = b[key] as? NSNumber, x != y { return false }
            }
            return true
        }

        // MARK: Delegate

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.isEditable, !isApplyingEdit, textView.markedTextRange == nil else { return true }
            setTypingStyle(for: textView, at: range.location)

            let replaced = range.location..<(range.location + range.length)
            // Pasted or dictated text can be Markdown, such as "- [ ] milk". Turn it into editor form as it goes in.
            let replacement = text.utf16.count > 1 ? editorForm(ofPasted: text, at: range.location, in: textView.text) : text
            if let edit = MarkdownEditing.intercept(text: textView.text, range: replaced, replacement: replacement) {
                apply(edit)
                return false
            }
            if replacement != text {
                let caret = range.location + replacement.utf16.count
                apply(TextEdit(range: replaced, replacement: replacement, selection: caret..<caret))
                return false
            }
            return true
        }

        /// A paste lands in the middle of a line unless it starts one. Only lines after the first can be list items then.
        private func editorForm(ofPasted original: String, at location: Int, in current: String) -> String {
            // A photo copied from another entry has no file here, so its line would only be an empty block.
            let text = parent.media == nil ? original : MediaLine.removingUnknown(from: original, known: Set(photosByFile.keys))
            let atLineStart = location == 0 || (current as NSString).character(at: location - 1) == 0x0A
            if atLineStart { return EditorText.fromMarkdown(text) }
            let scalars = text.unicodeScalars
            guard let newline = scalars.firstIndex(of: "\n") else { return text }
            return String(scalars[..<newline]) + EditorText.fromMarkdown(String(scalars[newline...]))
        }

        func textViewDidChange(_ textView: UITextView) {
            changed(textView)
            // The text view scrolls to typed characters itself, but the restyle above can make lines taller.
            if !isApplyingEdit { keepCaretInView(textView) }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingEdit, !isSnapping else { return }
            keepSelectionOutOfPictures(textView)
            restyle()
            updateSlashSuggestions(textView)
            if parent.isFocusMode { centerCaret(textView) }
            // Moving with the arrow keys: the text view scrolls to the caret itself, but it can stop short when the
            // page it has laid out is not as tall as the page will be.
            keepCaretInView(textView, below: 8)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            restyle()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            restyle()
        }

        /// The text changed: save it, restyle it, and update the bar.
        private func changed(_ view: UITextView) {
            // Anything that got past the editing rules, such as text typed through an input method, which the text
            // view makes without asking, is put right here so a photo never shares its line with words.
            if view.markedTextRange == nil, parent.media != nil,
               let fix = MediaLine.separated(view.text, caret: view.selectedRange.location) {
                apply(fix)
                return
            }
            let markdown = EditorText.toMarkdown(view.text)
            syncedText = markdown
            if markdown != parent.text {
                parent.text = markdown
            }
            restyle()
            updateSlashSuggestions(view)
            if parent.isFocusMode { centerCaret(view) }
        }

        // MARK: Edits

        /// Makes an edit the engine asked for, in a way that can be undone.
        func apply(_ requested: TextEdit) {
            guard let view = textView else { return }
            // Whatever asked for this, a picture line never ends up sharing its line with text.
            let edit = MediaLine.repaired(requested, in: view.text)
            isApplyingEdit = true
            let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
            // An edit that changes nothing, such as a Backspace that is refused, only moves the caret.
            if edit.applied(to: view.text) != view.text {
                if let start = view.position(from: view.beginningOfDocument, offset: range.location),
                   let end = view.position(from: start, offset: range.length),
                   let textRange = view.textRange(from: start, to: end) {
                    view.replace(textRange, withText: edit.replacement)
                } else {
                    view.textStorage.replaceCharacters(in: range, with: edit.replacement)
                }
            }
            view.selectedRange = NSRange(location: edit.selection.lowerBound, length: edit.selection.count)
            lastCaret = view.selectedRange.location
            isApplyingEdit = false
            changed(view)
            keepCaretInView(view)
        }

        /// Scrolls just far enough that the caret is on screen. An edit made here, such as Return, takes the place of
        /// the text view's own typing, so the text view doesn't scroll to it. Focus mode places the caret itself.
        private func keepCaretInView(_ view: UITextView, below room: CGFloat = 40) {
            guard view.isScrollEnabled, !parent.isFocusMode else { return }
            // Next turn of the run loop, once the text view has laid out the new line and sized itself to it.
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isScrollEnabled, let range = view.selectedTextRange else { return }
                view.layoutIfNeeded()
                let caret = view.caretRect(for: range.end)
                guard caret.minY.isFinite, caret.maxY.isFinite else { return }
                // The target is worked out here, not by the scroll view, which holds back from content its size
                // doesn't include yet. The text view's size can lag a moment behind the new line.
                let inset = view.adjustedContentInset
                let visibleTop = view.contentOffset.y + inset.top
                let visibleBottom = view.contentOffset.y + view.bounds.height - inset.bottom
                var offset = view.contentOffset.y
                if caret.minY - 12 < visibleTop {
                    offset = caret.minY - 12 - inset.top
                } else if caret.maxY + room > visibleBottom {
                    // After typing, room for the space under the last line, as the text view leaves for a typed character.
                    offset = caret.maxY + room - view.bounds.height + inset.bottom
                }
                offset = max(offset, -inset.top)
                guard abs(offset - view.contentOffset.y) > 0.5 else { return }
                view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: false)
            }
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
            guard selection.length == 0, slashMayBeTyped(in: view) else {
                bar.showSlashSuggestions([])
                return
            }
            bar.showSlashSuggestions(SlashCommand.suggestions(in: view.text, caret: selection.location))
        }

        /// A cheap look back from the caret for a "/" in the current word, so the whole text isn't parsed on every key.
        private func slashMayBeTyped(in view: UITextView) -> Bool {
            let text = view.text as NSString
            var index = min(view.selectedRange.location, text.length)
            while index > 0 {
                let unit = text.character(at: index - 1)
                if unit == 0x2F { return true }
                if unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D { return false }
                index -= 1
            }
            return false
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
            let location = recognizer.location(in: view)
            if tickCheckbox(at: location, in: view) { return }

            // A tap on a photo in the text opens it, whether writing or reading.
            if let photo = photo(at: location, in: view) {
                parent.media?.onOpen(photo)
                return
            }

            // When reading, a tap on the text starts editing there. A tap on a link opens the link instead.
            guard !parent.isEditable, let beginEditing = parent.onTapToEdit else { return }
            if let character = character(at: location, in: view), isLink(at: character, in: view) {
                return
            }
            let position = view.closestPosition(to: location) ?? view.endOfDocument
            beginEditing(view.offset(from: view.beginningOfDocument, to: position))
        }

        private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

        /// True if the character is part of a link: one written in Markdown, or a plain web address.
        private func isLink(at character: Int, in view: UITextView) -> Bool {
            if view.textStorage.attribute(.link, at: character, effectiveRange: nil) != nil { return true }
            guard let detector = Self.linkDetector else { return false }
            let line = (view.text as NSString).lineRange(for: NSRange(location: character, length: 0))
            return detector.matches(in: view.text, options: [], range: line).contains { match in
                character >= match.range.location && character < match.range.location + match.range.length
            }
        }

        /// The character under a point, or nil for empty space beside or below the text.
        private func character(at location: CGPoint, in view: UITextView) -> Int? {
            var point = location
            point.x -= view.textContainerInset.left
            point.y -= view.textContainerInset.top
            let layout = view.layoutManager
            guard layout.numberOfGlyphs > 0 else { return nil }
            let glyph = layout.glyphIndex(for: point, in: view.textContainer)
            let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer)
            // Only a tap on the character itself counts, not on the empty space after a short line.
            guard box.insetBy(dx: -10, dy: -6).contains(point) else { return nil }
            return layout.characterIndexForGlyph(at: glyph)
        }

        /// Ticks or unticks the checklist box at a point. Returns false if there is no box there.
        private func tickCheckbox(at location: CGPoint, in view: UITextView) -> Bool {
            guard let character = character(at: location, in: view) else { return false }
            let selection = view.selectedRange
            guard let edit = MarkdownEditing.toggleCheckbox(
                in: view.text, near: character, keeping: selection.location..<(selection.location + selection.length)
            ) else { return false }

            // A checklist can be ticked even while reading. Replace just the symbol, and leave the caret alone.
            isApplyingEdit = true
            view.textStorage.replaceCharacters(
                in: NSRange(location: edit.range.lowerBound, length: edit.range.count), with: edit.replacement
            )
            view.selectedRange = selection
            isApplyingEdit = false
            changed(view)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return true
        }

        // MARK: Focus mode

        /// Space above and below the text so the line being written can sit near the middle. Follows the view's size.
        /// Returns true if the insets changed.
        @discardableResult
        private func updateFocusInsets(_ view: UITextView) -> Bool {
            guard view.isScrollEnabled else { return false }
            let height = view.bounds.height
            let top: CGFloat = parent.isFocusMode ? height * 0.35 : 0
            let bottom: CGFloat = parent.isFocusMode ? height * 0.45 : 0
            guard abs(view.contentInset.top - top) > 0.5 || abs(view.contentInset.bottom - bottom) > 0.5 else { return false }
            view.contentInset.top = top
            view.contentInset.bottom = bottom
            if !parent.isFocusMode {
                view.contentOffset.y = max(view.contentOffset.y, -view.adjustedContentInset.top)
            }
            return true
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
