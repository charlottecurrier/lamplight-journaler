import Foundation

/// A photo placed in the text is a line of its own: `![](photos/NAME.jpg)`. The file sits in the entry's "photos"
/// folder, so the same path works from the entry file in any Markdown app.
///
/// The editor draws the picture where that line is and hides the line itself. The rule that keeps this safe is
/// that a picture line is never mixed with other text, and `repaired` holds the editor to it.
enum MediaLine {
    static let photosFolder = "photos"

    static func markdown(fileName: String) -> String {
        "![](\(photosFolder)/\(fileName))"
    }

    /// A cheap test, before any parsing, for text that might hold a picture line.
    static func mayContain(_ text: String) -> Bool {
        text.range(of: "](\(photosFolder)/") != nil
    }

    /// The file names of the pictures in the text, in the order they appear.
    static func fileNames(in markdown: String) -> [String] {
        guard mayContain(markdown) else { return [] }
        let doc = MarkdownDocument(markdown)
        return doc.lines.compactMap { $0.kind == .media ? doc.string($0.content) : nil }
    }

    /// The text without its picture lines, for places that can only show words. Runs of blank lines left behind
    /// are tidied.
    static func stripped(_ markdown: String) -> String {
        guard mayContain(markdown) else { return markdown }
        let doc = MarkdownDocument(markdown)
        var kept: [String] = []
        for line in doc.lines where line.kind != .media {
            kept.append(doc.string(line.range))
        }
        var result = kept.joined(separator: "\n")
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Inserting

    /// The edit that puts pictures in the text at `caret`. Each gets a line of its own, and the caret ends on the
    /// empty line after them, ready to keep writing.
    static func insertionEdit(fileNames: [String], into text: String, caret: Int) -> TextEdit {
        let doc = MarkdownDocument(text)
        let at = max(0, min(caret, doc.units.count))
        let index = doc.lineIndex(containing: at)
        let line = doc.lines[index]
        let pictures = fileNames.map { markdown(fileName: $0) }.joined(separator: "\n")
        let length = pictures.utf16.count

        func edit(_ range: Range<Int>, _ replacement: String, caretAt offset: Int) -> TextEdit {
            let position = range.lowerBound + offset
            return TextEdit(range: range, replacement: replacement, selection: position..<position)
        }

        if line.kind == .blank {
            // The empty line becomes the pictures, and an empty line is left after them.
            return edit(line.range, pictures + "\n", caretAt: length + 1)
        }
        if line.kind == .media || at == line.range.upperBound {
            // After the line it is on. An empty line that is already there next is used as the one to write on.
            let end = line.range.upperBound
            let nextIsBlank = index + 1 < doc.lines.count && doc.lines[index + 1].kind == .blank
            return edit(end..<end, "\n" + pictures + (nextIsBlank ? "" : "\n"), caretAt: length + 2)
        }
        if at == line.range.lowerBound {
            // Before it.
            return edit(at..<at, pictures + "\n", caretAt: length + 1)
        }
        // In the middle of a line: split it around the pictures.
        return edit(at..<at, "\n" + pictures + "\n", caretAt: length + 2)
    }

    // MARK: Keeping pictures apart from text

    /// Takes the edit the text view is about to make and returns the edit to make instead, so a picture line stays on
    /// a line of its own:
    /// - Typing next to a picture starts a new line for the words.
    /// - Deleting a line break never joins words onto a picture, or a picture onto words.
    /// - Deleting one character of a picture line removes the whole picture, and a line break with it.
    /// - A change that starts or ends inside a picture line takes the whole line. A caret inside one moves to its end.
    ///
    /// Without picture lines, or when nothing needs fixing, it returns the edit it was given.
    static func repaired(_ edit: TextEdit, in text: String) -> TextEdit {
        guard mayContain(text) else { return edit }
        let doc = MarkdownDocument(text)
        let pictures = doc.lines.filter { $0.kind == .media }.map(\.range)
        guard !pictures.isEmpty else { return edit }
        let units = doc.units

        var range = edit.range
        let replacement = edit.replacement
        let replacementLength = replacement.utf16.count

        // One character deleted from inside a picture line.
        if replacement.isEmpty, range.count == 1,
           let picture = pictures.first(where: { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }) {
            let removal: Range<Int>
            if picture.lowerBound > 0 {
                removal = (picture.lowerBound - 1)..<picture.upperBound
            } else if picture.upperBound < units.count {
                removal = picture.lowerBound..<(picture.upperBound + 1)
            } else {
                removal = picture
            }
            return TextEdit(range: removal, replacement: "", selection: removal.lowerBound..<removal.lowerBound)
        }

        // A caret inside a picture line goes to its end. A change cutting into one takes the whole line.
        if range.isEmpty,
           let picture = pictures.first(where: { $0.lowerBound < range.lowerBound && range.lowerBound < $0.upperBound }) {
            range = picture.upperBound..<picture.upperBound
        }
        for picture in pictures where range.lowerBound < picture.upperBound && picture.lowerBound < range.upperBound {
            range = min(range.lowerBound, picture.lowerBound)..<max(range.upperBound, picture.upperBound)
        }

        // Where, in the new text, a line break is needed so that no picture shares its line.
        var result = Array(units)
        result.replaceSubrange(range, with: Array(replacement.utf16))
        let delta = replacementLength - range.count
        var breaks = Set<Int>()
        for picture in pictures {
            let replaced = !picture.isEmpty && picture.lowerBound >= range.lowerBound && picture.upperBound <= range.upperBound
            if replaced { continue }
            let before = picture.upperBound <= range.lowerBound
            let after = picture.lowerBound >= range.upperBound
            guard before || after else { continue }
            let start = before ? picture.lowerBound : picture.lowerBound + delta
            let end = start + picture.count
            if start > 0, result[start - 1] != 0x0A { breaks.insert(start) }
            if end < result.count, result[end] != 0x0A { breaks.insert(end) }
        }

        if range == edit.range && breaks.isEmpty { return edit }

        // The breaks lie in or beside the replaced text, so they can be folded into the replacement.
        var fixed = Array(replacement.utf16)
        for position in breaks.sorted(by: >) {
            fixed.insert(0x0A, at: min(max(position - range.lowerBound, 0), fixed.count))
        }

        // The selection follows the text it was on: past the expanded range, then past each break before it.
        let lowerShift = range.lowerBound - edit.range.lowerBound
        let replacedEnd = edit.range.lowerBound + replacementLength
        let upperShift = range.count - edit.range.count
        func follow(_ offset: Int) -> Int {
            var moved = offset <= replacedEnd ? offset + lowerShift : offset - upperShift
            moved += breaks.filter { $0 < moved }.count
            return max(0, moved)
        }
        let selection = follow(edit.selection.lowerBound)..<max(follow(edit.selection.lowerBound), follow(edit.selection.upperBound))
        return TextEdit(range: range, replacement: String(decoding: fixed, as: UTF16.self), selection: selection)
    }

    /// The natural edit for a keystroke or paste, repaired. Nil when the text view can make it as it is.
    static func guarded(text: String, range: Range<Int>, replacement: String) -> TextEdit? {
        guard mayContain(text) else { return nil }
        let caret = range.lowerBound + replacement.utf16.count
        let natural = TextEdit(range: range, replacement: replacement, selection: caret..<caret)
        let fixed = repaired(natural, in: text)
        return fixed == natural ? nil : fixed
    }
}

// MARK: - Entries

extension Entry {
    /// The file names of the photos placed in the text, in the order they appear.
    var placedFileNames: [String] { MediaLine.fileNames(in: body) }

    /// Photos that are not in the text. Entries from before photos could be placed show them above the text.
    var unplacedPhotos: [PhotoRef] {
        let placed = Set(placedFileNames)
        return placed.isEmpty ? photos : photos.filter { !placed.contains($0.fileName) }
    }

    /// Every photo in reading order: the ones in the text as they appear, then the rest.
    var orderedPhotos: [PhotoRef] {
        let byFile = Dictionary(photos.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [PhotoRef] = []
        for name in placedFileNames where seen.insert(name).inserted {
            if let photo = byFile[name] { result.append(photo) }
        }
        let placed = Set(result.map(\.id))
        result.append(contentsOf: photos.filter { !placed.contains($0.id) })
        return result
    }
}
