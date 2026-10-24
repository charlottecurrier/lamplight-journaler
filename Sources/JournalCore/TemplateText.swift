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

    /// Removes template headings nobody wrote under, when an entry is finished.
    ///
    /// A heading goes only if its text is one of the template's headings and everything under it, up to the next
    /// heading of the same or a higher level, is blank or more template headings. Anything the person wrote stays
    /// exactly as written. Returns `body` unchanged when there is nothing to remove.
    static func removingEmptyHeadings(from body: String, template templateBody: String) -> String {
        let template = MarkdownDocument(templateBody)
        var known = Set<String>()
        for line in template.lines {
            if case .heading(let level) = line.kind {
                known.insert(headingKey(level, template.string(line.content)))
            }
        }
        guard !known.isEmpty else { return body }

        let doc = MarkdownDocument(body)
        func isBlank(_ line: MDLine) -> Bool {
            doc.units[line.range].allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
        }
        func isTemplateHeading(_ line: MDLine) -> Bool {
            guard case .heading(let level) = line.kind else { return false }
            return known.contains(headingKey(level, doc.string(line.content)))
        }

        var removed = Set<Int>()
        for (index, line) in doc.lines.enumerated() {
            guard case .heading(let level) = line.kind, isTemplateHeading(line) else { continue }
            var end = index + 1
            var empty = true
            while end < doc.lines.count {
                let next = doc.lines[end]
                if case .heading(let nextLevel) = next.kind {
                    if nextLevel <= level { break }
                    if !isTemplateHeading(next) { empty = false; break }
                } else if !isBlank(next) {
                    empty = false
                    break
                }
                end += 1
            }
            if empty { removed.formUnion(index..<end) }
        }
        guard !removed.isEmpty else { return body }

        // Keep the rest, without leaving a gap of blank lines where something was taken out.
        var kept: [String] = []
        var afterRemoval = false
        for (index, line) in doc.lines.enumerated() {
            if removed.contains(index) {
                afterRemoval = true
                continue
            }
            if afterRemoval, isBlank(line), kept.last.map({ $0.allSatisfy(\.isWhitespace) }) ?? true {
                continue
            }
            afterRemoval = false
            kept.append(doc.string(line.range))
        }
        let newline = body.contains("\r\n") ? "\r\n" : "\n"
        var result = kept.joined(separator: "\n")
        while let last = result.last, last.isWhitespace || last.isNewline { result.removeLast() }
        return result.isEmpty ? "" : result + newline
    }

    private static func headingKey(_ level: Int, _ text: String) -> String {
        "\(level) " + text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
