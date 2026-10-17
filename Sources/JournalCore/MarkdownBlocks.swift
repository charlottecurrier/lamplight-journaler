import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    /// One or more lines with no blank line between them. Inline Markdown (bold, italic, links) is left in the text.
    case paragraph(String)
}

/// Splits an entry into headings and paragraphs so the reading view can style them.
/// Only what templates and quick notes need: no lists, tables or code blocks.
enum MarkdownBlocks {
    static func parse(_ body: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for rawLine in body.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if let heading = heading(in: trimmed) {
                flush()
                blocks.append(heading)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// "## Title" is a heading. "#hashtag" is not.
    private static func heading(in line: String) -> MarkdownBlock? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: level, text: text)
    }
}
