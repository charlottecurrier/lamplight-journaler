import UIKit

extension NSAttributedString.Key {
    /// Marks the text of a section line. The value is the color of its rule, which the layout manager draws.
    static let sectionRule = NSAttributedString.Key("lamplight.sectionRule")
    /// Marks a picture line. The value is the photo's file name, and the layout manager draws the photo there.
    static let mediaFile = NSAttributedString.Key("lamplight.mediaFile")
    /// True on a picture line the caret or selection is on, so it is drawn with an outline.
    static let mediaActive = NSAttributedString.Key("lamplight.mediaActive")
}

/// How tall photos placed in the text are drawn: the full width of the page, kept to a sensible height.
struct MediaLayout: Equatable {
    var width: CGFloat
    /// Width over height, by file name.
    var aspect: [String: CGFloat]

    func height(forFile file: String) -> CGFloat {
        let ratio = min(max(aspect[file] ?? 1.5, 0.4), 4)
        return max(ceil(min(width / ratio, width * 1.2)), 80)
    }
}

/// Gives the editor its look: serif fonts, heading sizes, list indents, and which Markdown symbols show.
///
/// Symbols such as `##` and `**` are hidden by making them tiny and clear, but only on lines the cursor isn't on.
/// On the cursor's line they show, dimmed, so the text can always be edited by hand.
@MainActor
enum MarkdownStyler {
    // MARK: Fonts

    private static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, scale: CGFloat = 1) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            .withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: base.pointSize * scale)
    }

    static func bodyFont() -> UIFont {
        serif(.title3)
    }

    static func headingFont(level: Int) -> UIFont {
        switch level {
        case 1: return serif(.title3, weight: .bold, scale: 1.75)
        case 2: return serif(.title3, weight: .bold, scale: 1.45)
        case 3: return serif(.title3, weight: .semibold, scale: 1.25)
        default: return serif(.title3, weight: .semibold, scale: 1.08)
        }
    }

    static func codeFont(relativeTo font: UIFont) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
    }

    private static func styled(_ font: UIFont, bold: Bool, italic: Bool) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// A font so small that characters in it take up no room.
    private static let hiddenFont = UIFont.systemFont(ofSize: 0.01)

    // MARK: Colors

    private static var ink: UIColor { Palette.ink.uiColor }
    private static var secondary: UIColor { Palette.inkSecondary.uiColor }
    private static var tertiary: UIColor { Palette.inkTertiary.uiColor }
    private static var accent: UIColor { Palette.accent.uiColor }
    private static var sage: UIColor { Palette.sage.uiColor }
    private static var raised: UIColor { Palette.surfaceRaised.uiColor }

    /// Highlighted text: a wash of the accent, so it differs from plain text by brightness and not only by color.
    private static var highlight: UIColor {
        UIColor { traits in
            let pair = Palette.accent
            return UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light).withAlphaComponent(0.32)
        }
    }

    // MARK: Paragraphs

    private static func paragraph(
        before: CGFloat = 0, after: CGFloat = 0, headIndent: CGFloat = 0, firstLineHeadIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = UIFontMetrics.default.scaledValue(for: 7)
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        return style
    }

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [.font: bodyFont(), .foregroundColor: ink, .paragraphStyle: paragraph()]
    }

    /// What newly typed text should look like at the caret.
    static func typingAttributes(document: MarkdownDocument, caret: Int) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        guard !document.lines.isEmpty else { return attributes }
        let line = document.lines[document.lineIndex(containing: min(caret, document.units.count))]
        switch line.kind {
        case .heading(let level):
            attributes[.font] = headingFont(level: level)
        case .section:
            attributes[.font] = serif(.subheadline, weight: .semibold)
            attributes[.foregroundColor] = accent
            attributes[.kern] = 1.0
        case .code, .fence:
            attributes[.font] = codeFont(relativeTo: bodyFont())
        default:
            break
        }
        return attributes
    }

    // MARK: Applying

    /// Styles all of the text. `selection` is the caret or selection while editing, or nil when reading,
    /// in which case every line looks finished.
    static func apply(
        to storage: NSTextStorage, document: MarkdownDocument, selection: NSRange?, media: MediaLayout? = nil
    ) {
        guard storage.length == document.units.count else { return }
        let selectionRange = selection.map { $0.location..<($0.location + $0.length) }

        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: NSRange(location: 0, length: storage.length))
        for (index, line) in document.lines.enumerated() {
            let active = selectionRange.map { document.isActive(index, selection: $0) } ?? false
            style(line, active: active, document: document, storage: storage, media: media)
        }
        storage.endEditing()
    }

    private static func nsRange(_ range: Range<Int>) -> NSRange {
        NSRange(location: range.lowerBound, length: range.count)
    }

    private static func style(
        _ line: MDLine, active: Bool, document: MarkdownDocument, storage: NSTextStorage, media: MediaLayout?
    ) {
        let whole = nsRange(line.range)
        var lineFont = bodyFont()

        switch line.kind {
        case .heading(let level):
            lineFont = headingFont(level: level)
            storage.addAttributes(
                [.font: lineFont, .paragraphStyle: paragraph(before: level <= 2 ? 16 : 10, after: 2)],
                range: whole
            )

        case .bullet, .numbered:
            if let marker = line.marker {
                let width = prefixWidth(document.string(line.range.lowerBound..<marker.upperBound), font: lineFont)
                storage.addAttribute(.paragraphStyle, value: paragraph(headIndent: width), range: whole)
                storage.addAttribute(.foregroundColor, value: accent, range: nsRange(marker))
            }

        case .checkbox(let checked):
            if let marker = line.marker {
                let boxFont = serif(.title3, scale: 1.2)
                let width = prefixWidth(document.string(line.range.lowerBound..<marker.upperBound), font: boxFont)
                storage.addAttribute(.paragraphStyle, value: paragraph(headIndent: width), range: whole)
                let glyph = NSRange(location: marker.lowerBound, length: 1)
                storage.addAttributes([.font: boxFont, .foregroundColor: checked ? sage : accent], range: glyph)
                if checked, !line.content.isEmpty {
                    storage.addAttribute(.foregroundColor, value: tertiary, range: nsRange(line.content))
                }
            }

        case .quote:
            storage.addAttributes(
                [.foregroundColor: secondary, .paragraphStyle: paragraph(headIndent: 18, firstLineHeadIndent: 18)],
                range: whole
            )

        case .divider:
            storage.addAttribute(.foregroundColor, value: tertiary, range: whole)

        case .section:
            // A small, spaced title in the accent color. The layout manager draws the rule after it.
            lineFont = serif(.subheadline, weight: .semibold)
            storage.addAttributes([
                .font: lineFont,
                .foregroundColor: accent,
                .kern: 1.0,
                .paragraphStyle: paragraph(before: 24, after: 6),
                .sectionRule: Palette.line.uiColor,
            ], range: whole)

        case .media:
            // Without a place to draw it, the line stays as the plain text it is in the file.
            guard let media else { break }
            // The line's own text is hidden. It is given the height of the photo, and the layout manager draws the
            // photo in that space. The line spacing is left out so the line is exactly the photo's height.
            let file = document.string(line.content)
            let height = media.height(forFile: file)
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            style.paragraphSpacingBefore = 12
            style.paragraphSpacing = 12
            storage.addAttributes([
                .font: hiddenFont,
                .foregroundColor: UIColor.clear,
                .kern: 0,
                .paragraphStyle: style,
                .mediaFile: file,
                .mediaActive: active,
            ], range: whole)
            return

        case .fence:
            storage.addAttributes([.font: codeFont(relativeTo: lineFont), .foregroundColor: tertiary], range: whole)

        case .code:
            storage.addAttributes([.font: codeFont(relativeTo: lineFont), .backgroundColor: raised], range: whole)

        case .blank, .paragraph:
            break
        }

        for inline in line.inlines {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if inline.style.contains(.code) {
                attributes[.font] = codeFont(relativeTo: lineFont)
                attributes[.backgroundColor] = raised
            } else if inline.style.contains(.bold) || inline.style.contains(.italic) {
                attributes[.font] = styled(
                    lineFont, bold: inline.style.contains(.bold), italic: inline.style.contains(.italic)
                )
            }
            if inline.style.contains(.strike) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if inline.style.contains(.highlight) {
                attributes[.backgroundColor] = highlight
            }
            if let link = inline.link, let url = URL(string: link) {
                attributes[.link] = url
                attributes[.foregroundColor] = accent
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            storage.addAttributes(attributes, range: nsRange(inline.range))
        }

        // Markdown symbols: hidden when finished, dimmed while the cursor is on the line.
        var symbols = line.inlineMarkers
        if line.markerHidesWhenInactive, let marker = line.marker { symbols.append(marker) }
        for symbol in symbols {
            if active {
                storage.addAttribute(.foregroundColor, value: tertiary, range: nsRange(symbol))
            } else {
                storage.addAttributes([.font: hiddenFont, .foregroundColor: UIColor.clear, .kern: 0], range: nsRange(symbol))
            }
        }
    }

    /// How far wrapped lines of a list item are indented, so they line up with the first line's text.
    private static func prefixWidth(_ prefix: String, font: UIFont) -> CGFloat {
        ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    }
}
