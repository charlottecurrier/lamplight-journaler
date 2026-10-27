import Foundation

/// A photo placed in the text is a line of its own: `![](photos/NAME.jpg)`. The file sits in the entry's "photos"
/// folder, so the same path works from the entry file in any Markdown app.
///
/// The editor draws the picture where that line is and hides the line itself. The rule that keeps this safe is
/// that a picture line is never mixed with other text. `repaired` holds every edit to it before it is made, and
/// `separated` puts right anything that got through, such as text typed through an input method.
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

    /// The text without picture lines for photos this entry doesn't have, such as ones copied from another entry.
    /// Their files aren't here, so the lines would only show as empty blocks.
    static func removingUnknown(from text: String, known: Set<String>) -> String {
        guard mayContain(text) else { return text }
        let doc = MarkdownDocument(text)
        let unknown = doc.lines.contains { $0.kind == .media && !known.contains(doc.string($0.content)) }
        guard unknown else { return text }
        var kept: [String] = []
        for line in doc.lines where !(line.kind == .media && !known.contains(doc.string(line.content))) {
            kept.append(doc.string(line.range))
        }
        return kept.joined(separator: "\n")
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

    // MARK: Finding pictures anywhere in a line

    /// Every `![](photos/NAME)` in the text, wherever it sits, as UTF-16 ranges.
    private static func tokens(in u: [UInt16]) -> [Range<Int>] {
        let prefix = Array("\(photosFolder)/".utf16)
        var found: [Range<Int>] = []
        var i = 0
        while i + 1 < u.count {
            guard u[i] == 0x21, u[i + 1] == 0x5B else {
                i += 1
                continue
            }
            var k = i + 2
            while k < u.count, u[k] != 0x5D, u[k] != 0x5B, u[k] != 0x0A { k += 1 }
            guard k + 1 < u.count, u[k] == 0x5D, u[k + 1] == 0x28 else {
                i += 2
                continue
            }
            let nameStart = k + 2 + prefix.count
            guard nameStart <= u.count, Array(u[(k + 2)..<nameStart]) == prefix else {
                i += 2
                continue
            }
            var m = nameStart
            var valid = true
            while m < u.count, u[m] != 0x29 {
                switch u[m] {
                case 0x20, 0x2F, 0x28, 0x5B, 0x5D, 0x3C, 0x3E, 0x0A, 0x0D, 0x09: valid = false
                default: break
                }
                if !valid { break }
                m += 1
            }
            if valid, m < u.count, m > nameStart {
                found.append(i..<(m + 1))
                i = m + 1
            } else {
                i += 2
            }
        }
        return found
    }

    /// Where a line break is needed so the picture has its line to itself: before it, and after it. Each is the
    /// span of places it could go, from just beside the picture to past its own spaces. Spaces next to the picture
    /// on its line don't count as text.
    private static func breaks(
        around token: Range<Int>, in u: [UInt16]
    ) -> (before: ClosedRange<Int>?, after: ClosedRange<Int>?) {
        // A picture written inside `code` is code.
        if token.lowerBound > 0, u[token.lowerBound - 1] == 0x60, token.upperBound < u.count, u[token.upperBound] == 0x60 {
            return (nil, nil)
        }
        var left = token.lowerBound
        while left > 0, u[left - 1] == 0x20 { left -= 1 }
        let aloneOnTheLeft = left == 0 || u[left - 1] == 0x0A

        var right = token.upperBound
        while right < u.count, u[right] == 0x20 || u[right] == 0x09 { right += 1 }
        let aloneOnTheRight = right == u.count || u[right] == 0x0A
            || (u[right] == 0x0D && (right + 1 == u.count || u[right + 1] == 0x0A))

        return (
            aloneOnTheLeft ? nil : left...token.lowerBound,
            aloneOnTheRight ? nil : token.upperBound...right
        )
    }

    // MARK: Keeping pictures apart from text

    /// Takes the edit the text view is about to make and returns the edit to make instead, so a picture line stays on
    /// a line of its own:
    /// - Typing or pasting next to a picture starts a new line for the words. A picture pasted into a line goes on
    ///   a line of its own.
    /// - Deleting a line break never joins words onto a picture, or a picture onto words.
    /// - Deleting one character of a picture line removes the whole picture, and a line break with it.
    /// - A change that starts or ends inside a picture line takes the whole line. A caret inside one moves to its end.
    ///
    /// Without pictures, or when nothing needs fixing, it returns the edit it was given.
    static func repaired(_ edit: TextEdit, in text: String) -> TextEdit {
        guard mayContain(text) || mayContain(edit.replacement) else { return edit }
        let doc = MarkdownDocument(text)
        let pictures = doc.lines.filter { $0.kind == .media }.map(\.range)
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

        // Where, in the new text, a line break is needed. Only pictures at the edit are looked at: the ones it
        // leaves beside other text, and any it brings in.
        var result = Array(units)
        result.replaceSubrange(range, with: Array(replacement.utf16))
        let low = range.lowerBound
        let high = range.lowerBound + replacementLength
        var needed = Set<Int>()
        for token in tokens(in: result) {
            let around = breaks(around: token, in: result)
            func inside(_ position: Int) -> Bool { position >= low && position <= high }
            if let before = around.before, let place = [before.lowerBound, before.upperBound].first(where: inside) {
                needed.insert(place)
            }
            if let after = around.after, let place = [after.upperBound, after.lowerBound].first(where: inside) {
                needed.insert(place)
            }
        }

        if range == edit.range && needed.isEmpty { return edit }

        // The breaks lie in or beside the replaced text, so they can be folded into the replacement.
        var fixed = Array(replacement.utf16)
        for position in needed.sorted(by: >) {
            fixed.insert(0x0A, at: min(max(position - low, 0), fixed.count))
        }

        // The selection follows the text it was on: past the expanded range, then past each break before it.
        let lowerShift = range.lowerBound - edit.range.lowerBound
        let replacedEnd = edit.range.lowerBound + replacementLength
        let upperShift = range.count - edit.range.count
        func follow(_ offset: Int) -> Int {
            var moved = offset <= replacedEnd ? offset + lowerShift : offset - upperShift
            moved += needed.filter { $0 < moved }.count
            return max(0, moved)
        }
        let selection = follow(edit.selection.lowerBound)..<max(follow(edit.selection.lowerBound), follow(edit.selection.upperBound))
        return TextEdit(range: range, replacement: String(decoding: fixed, as: UTF16.self), selection: selection)
    }

    /// The natural edit for a keystroke or paste, repaired. Nil when the text view can make it as it is.
    static func guarded(text: String, range: Range<Int>, replacement: String) -> TextEdit? {
        guard mayContain(text) || mayContain(replacement) else { return nil }
        let caret = range.lowerBound + replacement.utf16.count
        let natural = TextEdit(range: range, replacement: replacement, selection: caret..<caret)
        let fixed = repaired(natural, in: text)
        return fixed == natural ? nil : fixed
    }

    /// The edit that puts right any picture that shares its line with text, wherever it is. This is for what got
    /// past `repaired`, such as text typed through an input method, which the text view makes without asking.
    /// Nil when every picture has its own line. `caret` is where the caret is now.
    static func separated(_ text: String, caret: Int) -> TextEdit? {
        guard mayContain(text) else { return nil }
        let doc = MarkdownDocument(text)
        let units = doc.units
        var needed = Set<Int>()
        for token in tokens(in: units) {
            // A picture in a code block is code.
            let kind = doc.lines[doc.lineIndex(containing: token.lowerBound)].kind
            if kind == .code || kind == .fence { continue }
            let around = breaks(around: token, in: units)
            if let before = around.before { needed.insert(before.lowerBound) }
            if let after = around.after { needed.insert(after.upperBound) }
        }
        guard let low = needed.min(), let high = needed.max() else { return nil }

        var piece = Array(units[low..<high])
        for position in needed.sorted(by: >) { piece.insert(0x0A, at: position - low) }
        let moved = caret + needed.filter { $0 < caret }.count
        return TextEdit(range: low..<high, replacement: String(decoding: piece, as: UTF16.self), selection: moved..<moved)
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
