import Foundation

/// What an entry looks like when it is shared as a Markdown file or a PDF.
/// The words for the date and details come from the app, which knows how to format them.
enum EntryExport {
    /// A file name that is safe on any system, such as "Entry 2026-10-24".
    static func baseFileName(for entry: Entry) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = entry.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: entry.createdAt)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        return String(format: "Entry %04d-%02d-%02d", year, month, day)
    }

    /// Markdown that reads well anywhere. Photos are linked from a "photos" folder beside the file.
    static func markdown(title: String, details: String, body: String, photoFiles: [String]) -> String {
        var parts = ["# " + title]
        if !details.isEmpty { parts.append("*\(details)*") }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append(text) }
        for file in photoFiles { parts.append("![](photos/\(file))") }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// A page of HTML in dark ink on white paper, for printing as a PDF. `photoSources` are addresses an image
    /// tag can use, such as data URLs.
    static func html(title: String, details: String, body: String, photoSources: [String]) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = photoSources
            .map { "<figure><img src=\"\(MarkdownHTML.escape($0))\"></figure>" }
            .joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: Georgia, "Times New Roman", serif; font-size: 12.5pt; line-height: 1.5; color: #231c14; }
        h1.title { font-size: 21pt; margin: 0 0 4pt 0; }
        .details { color: #6b5d4a; font-size: 10.5pt; margin: 0 0 18pt 0; }
        h1, h2, h3, h4 { line-height: 1.25; }
        h1 { font-size: 19pt; } h2 { font-size: 16pt; } h3 { font-size: 14pt; } h4, h5, h6 { font-size: 12.5pt; }
        p { margin: 0 0 10pt 0; }
        blockquote { margin: 0 0 10pt 0; padding-left: 12pt; border-left: 2pt solid #c9b99e; color: #5a4c39; }
        blockquote p { margin: 0; }
        ul, ol { margin: 0 0 10pt 0; padding-left: 20pt; }
        ul.tasks { list-style: none; padding-left: 0; }
        li.done { color: #6b5d4a; }
        .box { display: inline-block; width: 16pt; }
        mark { background: #f1dfae; }
        code, pre { font-family: Menlo, Courier, monospace; font-size: 10.5pt; }
        pre { background: #f4eee3; padding: 8pt; white-space: pre-wrap; }
        hr { border: 0; border-top: 0.5pt solid #c9b99e; margin: 14pt 0; }
        figure { margin: 12pt 0; text-align: center; }
        img { max-width: 100%; max-height: 330pt; }
        a { color: #7a3510; }
        </style></head><body>
        <h1 class="title">\(MarkdownHTML.escape(title))</h1>
        <p class="details">\(MarkdownHTML.escape(details))</p>
        \(MarkdownHTML.render(text))
        \(photos)
        </body></html>
        """
    }
}
