import Foundation

/// Converts between the Markdown in the entry file and the text shown in the editor.
///
/// In the file, lists use plain Markdown: "- item", "- [ ] task", "- [x] done".
/// In the editor, those markers are real symbols ("• ", "☐ ", "☑ ") so they draw correctly
/// and a checklist box can be tapped. Everything else is the same in both.
///
/// Converting there and back gives the same Markdown, except that "* " and "+ " bullets come back as "- ",
/// "[X]" as "[x]", and Windows line endings as plain ones.
enum EditorText {
    private static let dash: UInt16 = 0x2D
    private static let star: UInt16 = 0x2A
    private static let plus: UInt16 = 0x2B
    private static let space: UInt16 = 0x20
    private static let fence: [UInt16] = [0x60, 0x60, 0x60]

    static func fromMarkdown(_ markdown: String) -> String {
        transform(markdown) { u, body in
            guard body < u.count else { return nil }
            let marker = u[body]
            guard marker == dash || marker == star || marker == plus else { return nil }
            if isDivider(u) { return nil }

            // A task: "- [ ] ", "- [x] " or "- [X] ". The box may be the last thing on the line.
            if body + 4 < u.count, u[body + 1] == space, u[body + 2] == 0x5B, u[body + 4] == 0x5D,
               u[body + 3] == space || u[body + 3] == 0x78 || u[body + 3] == 0x58 {
                let afterBox = body + 5
                if afterBox == u.count || u[afterBox] == space {
                    var result = Array(u[0..<body])
                    result.append(u[body + 3] == space ? EditorGlyph.unchecked : EditorGlyph.checked)
                    result.append(space)
                    if afterBox < u.count { result.append(contentsOf: u[(afterBox + 1)...]) }
                    return result
                }
            }

            // A bullet: "- ", "* " or "+ ".
            guard body + 1 < u.count, u[body + 1] == space else { return nil }
            var result = Array(u[0..<body])
            result.append(EditorGlyph.bullet)
            result.append(contentsOf: u[(body + 1)...])
            return result
        }
    }

    static func toMarkdown(_ editorText: String) -> String {
        transform(editorText) { line, indent in
            let u = line
            let body = indent
            guard body + 1 < u.count, u[body + 1] == space else { return nil }
            var result = Array(u[0..<body])
            switch u[body] {
            case EditorGlyph.bullet:
                result.append(contentsOf: [dash, space])
            case EditorGlyph.unchecked:
                result.append(contentsOf: [dash, space, 0x5B, space, 0x5D, space])
            case EditorGlyph.checked:
                result.append(contentsOf: [dash, space, 0x5B, 0x78, 0x5D, space])
            default:
                return nil
            }
            result.append(contentsOf: u[(body + 2)...])
            return result
        }
    }

    // MARK: Plumbing

    /// Runs `convert` on every line outside a code block. It gets the line and its indent, and returns the new line or nil.
    private static func transform(_ text: String, _ convert: ([UInt16], Int) -> [UInt16]?) -> String {
        let units = Array(text.utf16)
        var output: [UInt16] = []
        output.reserveCapacity(units.count)
        var inFence = false
        var start = 0
        var first = true
        while true {
            var end = start
            while end < units.count && units[end] != 0x0A { end += 1 }
            var line = Array(units[start..<end])
            if line.last == 0x0D { line.removeLast() } // Windows line ending

            var indent = 0
            while indent < line.count && line[indent] == space { indent += 1 }
            let isFence = indent + 3 <= line.count && Array(line[indent..<(indent + 3)]) == fence
            if isFence {
                inFence.toggle()
            } else if !inFence, let converted = convert(line, indent) {
                line = converted
            }

            if !first { output.append(0x0A) }
            output.append(contentsOf: line)
            first = false
            if end >= units.count { break }
            start = end + 1
        }
        return String(decoding: output, as: UTF16.self)
    }

    /// "---", "***", "* * *" and the like are dividers, not bullets.
    private static func isDivider(_ line: [UInt16]) -> Bool {
        let trimmed = line.filter { $0 != space }
        guard trimmed.count >= 3, let first = trimmed.first, first == dash || first == star || first == 0x5F else {
            return false
        }
        return trimmed.allSatisfy { $0 == first }
    }
}
