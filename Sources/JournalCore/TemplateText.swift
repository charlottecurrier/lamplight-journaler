import Foundation

enum TemplateText {
    /// Where the caret goes in a new entry made from a template: the first blank line under the first heading,
    /// so the person can start typing straight away. With no heading, the end of the text.
    /// `editorText` is in editor form (see EditorText), and the result is a UTF-16 offset in it.
    static func initialCaret(inEditorText editorText: String) -> Int {
        let doc = MarkdownDocument(editorText)
        guard let heading = doc.lines.firstIndex(where: {
            if case .heading = $0.kind { return true }
            return false
        }) else {
            return doc.units.count
        }
        let next = heading + 1
        if next < doc.lines.count, doc.lines[next].kind == .blank {
            return doc.lines[next].range.lowerBound
        }
        return doc.lines[heading].range.upperBound
    }

    /// Adds a template's text to an entry that already has some. A blank line is kept between them.
    /// Returns the edit to make at `caret`.
    static func insertionEdit(templateEditorText: String, into text: String, caret: Int) -> TextEdit {
        let units = Array(text.utf16)
        let safeCaret = min(max(caret, 0), units.count)
        let before = String(decoding: units[0..<safeCaret], as: UTF16.self)
        let after = String(decoding: units[safeCaret...], as: UTF16.self)

        var lead = ""
        if !before.isEmpty {
            if before.hasSuffix("\n\n") { lead = "" } else if before.hasSuffix("\n") { lead = "\n" } else { lead = "\n\n" }
        }
        var trail = ""
        if !after.isEmpty, !templateEditorText.hasSuffix("\n") { trail = "\n" }

        let insertion = lead + templateEditorText + trail
        let caretAfter = safeCaret + lead.utf16.count + initialCaret(inEditorText: templateEditorText)
        return TextEdit(range: safeCaret..<safeCaret, replacement: insertion, selection: caretAfter..<caretAfter)
    }
}
