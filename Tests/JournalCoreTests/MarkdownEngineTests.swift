import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class MarkdownEngineTests: XCTestCase {
    func kinds(_ text: String) -> [MDLineKind] {
        MarkdownDocument(text).lines.map(\.kind)
    }

    /// The styled runs of the first line, as "text:style" strings.
    func runs(_ text: String) -> [String] {
        let doc = MarkdownDocument(text)
        return doc.lines[0].inlines.map { inline in
            var names: [String] = []
            if inline.style.contains(.bold) { names.append("bold") }
            if inline.style.contains(.italic) { names.append("italic") }
            if inline.style.contains(.strike) { names.append("strike") }
            if inline.style.contains(.highlight) { names.append("highlight") }
            if inline.style.contains(.code) { names.append("code") }
            if let link = inline.link { names.append("link=\(link)") }
            return "\(doc.string(inline.range)):\(names.joined(separator: "+"))"
        }
    }

    func markers(_ text: String) -> [String] {
        let doc = MarkdownDocument(text)
        return doc.lines[0].inlineMarkers.map { doc.string($0) }
    }

    // MARK: Lines

    func testLineKinds() {
        let text = "# Title\n\nPlain\n\u{2022} bullet\n\u{2610} todo\n\u{2611} done\n1. one\n> quote\n---\n```\ncode\n```\nafter"
        XCTAssertEqual(kinds(text), [
            .heading(level: 1), .blank, .paragraph, .bullet, .checkbox(checked: false), .checkbox(checked: true),
            .numbered(number: 1), .quote, .divider, .fence, .code, .fence, .paragraph,
        ])
    }

    func testHashWithoutASpaceIsNotAHeading() {
        XCTAssertEqual(kinds("#tag"), [.paragraph])
        XCTAssertEqual(kinds("####### seven"), [.paragraph])
        XCTAssertEqual(kinds("#"), [.paragraph])
        XCTAssertEqual(kinds("###### six"), [.heading(level: 6)])
    }

    func testHeadingMarkerAndContent() {
        let line = MarkdownDocument("## Hello").lines[0]
        XCTAssertEqual(line.marker, 0..<3)
        XCTAssertEqual(line.content, 3..<8)
        XCTAssertTrue(line.markerHidesWhenInactive)
    }

    func testEmptyItemsAndHeadingsAreStillRecognized() {
        XCTAssertEqual(kinds("# "), [.heading(level: 1)])
        XCTAssertEqual(kinds("\u{2022} "), [.bullet])
        XCTAssertEqual(kinds("\u{2610} "), [.checkbox(checked: false)])
        XCTAssertEqual(kinds("1. "), [.numbered(number: 1)])
        XCTAssertEqual(MarkdownDocument("\u{2022} ").lines[0].content, 2..<2)
    }

    func testListMarkersStayVisibleButHeadingAndQuoteMarkersHide() {
        let doc = MarkdownDocument("\u{2022} a\n> b")
        XCTAssertFalse(doc.lines[0].markerHidesWhenInactive)
        XCTAssertTrue(doc.lines[1].markerHidesWhenInactive)
    }

    func testIndentedList() {
        let line = MarkdownDocument("  \u{2022} nested").lines[0]
        XCTAssertEqual(line.indent, 2)
        XCTAssertEqual(line.marker, 2..<4)
        XCTAssertEqual(line.content, 4..<10)
    }

    func testLineRanges() {
        let doc = MarkdownDocument("a\n\nbc\n")
        XCTAssertEqual(doc.lines.map(\.range), [0..<1, 2..<2, 3..<5, 6..<6])
    }

    func testEmptyTextIsOneBlankLine() {
        let doc = MarkdownDocument("")
        XCTAssertEqual(doc.lines.count, 1)
        XCTAssertEqual(doc.lines[0].kind, .blank)
    }

    func testDividers() {
        XCTAssertEqual(kinds("***"), [.divider])
        XCTAssertEqual(kinds("___"), [.divider])
        XCTAssertEqual(kinds("-----"), [.divider])
        XCTAssertEqual(kinds("--"), [.paragraph])
        XCTAssertEqual(kinds("***bold***"), [.paragraph])
    }

    func testCodeBlocksAreNotAnalyzed() {
        let doc = MarkdownDocument("```\n# not a heading\n\u{2022} not a bullet\n```\n# real")
        XCTAssertEqual(doc.lines.map(\.kind), [.fence, .code, .code, .fence, .heading(level: 1)])
        XCTAssertTrue(doc.lines[1].inlines.isEmpty)
    }

    func testQuoteWithoutASpace() {
        let line = MarkdownDocument(">tight").lines[0]
        XCTAssertEqual(line.kind, .quote)
        XCTAssertEqual(line.marker, 0..<1)
    }

    func testLineLookup() {
        let doc = MarkdownDocument("ab\ncd\n\nef")
        XCTAssertEqual(doc.lineIndex(containing: 0), 0)
        XCTAssertEqual(doc.lineIndex(containing: 2), 0) // end of the first line
        XCTAssertEqual(doc.lineIndex(containing: 3), 1)
        XCTAssertEqual(doc.lineIndex(containing: 6), 2)
        XCTAssertEqual(doc.lineIndex(containing: 9), 3)
        XCTAssertEqual(doc.lineIndexes(touching: 0..<4), 0...1)
        XCTAssertEqual(doc.lineIndexes(touching: 0..<3), 0...0) // ends at the start of line 1
        XCTAssertEqual(doc.lineIndexes(touching: 4..<4), 1...1)
    }

    func testActiveLines() {
        let doc = MarkdownDocument("ab\ncd")
        XCTAssertTrue(doc.isActive(0, selection: 2..<2))
        XCTAssertFalse(doc.isActive(1, selection: 2..<2))
        XCTAssertTrue(doc.isActive(1, selection: 3..<3))
        XCTAssertTrue(doc.isActive(0, selection: 1..<4))
        XCTAssertTrue(doc.isActive(1, selection: 1..<4))
    }

    // MARK: Inline styles

    func testBold() {
        XCTAssertEqual(runs("a **bold** b"), ["bold:bold"])
        XCTAssertEqual(markers("a **bold** b"), ["**", "**"])
        XCTAssertEqual(runs("a __bold__ b"), ["bold:bold"])
    }

    func testItalic() {
        XCTAssertEqual(runs("a *it* b"), ["it:italic"])
        XCTAssertEqual(runs("a _it_ b"), ["it:italic"])
    }

    func testBoldItalic() {
        XCTAssertEqual(runs("***both***"), ["both:bold+italic"])
    }

    func testNestedStyles() {
        XCTAssertEqual(runs("**bold *it* more**"), ["bold :bold", "it:bold+italic", " more:bold"])
        XCTAssertEqual(runs("*it **bold** it*"), ["it :italic", "bold:bold+italic", " it:italic"])
    }

    func testStrikeAndHighlight() {
        XCTAssertEqual(runs("~~gone~~"), ["gone:strike"])
        XCTAssertEqual(runs("==look=="), ["look:highlight"])
        XCTAssertEqual(runs("a == b"), [])
        XCTAssertEqual(runs("~one~"), [])
    }

    func testInlineCodeShieldsItsContents() {
        XCTAssertEqual(runs("`code **not bold**`"), ["code **not bold**:code"])
        XCTAssertEqual(markers("`x`"), ["`", "`"])
    }

    func testLinks() {
        XCTAssertEqual(runs("see [site](http://x.com/a_b) now"), ["site:link=http://x.com/a_b"])
        XCTAssertEqual(markers("[site](http://x.com)"), ["[", "](http://x.com)"])
        XCTAssertEqual(runs("[**bold link**](u)"), ["bold link:bold+link=u"])
    }

    func testThingsThatAreNotEmphasis() {
        XCTAssertEqual(runs("snake_case_word"), [])
        XCTAssertEqual(runs("2 * 3 * 4"), [])
        XCTAssertEqual(runs("**unfinished"), [])
        XCTAssertEqual(runs("a * b"), [])
        XCTAssertEqual(runs("[not a link]"), [])
        XCTAssertEqual(runs("[nope] (x)"), [])
    }

    func testEscapedMarkersArePlain() {
        XCTAssertEqual(runs("\\*literal\\*"), [])
    }

    func testStylesInsideListsHeadingsAndQuotes() {
        let doc = MarkdownDocument("\u{2022} a **b**\n## **c** d\n> *e*")
        XCTAssertEqual(doc.lines[0].inlines.map { doc.string($0.range) }, ["b"])
        XCTAssertEqual(doc.lines[1].inlines.map { doc.string($0.range) }, ["c"])
        XCTAssertEqual(doc.lines[2].inlines.map { doc.string($0.range) }, ["e"])
    }

    func testOffsetsCountUTF16Units() {
        // The emoji takes two UTF-16 units.
        let doc = MarkdownDocument("\u{1F319} **moon**")
        XCTAssertEqual(doc.lines[0].inlines.first?.range, 5..<9)
        XCTAssertEqual(doc.string(5..<9), "moon")
    }
}
