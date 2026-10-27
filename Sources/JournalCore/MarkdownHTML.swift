import Foundation

/// Turns an entry's Markdown into HTML, for the PDF. Uses the same line and inline analysis as the editor,
/// so what is printed matches what is on screen.
enum MarkdownHTML {
    /// `mediaSource` gives the address an image tag can use, such as a data URL, for a photo placed in the text.
    /// A photo it has no address for is left out.
    static func render(_ markdown: String, mediaSource: (String) -> String? = { _ in nil }) -> String {
        let doc = MarkdownDocument(EditorText.fromMarkdown(markdown))
        var out: [String] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var list: String?
        var inCode = false
        var code: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append("<p>" + paragraph.joined(separator: "<br>\n") + "</p>")
                paragraph = []
            }
        }
        func flushQuote() {
            if !quote.isEmpty {
                out.append("<blockquote><p>" + quote.joined(separator: "<br>\n") + "</p></blockquote>")
                quote = []
            }
        }
        func closeList() {
            if let open = list {
                out.append(open == "ol" ? "</ol>" : "</ul>")
                list = nil
            }
        }
        func closeBlocks() {
            flushParagraph()
            flushQuote()
            closeList()
        }
        func openList(_ kind: String, _ tag: String) {
            if list != kind {
                closeBlocks()
                out.append(kind == "tasks" ? "<ul class=\"tasks\">" : "<\(tag)>")
                list = kind
            }
        }

        for line in doc.lines {
            switch line.kind {
            case .fence:
                if inCode {
                    out.append("<pre><code>" + code.joined(separator: "\n") + "</code></pre>")
                    code = []
                    inCode = false
                } else {
                    closeBlocks()
                    inCode = true
                }
            case .code:
                code.append(escape(doc.string(line.range)))
            case .blank:
                closeBlocks()
            case .heading(let level):
                closeBlocks()
                out.append("<h\(level)>\(inline(doc, line))</h\(level)>")
            case .divider:
                closeBlocks()
                out.append("<hr>")
            case .section:
                closeBlocks()
                out.append("<div class=\"section\"><span>\(escape(doc.string(line.content)))</span></div>")
            case .media:
                closeBlocks()
                if let source = mediaSource(doc.string(line.content)) {
                    out.append("<figure><img src=\"\(escape(source))\"></figure>")
                }
            case .bullet:
                openList("ul", "ul")
                out.append("<li>\(inline(doc, line))</li>")
            case .numbered(let number):
                openList("ol", "ol")
                out.append("<li value=\"\(number)\">\(inline(doc, line))</li>")
            case .checkbox(let checked):
                openList("tasks", "ul")
                let box = checked ? "&#9745;" : "&#9744;"
                out.append("<li class=\"\(checked ? "done" : "open")\"><span class=\"box\">\(box)</span> \(inline(doc, line))</li>")
            case .quote:
                flushParagraph()
                closeList()
                quote.append(inline(doc, line))
            case .paragraph:
                flushQuote()
                closeList()
                paragraph.append(inline(doc, line))
            }
        }
        if inCode { out.append("<pre><code>" + code.joined(separator: "\n") + "</code></pre>") }
        closeBlocks()
        return out.joined(separator: "\n")
    }

    // MARK: Inline

    /// The text of a line after its marker, with bold, italic, strike, highlight, code and links as tags.
    private static func inline(_ doc: MarkdownDocument, _ line: MDLine) -> String {
        let content = line.content
        guard content.lowerBound < content.upperBound else { return "" }

        var cuts: Set<Int> = [content.lowerBound, content.upperBound]
        for run in line.inlines {
            cuts.insert(run.range.lowerBound)
            cuts.insert(run.range.upperBound)
        }
        for marker in line.inlineMarkers {
            cuts.insert(marker.lowerBound)
            cuts.insert(marker.upperBound)
        }
        let points = cuts.filter { content.contains($0) || $0 == content.upperBound }.sorted()

        var html = ""
        for (a, b) in zip(points, points.dropFirst()) {
            if line.inlineMarkers.contains(where: { $0.lowerBound <= a && $0.upperBound >= b }) { continue }
            let text = escape(doc.string(a..<b))
            guard let run = line.inlines.first(where: { $0.range.lowerBound <= a && $0.range.upperBound >= b }) else {
                html += text
                continue
            }
            html += wrap(text, style: run.style, link: run.link)
        }
        return html
    }

    private static func wrap(_ text: String, style: MDStyle, link: String?) -> String {
        var result = text
        if style.contains(.code) { result = "<code>\(result)</code>" }
        if style.contains(.highlight) { result = "<mark>\(result)</mark>" }
        if style.contains(.strike) { result = "<s>\(result)</s>" }
        if style.contains(.italic) { result = "<em>\(result)</em>" }
        if style.contains(.bold) { result = "<strong>\(result)</strong>" }
        if let link, let href = safeLink(link) { result = "<a href=\"\(escape(href))\">\(result)</a>" }
        return result
    }

    /// Only web and mail links become links in the PDF.
    private static func safeLink(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") ? trimmed : nil
    }

    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }
}
