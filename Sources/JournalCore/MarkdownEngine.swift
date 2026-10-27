import Foundation

// The live Markdown editor works on the text in "editor form", where list markers are real symbols:
// "• " for a bullet, "☐ " / "☑ " for a checklist item. EditorText converts to and from the Markdown in the file.
//
// All positions here are UTF-16 offsets, because that is what UITextView and NSRange use.

enum EditorGlyph {
    static let bullet: UInt16 = 0x2022 // •
    static let unchecked: UInt16 = 0x2610 // ☐
    static let checked: UInt16 = 0x2611 // ☑

    static let bulletString = "\u{2022}"
    static let uncheckedString = "\u{2610}"
    static let checkedString = "\u{2611}"
}

struct MDStyle: OptionSet, Equatable {
    let rawValue: Int

    static let bold = MDStyle(rawValue: 1)
    static let italic = MDStyle(rawValue: 2)
    static let strike = MDStyle(rawValue: 4)
    static let highlight = MDStyle(rawValue: 8)
    static let code = MDStyle(rawValue: 16)
}

/// A run of text that carries a style. The characters that make the style (like the `**`) are not part of the range.
struct MDInline: Equatable {
    var range: Range<Int>
    var style: MDStyle
    var link: String?
}

enum MDLineKind: Equatable {
    case blank
    case paragraph
    case heading(level: Int)
    case bullet
    case checkbox(checked: Bool)
    case numbered(number: Int)
    case quote
    case divider
    /// "--- Evening ---": a titled break, drawn as the title with a rule running to the edge.
    case section
    /// "![](photos/NAME.jpg)": a picture on a line of its own. `content` is the file name.
    case media
    /// A line of three backticks that opens or closes a code block.
    case fence
    /// A line inside a code block.
    case code

    var isListItem: Bool {
        switch self {
        case .bullet, .checkbox, .numbered: return true
        default: return false
        }
    }
}

struct MDLine {
    /// The line without its newline.
    var range: Range<Int>
    var kind: MDLineKind
    /// Leading spaces.
    var indent: Int
    /// The block marker with its trailing space: "## ", "• ", "☐ ", "1. ", "> ". Nil for plain lines.
    var marker: Range<Int>?
    /// Headings and quotes hide their marker when the cursor isn't on the line. List markers are always shown.
    var markerHidesWhenInactive: Bool
    /// The text after the marker (or after the indent, for plain lines).
    var content: Range<Int>
    var inlines: [MDInline]
    /// Inline marker characters (`**`, `~~`, link brackets) that can be hidden when the cursor isn't on the line.
    var inlineMarkers: [Range<Int>]
}

struct MarkdownDocument {
    let units: [UInt16]
    let lines: [MDLine]

    init(_ text: String) {
        let units = Array(text.utf16)
        self.units = units
        self.lines = MarkdownDocument.analyze(units)
    }

    func string(_ range: Range<Int>) -> String {
        String(decoding: units[range], as: UTF16.self)
    }

    /// The line the offset is on. An offset at the very end of a line belongs to that line.
    func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].range.lowerBound <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// The lines a selection touches. A selection that ends right at the start of a line doesn't include that line.
    func lineIndexes(touching selection: Range<Int>) -> ClosedRange<Int> {
        let first = lineIndex(containing: selection.lowerBound)
        let lastOffset = selection.isEmpty ? selection.upperBound : selection.upperBound - 1
        let last = max(first, lineIndex(containing: lastOffset))
        return first...last
    }

    /// True when the selection (or caret) touches this line, so its Markdown symbols should show.
    func isActive(_ lineIndex: Int, selection: Range<Int>) -> Bool {
        let range = lines[lineIndex].range
        return selection.lowerBound <= range.upperBound && selection.upperBound >= range.lowerBound
    }

    // MARK: Analysis

    private static func analyze(_ u: [UInt16]) -> [MDLine] {
        var lines: [MDLine] = []
        var inFence = false
        var start = 0
        while true {
            var end = start
            while end < u.count && u[end] != 0x0A { end += 1 }
            lines.append(classify(u, start..<end, &inFence))
            if end >= u.count { break }
            start = end + 1
        }
        return lines
    }

    private static func starts(_ u: [UInt16], _ prefix: [UInt16], at index: Int) -> Bool {
        guard index + prefix.count <= u.count else { return false }
        for (offset, unit) in prefix.enumerated() where u[index + offset] != unit {
            return false
        }
        return true
    }

    private static let fenceUnits: [UInt16] = [0x60, 0x60, 0x60]

    private static func classify(_ u: [UInt16], _ r: Range<Int>, _ inFence: inout Bool) -> MDLine {
        var indent = 0
        while r.lowerBound + indent < r.upperBound && u[r.lowerBound + indent] == 0x20 { indent += 1 }
        let body = r.lowerBound + indent

        func line(
            _ kind: MDLineKind, marker: Range<Int>? = nil, hides: Bool = false, inline: Bool = true
        ) -> MDLine {
            let contentStart = marker?.upperBound ?? body
            let content = contentStart..<r.upperBound
            var inlines: [MDInline] = []
            var inlineMarkers: [Range<Int>] = []
            if inline {
                var spans: [RawSpan] = []
                scanInline(u, content, spans: &spans, markers: &inlineMarkers)
                inlineMarkers.sort { $0.lowerBound < $1.lowerBound }
                inlines = flatten(spans, excluding: inlineMarkers)
            }
            return MDLine(
                range: r, kind: kind, indent: indent, marker: marker, markerHidesWhenInactive: hides,
                content: content, inlines: inlines, inlineMarkers: inlineMarkers
            )
        }

        if inFence {
            if starts(u, fenceUnits, at: body) {
                inFence = false
                return line(.fence, inline: false)
            }
            return line(.code, inline: false)
        }
        if starts(u, fenceUnits, at: body) {
            inFence = true
            return line(.fence, inline: false)
        }
        if body >= r.upperBound {
            return line(.blank, inline: false)
        }

        // Heading: one to six # and a space. "#hashtag" is not a heading.
        if indent <= 3 {
            var hashes = 0
            while body + hashes < r.upperBound && u[body + hashes] == 0x23 { hashes += 1 }
            if (1...6).contains(hashes), body + hashes < r.upperBound, u[body + hashes] == 0x20 {
                return line(.heading(level: hashes), marker: r.lowerBound..<(body + hashes + 1), hides: true)
            }
        }

        // Section: "--- Title ---". At least three dashes either side, with a space between them and the title.
        if indent <= 3, u[body] == 0x2D, let title = sectionTitle(u, body, r.upperBound) {
            var section = line(.section, marker: r.lowerBound..<title.lowerBound, hides: true, inline: false)
            section.content = title
            section.inlineMarkers = [title.upperBound..<r.upperBound]
            return section
        }

        // Picture: "![](photos/NAME)" and nothing else on the line.
        if indent <= 3, u[body] == 0x21, let name = mediaName(u, body, r.upperBound) {
            var picture = line(.media, inline: false)
            picture.content = name
            return picture
        }

        // Divider: three or more of the same - * _ and nothing else.
        let first = u[body]
        if first == 0x2D || first == 0x2A || first == 0x5F {
            var run = 0
            while body + run < r.upperBound && u[body + run] == first { run += 1 }
            var restIsBlank = true
            var cursor = body + run
            while cursor < r.upperBound {
                if u[cursor] != 0x20 { restIsBlank = false }
                cursor += 1
            }
            if run >= 3 && restIsBlank {
                return line(.divider, inline: false)
            }
        }

        if body + 1 < r.upperBound, u[body + 1] == 0x20 {
            if first == EditorGlyph.unchecked || first == EditorGlyph.checked {
                return line(.checkbox(checked: first == EditorGlyph.checked), marker: body..<(body + 2))
            }
            if first == EditorGlyph.bullet {
                return line(.bullet, marker: body..<(body + 2))
            }
        }

        // Numbered: 1 to 9 digits, a period and a space.
        var digits = 0
        while body + digits < r.upperBound && digits < 9, (0x30...0x39).contains(u[body + digits]) { digits += 1 }
        if digits > 0, body + digits + 1 < r.upperBound, u[body + digits] == 0x2E, u[body + digits + 1] == 0x20 {
            var number = 0
            for offset in 0..<digits { number = number * 10 + Int(u[body + offset] - 0x30) }
            return line(.numbered(number: number), marker: body..<(body + digits + 2))
        }

        // Quote: ">" and, usually, a space.
        if indent <= 3 && first == 0x3E {
            let hasSpace = body + 1 < r.upperBound && u[body + 1] == 0x20
            return line(.quote, marker: r.lowerBound..<(body + (hasSpace ? 2 : 1)), hides: true)
        }

        return line(.paragraph)
    }

    /// The title of a line like "--- Evening ---", or nil if the line isn't one. Dashes and spaces around the title
    /// are not part of it.
    private static func sectionTitle(_ u: [UInt16], _ start: Int, _ end: Int) -> Range<Int>? {
        var lead = 0
        while start + lead < end && u[start + lead] == 0x2D { lead += 1 }
        guard lead >= 3, start + lead < end, u[start + lead] == 0x20 else { return nil }

        var last = end
        while last > start + lead && (u[last - 1] == 0x20 || u[last - 1] == 0x09 || u[last - 1] == 0x0D) { last -= 1 }
        var trail = 0
        while last - trail > start + lead && u[last - trail - 1] == 0x2D { trail += 1 }
        guard trail >= 3, last - trail > start + lead, u[last - trail - 1] == 0x20 else { return nil }

        var titleStart = start + lead
        var titleEnd = last - trail
        while titleStart < titleEnd && u[titleStart] == 0x20 { titleStart += 1 }
        while titleEnd > titleStart && u[titleEnd - 1] == 0x20 { titleEnd -= 1 }
        guard titleStart < titleEnd else { return nil }
        return titleStart..<titleEnd
    }

    private static let photosPrefix: [UInt16] = Array("photos/".utf16)

    /// The file name in a line like "![](photos/ABC.jpg)". Alt text is allowed. Nil if the line holds anything else,
    /// or if the path goes anywhere but straight into the photos folder.
    private static func mediaName(_ u: [UInt16], _ start: Int, _ end: Int) -> Range<Int>? {
        guard start + 1 < end, u[start] == 0x21, u[start + 1] == 0x5B else { return nil }
        var k = start + 2
        while k < end, u[k] != 0x5D {
            if u[k] == 0x5B { return nil }
            k += 1
        }
        guard k + 1 < end, u[k + 1] == 0x28 else { return nil }
        let pathStart = k + 2
        guard starts(u, photosPrefix, at: pathStart) else { return nil }
        let nameStart = pathStart + photosPrefix.count
        var m = nameStart
        while m < end, u[m] != 0x29 {
            // Spaces, slashes and brackets can't be in a file name here.
            switch u[m] {
            case 0x20, 0x2F, 0x28, 0x5B, 0x5D, 0x3C, 0x3E: return nil
            default: m += 1
            }
        }
        guard m < end, m > nameStart else { return nil }
        var rest = m + 1
        while rest < end, u[rest] == 0x20 || u[rest] == 0x09 || u[rest] == 0x0D { rest += 1 }
        return rest == end ? nameStart..<m : nil
    }

    // MARK: Inline scanning

    private struct RawSpan {
        var range: Range<Int>
        var style: MDStyle
        var link: String?
    }

    private static func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }

    private static func isWordCharacter(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) || unit >= 0x80
    }

    private static func scanInline(
        _ u: [UInt16], _ range: Range<Int>, spans: inout [RawSpan], markers: inout [Range<Int>]
    ) {
        var i = range.lowerBound
        let end = range.upperBound
        while i < end {
            switch u[i] {
            case 0x5C: // backslash: the next character is plain
                i += 2
            case 0x60: // `code`
                var j = i + 1
                while j < end && u[j] != 0x60 { j += 1 }
                if j < end && j > i + 1 {
                    markers.append(i..<(i + 1))
                    markers.append(j..<(j + 1))
                    spans.append(RawSpan(range: (i + 1)..<j, style: .code, link: nil))
                    i = j + 1
                } else {
                    i += 1
                }
            case 0x5B: // [text](url)
                if let link = parseLink(u, i, end) {
                    markers.append(i..<(i + 1))
                    markers.append(link.closeMarker)
                    spans.append(RawSpan(range: link.text, style: [], link: link.url))
                    scanInline(u, link.text, spans: &spans, markers: &markers)
                    i = link.end
                } else {
                    i += 1
                }
            case 0x2A, 0x5F, 0x7E, 0x3D: // * _ ~ =
                i = parseEmphasis(u, i, end, spans: &spans, markers: &markers)
            default:
                i += 1
            }
        }
    }

    private static func parseLink(
        _ u: [UInt16], _ i: Int, _ end: Int
    ) -> (text: Range<Int>, url: String, closeMarker: Range<Int>, end: Int)? {
        var k = i + 1
        while k < end && u[k] != 0x5D {
            if u[k] == 0x5B { return nil }
            k += 1
        }
        guard k < end, k > i + 1, k + 1 < end, u[k + 1] == 0x28 else { return nil }
        var m = k + 2
        while m < end && u[m] != 0x29 { m += 1 }
        guard m < end else { return nil }
        let url = String(decoding: u[(k + 2)..<m], as: UTF16.self)
        return ((i + 1)..<k, url, k..<(m + 1), m + 1)
    }

    /// Handles a run of * _ ~ or =. Returns where scanning continues.
    private static func parseEmphasis(
        _ u: [UInt16], _ i: Int, _ end: Int, spans: inout [RawSpan], markers: inout [Range<Int>]
    ) -> Int {
        let c = u[i]
        var run = 0
        while i + run < end && u[i + run] == c { run += 1 }

        let isPair = c == 0x7E || c == 0x3D // ~~strike~~ and ==highlight==
        let n: Int
        if isPair {
            guard run == 2 else { return i + run }
            n = 2
        } else {
            guard run <= 3 else { return i + run }
            n = run
        }

        let contentStart = i + n
        guard contentStart < end, !isSpace(u[contentStart]) else { return i + run }
        // snake_case is not emphasis.
        if c == 0x5F, i > 0, isWordCharacter(u[i - 1]) { return i + run }

        var j = contentStart
        while j < end {
            let d = u[j]
            if d == 0x5C {
                j += 2
                continue
            }
            if d == 0x60 {
                var k = j + 1
                while k < end && u[k] != 0x60 { k += 1 }
                j = k < end ? k + 1 : j + 1
                continue
            }
            if d == c {
                var r = 0
                while j + r < end && u[j + r] == c { r += 1 }
                let closes = r == n
                    && j > contentStart
                    && !isSpace(u[j - 1])
                    && (c != 0x5F || j + r >= end || !isWordCharacter(u[j + r]))
                if closes {
                    markers.append(i..<(i + n))
                    markers.append(j..<(j + n))
                    var style: MDStyle
                    switch c {
                    case 0x7E: style = .strike
                    case 0x3D: style = .highlight
                    default: style = n == 1 ? .italic : (n == 2 ? .bold : [.bold, .italic])
                    }
                    spans.append(RawSpan(range: contentStart..<j, style: style, link: nil))
                    scanInline(u, contentStart..<j, spans: &spans, markers: &markers)
                    return j + n
                }
                j += r
                continue
            }
            j += 1
        }
        return i + run
    }

    /// Turns overlapping spans into separate runs, each with the combined style of everything over it.
    /// The marker characters themselves (`**`, `[`, and so on) are left out of the runs.
    private static func flatten(_ spans: [RawSpan], excluding markers: [Range<Int>]) -> [MDInline] {
        guard !spans.isEmpty else { return [] }
        var cuts = Set<Int>()
        for span in spans {
            cuts.insert(span.range.lowerBound)
            cuts.insert(span.range.upperBound)
        }
        for marker in markers {
            cuts.insert(marker.lowerBound)
            cuts.insert(marker.upperBound)
        }
        let points = cuts.sorted()
        var result: [MDInline] = []
        for (a, b) in zip(points, points.dropFirst()) {
            if markers.contains(where: { $0.lowerBound <= a && $0.upperBound >= b }) { continue }
            var style: MDStyle = []
            var link: String?
            for span in spans where span.range.lowerBound <= a && span.range.upperBound >= b {
                style.formUnion(span.style)
                if let url = span.link { link = url }
            }
            if !style.isEmpty || link != nil {
                result.append(MDInline(range: a..<b, style: style, link: link))
            }
        }
        return result
    }
}
