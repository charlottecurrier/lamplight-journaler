import Foundation

/// One change to the text: replace `range` with `replacement`, then put the selection at `selection`
/// (a position in the new text).
struct TextEdit: Equatable {
    var range: Range<Int>
    var replacement: String
    var selection: Range<Int>

    func applied(to text: String) -> String {
        var units = Array(text.utf16)
        units.replaceSubrange(range, with: Array(replacement.utf16))
        return String(decoding: units, as: UTF16.self)
    }
}

/// Things the format bar, the Format menu and keyboard shortcuts can do.
enum FormatCommand: Equatable {
    /// 1 to 6, or 0 for plain text.
    case heading(Int)
    case bold, italic, strike, highlight, code
    case bullet, numbered, checklist, quote
    case divider
    /// A titled break: "--- Title ---".
    case section
    case link
    case indent, outdent
}

/// The rules of the Markdown editor, written as plain functions so they can be tested without a screen.
enum MarkdownEditing {
    // MARK: As you type

    /// Looks at a change about to be made and, for a few special cases, returns a different edit to make instead:
    /// Return continues or ends a list, "- " becomes a bullet, Backspace removes a list marker, "/todo " runs a command.
    /// Nil means "let the text view do what it normally does".
    static func intercept(
        text: String, range: Range<Int>, replacement: String, context: SlashContext = .current
    ) -> TextEdit? {
        if let edit = listRules(text: text, range: range, replacement: replacement, context: context) { return edit }
        // Whatever else is typed, deleted or pasted must not mix a picture with other text.
        return MediaLine.guarded(text: text, range: range, replacement: replacement)
    }

    private static func listRules(
        text: String, range: Range<Int>, replacement: String, context: SlashContext
    ) -> TextEdit? {
        let isReturn = replacement == "\n" && range.isEmpty
        let isSpace = replacement == " " && range.isEmpty
        let isBackspace = replacement.isEmpty && range.count == 1
        let isTab = replacement == "\t" && range.isEmpty
        // Most keystrokes are ordinary letters. Don't read the whole document for those.
        guard isReturn || isSpace || isBackspace || isTab else { return nil }

        let doc = MarkdownDocument(text)
        if isReturn { return returnKey(doc, caret: range.lowerBound) }
        if isSpace { return spaceKey(doc, caret: range.lowerBound, context: context) }
        if isBackspace { return backspace(doc, caret: range.upperBound) }
        return tab(doc, caret: range.lowerBound)
    }

    private static func nextMarker(for line: MDLine) -> String {
        switch line.kind {
        case .bullet: return EditorGlyph.bulletString + " "
        case .checkbox: return EditorGlyph.uncheckedString + " "
        case .numbered(let number): return "\(number + 1). "
        default: return "> "
        }
    }

    private static func returnKey(_ doc: MarkdownDocument, caret: Int) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: caret)]
        guard let marker = line.marker else { return nil }
        switch line.kind {
        case .bullet, .checkbox, .numbered, .quote: break
        default: return nil
        }
        guard caret >= marker.upperBound else { return nil }

        let isEmptyItem = doc.string(line.content).trimmingCharacters(in: .whitespaces).isEmpty
        if isEmptyItem {
            // Return on an empty item ends the list.
            let start = line.range.lowerBound
            return TextEdit(range: start..<line.range.upperBound, replacement: "", selection: start..<start)
        }
        guard caret > marker.upperBound else { return nil }
        let insertion = "\n" + String(repeating: " ", count: line.indent) + nextMarker(for: line)
        let after = caret + insertion.utf16.count
        return TextEdit(range: caret..<caret, replacement: insertion, selection: after..<after)
    }

    private static func spaceKey(_ doc: MarkdownDocument, caret: Int, context: SlashContext) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: caret)]
        let indentEnd = line.range.lowerBound + line.indent
        switch line.kind {
        case .paragraph:
            // "-", "*" or "+" at the start of a line, then a space: a bullet.
            if caret == indentEnd + 1, [0x2D, 0x2A, 0x2B].contains(doc.units[indentEnd]) {
                let marker = EditorGlyph.bulletString + " "
                let after = indentEnd + marker.utf16.count
                return TextEdit(range: indentEnd..<caret, replacement: marker, selection: after..<after)
            }
        case .bullet:
            // "- []" or "- [ ]" then a space: a checklist item. "- [x]": a checked one.
            if caret == line.range.upperBound {
                let typed = doc.string(line.content.lowerBound..<caret)
                var glyph: String?
                if typed == "[]" || typed == "[ ]" { glyph = EditorGlyph.uncheckedString }
                if typed == "[x]" || typed == "[X]" { glyph = EditorGlyph.checkedString }
                if let glyph {
                    let marker = glyph + " "
                    let after = indentEnd + marker.utf16.count
                    return TextEdit(range: indentEnd..<caret, replacement: marker, selection: after..<after)
                }
            }
        case .blank, .divider, .fence, .code:
            return nil
        default:
            break
        }
        // A slash command: "/todo" and a space.
        guard let token = SlashCommand.typedToken(in: doc, caret: caret),
              let command = SlashCommand(rawValue: token.name.lowercased()),
              let edit = command.edit(in: doc, token: token.range, context: context) else { return nil }
        // The space the person typed is not inserted: the command replaces the "/word" instead.
        return edit
    }

    private static func backspace(_ doc: MarkdownDocument, caret: Int) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: caret)]
        guard let marker = line.marker, marker.upperBound == caret else { return nil }
        switch line.kind {
        case .bullet, .checkbox, .numbered, .quote, .heading:
            // Backspace right after a marker removes the whole marker, not just its space.
            return TextEdit(range: marker, replacement: "", selection: marker.lowerBound..<marker.lowerBound)
        default:
            return nil
        }
    }

    private static func tab(_ doc: MarkdownDocument, caret: Int) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: caret)]
        guard line.kind.isListItem else { return nil }
        let start = line.range.lowerBound
        return TextEdit(range: start..<start, replacement: "  ", selection: (caret + 2)..<(caret + 2))
    }

    // MARK: Format commands

    static func apply(_ command: FormatCommand, to text: String, selection: Range<Int>) -> TextEdit? {
        let doc = MarkdownDocument(text)
        switch command {
        case .bold, .italic, .strike, .highlight, .code, .link:
            // A section's title is plain text, so styling marks would only show up as stray symbols.
            // A picture line is not text at all.
            let kind = doc.lines[doc.lineIndex(containing: selection.lowerBound)].kind
            if kind == .section || kind == .media { return nil }
        default:
            break
        }
        switch command {
        case .heading(let level):
            return setHeading(doc, level: max(0, min(6, level)), selection: selection)
        case .bold: return toggleInline("**", text: text, selection: selection)
        case .italic: return toggleInline("*", text: text, selection: selection)
        case .strike: return toggleInline("~~", text: text, selection: selection)
        case .highlight: return toggleInline("==", text: text, selection: selection)
        case .code: return toggleInline("`", text: text, selection: selection)
        case .bullet:
            return toggleBlock(doc, selection: selection, matches: { $0 == .bullet }) { _ in
                EditorGlyph.bulletString + " "
            }
        case .checklist:
            return toggleBlock(doc, selection: selection, matches: {
                if case .checkbox = $0 { return true }
                return false
            }) { _ in EditorGlyph.uncheckedString + " " }
        case .numbered:
            return toggleBlock(doc, selection: selection, matches: {
                if case .numbered = $0 { return true }
                return false
            }) { index in "\(index + 1). " }
        case .quote:
            return toggleBlock(doc, selection: selection, matches: { $0 == .quote }) { _ in "> " }
        case .divider:
            return insertDivider(doc, selection: selection)
        case .section:
            return toggleSection(doc, selection: selection)
        case .link:
            return makeLink(text: text, selection: selection)
        case .indent:
            return shiftIndent(doc, selection: selection, by: 2)
        case .outdent:
            return shiftIndent(doc, selection: selection, by: -2)
        }
    }

    /// Lines the format commands may rewrite. Code, dividers and blank lines are left alone.
    private static func canRewrite(_ line: MDLine) -> Bool {
        switch line.kind {
        case .blank, .divider, .section, .media, .fence, .code: return false
        default: return true
        }
    }

    /// Rewrites each line a selection touches. `transform` gets the line and its position among the rewritten
    /// lines, and returns the new text and the length of everything before the content.
    private static func rewriteLines(
        _ doc: MarkdownDocument,
        selection: Range<Int>,
        transform: (MDLine, Int) -> (text: String, prefixLength: Int)?
    ) -> TextEdit {
        let indexes = doc.lineIndexes(touching: selection)
        let firstLine = doc.lines[indexes.lowerBound]
        let lastLine = doc.lines[indexes.upperBound]
        let block = firstLine.range.lowerBound..<lastLine.range.upperBound

        var pieces: [String] = []
        var newLength = 0
        var caretAfter: Int?
        var position = 0
        let caretIndex = doc.lineIndex(containing: selection.lowerBound)
        for index in indexes {
            let line = doc.lines[index]
            var text = doc.string(line.range)
            var prefix = line.content.lowerBound - line.range.lowerBound
            if canRewrite(line), let result = transform(line, position) {
                text = result.text
                prefix = result.prefixLength
                position += 1
            }
            if selection.isEmpty, index == caretIndex {
                let inside = max(0, selection.lowerBound - line.content.lowerBound)
                caretAfter = block.lowerBound + newLength + prefix + inside
            }
            pieces.append(text)
            newLength += text.utf16.count + 1
        }
        let joined = pieces.joined(separator: "\n")
        let selectionAfter: Range<Int>
        if let caret = caretAfter {
            selectionAfter = caret..<caret
        } else {
            selectionAfter = block.lowerBound..<(block.lowerBound + joined.utf16.count)
        }
        return TextEdit(range: block, replacement: joined, selection: selectionAfter)
    }

    private static func setHeading(_ doc: MarkdownDocument, level: Int, selection: Range<Int>) -> TextEdit? {
        let indexes = doc.lineIndexes(touching: selection)
        let targets = indexes.map { doc.lines[$0] }.filter(canRewrite)
        guard !targets.isEmpty else { return nil }
        let alreadyThatLevel = targets.allSatisfy { $0.kind == .heading(level: level) }
        let newLevel = (level == 0 || alreadyThatLevel) ? 0 : level
        return rewriteLines(doc, selection: selection) { line, _ in
            let prefix = newLevel > 0 ? String(repeating: "#", count: newLevel) + " " : ""
            return (prefix + doc.string(line.content), prefix.utf16.count)
        }
    }

    private static func toggleBlock(
        _ doc: MarkdownDocument,
        selection: Range<Int>,
        matches: (MDLineKind) -> Bool,
        marker: (Int) -> String
    ) -> TextEdit? {
        let indexes = doc.lineIndexes(touching: selection)
        let targets = indexes.map { doc.lines[$0] }.filter(canRewrite)
        guard !targets.isEmpty else { return nil }
        let allAlready = targets.allSatisfy { matches($0.kind) }
        return rewriteLines(doc, selection: selection) { line, position in
            let keepsIndent = line.kind == .paragraph || line.kind.isListItem
            let indent = keepsIndent ? String(repeating: " ", count: line.indent) : ""
            let prefix = allAlready ? indent : indent + marker(position)
            return (prefix + doc.string(line.content), prefix.utf16.count)
        }
    }

    private static func shiftIndent(_ doc: MarkdownDocument, selection: Range<Int>, by amount: Int) -> TextEdit? {
        let indexes = doc.lineIndexes(touching: selection)
        guard indexes.contains(where: { doc.lines[$0].kind.isListItem }) else { return nil }
        let block = doc.lines[indexes.lowerBound].range.lowerBound..<doc.lines[indexes.upperBound].range.upperBound

        var pieces: [String] = []
        var caretAfter = selection.lowerBound
        for index in indexes {
            let line = doc.lines[index]
            var text = doc.string(line.range)
            if line.kind.isListItem {
                let newIndent = max(0, min(8, line.indent + amount))
                let rest = doc.string((line.range.lowerBound + line.indent)..<line.range.upperBound)
                text = String(repeating: " ", count: newIndent) + rest
                if selection.isEmpty {
                    // Keep the caret on the same character, even though the line moved.
                    caretAfter = max(line.range.lowerBound, selection.lowerBound + (newIndent - line.indent))
                }
            }
            pieces.append(text)
        }
        let joined = pieces.joined(separator: "\n")
        let selectionAfter = selection.isEmpty
            ? caretAfter..<caretAfter
            : block.lowerBound..<(block.lowerBound + joined.utf16.count)
        return TextEdit(range: block, replacement: joined, selection: selectionAfter)
    }

    /// Makes the line a section, or turns a section back into plain text. A blank line becomes an empty section
    /// with the caret where the title goes.
    private static func toggleSection(_ doc: MarkdownDocument, selection: Range<Int>) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: selection.lowerBound)]
        switch line.kind {
        case .fence, .code, .divider, .media:
            return nil
        case .section:
            let title = doc.string(line.content)
            let caret = line.range.lowerBound + title.utf16.count
            return TextEdit(range: line.range, replacement: title + lineEnding(doc, line), selection: caret..<caret)
        case .blank:
            let caret = line.range.lowerBound + 4
            return TextEdit(range: line.range, replacement: "---  ---", selection: caret..<caret)
        default:
            let title = doc.string(line.content).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let replacement = "--- \(title) ---"
            let caret = line.range.lowerBound + replacement.utf16.count - 4
            return TextEdit(
                range: line.range, replacement: replacement + lineEnding(doc, line), selection: caret..<caret
            )
        }
    }

    /// The carriage return a line ends with, if it has one (a Windows line ending), so it isn't lost.
    private static func lineEnding(_ doc: MarkdownDocument, _ line: MDLine) -> String {
        line.range.upperBound > line.range.lowerBound && doc.units[line.range.upperBound - 1] == 0x0D ? "\r" : ""
    }

    private static func insertDivider(_ doc: MarkdownDocument, selection: Range<Int>) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: selection.upperBound)]
        if line.kind == .blank {
            let after = line.range.lowerBound + 4
            return TextEdit(range: line.range, replacement: "---\n", selection: after..<after)
        }
        let end = line.range.upperBound
        return TextEdit(range: end..<end, replacement: "\n---\n", selection: (end + 5)..<(end + 5))
    }

    // MARK: Inline

    private static func isWordUnit(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) || unit >= 0x80
    }

    /// The selection, or the word the caret is in or next to.
    private static func targetRange(_ units: [UInt16], selection: Range<Int>) -> Range<Int> {
        guard selection.isEmpty else { return selection }
        var start = selection.lowerBound
        var end = start
        while start > 0, isWordUnit(units[start - 1]) { start -= 1 }
        while end < units.count, isWordUnit(units[end]) { end += 1 }
        return start..<end
    }

    private static func toggleInline(_ delimiter: String, text: String, selection: Range<Int>) -> TextEdit {
        let units = Array(text.utf16)
        let marker = Array(delimiter.utf16)
        let target = targetRange(units, selection: selection)

        var before = 0
        while target.lowerBound - before - 1 >= 0, units[target.lowerBound - before - 1] == marker[0] { before += 1 }
        var after = 0
        while target.upperBound + after < units.count, units[target.upperBound + after] == marker[0] { after += 1 }
        let run = min(before, after)

        let wrapped: Bool
        switch delimiter {
        case "*": wrapped = run == 1 || run == 3 // a single * is italic; ** is bold; *** is both
        case "**": wrapped = run >= 2
        default: wrapped = run >= marker.count
        }

        let inner = String(decoding: units[target], as: UTF16.self)
        if wrapped {
            let range = (target.lowerBound - marker.count)..<(target.upperBound + marker.count)
            let start = target.lowerBound - marker.count
            return TextEdit(range: range, replacement: inner, selection: start..<(start + inner.utf16.count))
        }
        let start = target.lowerBound + marker.count
        return TextEdit(
            range: target,
            replacement: delimiter + inner + delimiter,
            selection: start..<(start + inner.utf16.count)
        )
    }

    private static func makeLink(text: String, selection: Range<Int>) -> TextEdit {
        let units = Array(text.utf16)
        let target = targetRange(units, selection: selection)
        if target.isEmpty {
            let replacement = "[link](url)"
            return TextEdit(
                range: target, replacement: replacement,
                selection: (target.lowerBound + 1)..<(target.lowerBound + 5)
            )
        }
        let inner = String(decoding: units[target], as: UTF16.self)
        let urlStart = target.lowerBound + 1 + inner.utf16.count + 2
        return TextEdit(range: target, replacement: "[\(inner)](url)", selection: urlStart..<(urlStart + 3))
    }

    // MARK: Checklist taps

    /// Flips a checklist item when its box is tapped. `offset` can be anywhere in the marker ("☐ ").
    static func toggleCheckbox(in text: String, near offset: Int, keeping selection: Range<Int>) -> TextEdit? {
        let doc = MarkdownDocument(text)
        guard offset >= 0, offset <= doc.units.count else { return nil }
        let line = doc.lines[doc.lineIndex(containing: offset)]
        guard case .checkbox(let checked) = line.kind, let marker = line.marker,
              offset >= marker.lowerBound, offset < marker.upperBound else { return nil }
        let glyph = checked ? EditorGlyph.uncheckedString : EditorGlyph.checkedString
        return TextEdit(range: marker.lowerBound..<(marker.lowerBound + 1), replacement: glyph, selection: selection)
    }
}
