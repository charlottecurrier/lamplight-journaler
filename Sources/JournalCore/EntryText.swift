import Foundation

struct EntrySummary: Equatable {
    var title: String
    var preview: String
}

extension Entry {
    /// A title and short preview for list rows, taken from the text.
    ///
    /// For entries made from a template the body starts with a question heading.
    /// There the first answer line is the title, because every entry from that template shares the questions.
    func summary(maxPreview: Int = 180) -> EntrySummary {
        EntryText.summarize(body: body, answersFirst: templateID != nil, maxPreview: maxPreview)
    }

    var wordCount: Int {
        body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Case- and accent-insensitive match on the text and location name.
    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if body.range(of: q, options: options) != nil { return true }
        if let name = location?.name, name.range(of: q, options: options) != nil { return true }
        return false
    }
}

enum EntryText {
    static func summarize(body: String, answersFirst: Bool, maxPreview: Int = 180) -> EntrySummary {
        let lines = body
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isSection($0) }
        guard !lines.isEmpty else { return EntrySummary(title: "", preview: "") }

        func isHeading(_ line: String) -> Bool { line.hasPrefix("#") }

        var titleIndex = 0
        if answersFirst, let firstAnswer = lines.firstIndex(where: { !isHeading($0) }) {
            titleIndex = firstAnswer
        }

        var restLines: [String] = []
        for (index, line) in lines.enumerated() where index != titleIndex {
            if answersFirst && isHeading(line) { continue }
            restLines.append(clean(line))
        }

        var preview = restLines.joined(separator: " ")
        if preview.count > maxPreview {
            preview = String(preview.prefix(maxPreview)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return EntrySummary(title: clean(lines[titleIndex]), preview: preview)
    }

    /// A line like "--- Evening ---". It divides an entry, so it is no use as a title or preview.
    static func isSection(_ line: String) -> Bool {
        let units = Array(line.utf16)
        let doc = MarkdownDocument(String(decoding: units, as: UTF16.self))
        return doc.lines.count == 1 && doc.lines[0].kind == .section
    }

    /// Removes heading marks, bullets and quote marks from the start of a line.
    private static func clean(_ line: String) -> String {
        var s = Substring(line)
        while s.hasPrefix("#") { s = s.dropFirst() }
        s = Substring(s.trimmingCharacters(in: .whitespaces))
        for marker in ["- ", "* ", "> "] where s.hasPrefix(marker) {
            s = s.dropFirst(marker.count)
            break
        }
        for box in ["[ ] ", "[x] ", "[X] "] where s.hasPrefix(box) {
            s = s.dropFirst(box.count)
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
