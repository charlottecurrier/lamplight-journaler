import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class MarkdownHTMLTests: XCTestCase {
    private func html(_ markdown: String) -> String { MarkdownHTML.render(markdown) }

    func testHeadingsAndParagraphs() {
        XCTAssertEqual(html("## Evening\n\nA quiet day.\nThe rain stopped."),
                       "<h2>Evening</h2>\n<p>A quiet day.<br>\nThe rain stopped.</p>")
    }

    func testBlankLinesSeparateParagraphs() {
        XCTAssertEqual(html("One.\n\nTwo."), "<p>One.</p>\n<p>Two.</p>")
    }

    func testInlineStyles() {
        let out = html("A **bold**, *italic*, ~~gone~~, ==marked== and `code` word.")
        XCTAssertEqual(out, "<p>A <strong>bold</strong>, <em>italic</em>, <s>gone</s>, <mark>marked</mark> and <code>code</code> word.</p>")
    }

    func testBoldItalicTogether() {
        XCTAssertEqual(html("***both***"), "<p><strong><em>both</em></strong></p>")
    }

    func testLinksOnlyForWebAndMail() {
        XCTAssertEqual(html("[site](https://example.com)"), "<p><a href=\"https://example.com\">site</a></p>")
        XCTAssertEqual(html("[odd](javascript:void)"), "<p>odd</p>")
    }

    func testTextIsEscaped() {
        XCTAssertEqual(html("1 < 2 & \"3\" > 0"), "<p>1 &lt; 2 &amp; &quot;3&quot; &gt; 0</p>")
    }

    func testBulletedAndNumberedLists() {
        XCTAssertEqual(html("- one\n- two\n\n1. first\n2. second"),
                       "<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n<ol>\n<li value=\"1\">first</li>\n<li value=\"2\">second</li>\n</ol>")
    }

    func testChecklist() {
        let out = html("- [ ] milk\n- [x] bread")
        XCTAssertTrue(out.contains("<ul class=\"tasks\">"))
        XCTAssertTrue(out.contains("<li class=\"open\"><span class=\"box\">&#9744;</span> milk</li>"))
        XCTAssertTrue(out.contains("<li class=\"done\"><span class=\"box\">&#9745;</span> bread</li>"))
    }

    func testQuoteLinesJoinIntoOneQuote() {
        XCTAssertEqual(html("> first\n> second"), "<blockquote><p>first<br>\nsecond</p></blockquote>")
    }

    func testDividerAndCodeBlock() {
        XCTAssertEqual(html("Above\n\n---\n\nBelow"), "<p>Above</p>\n<hr>\n<p>Below</p>")
        XCTAssertEqual(html("```\nlet x = 1 < 2\n```"), "<pre><code>let x = 1 &lt; 2</code></pre>")
    }

    func testEmptyTextIsEmpty() {
        XCTAssertEqual(html(""), "")
    }
}

final class EntryExportTests: XCTestCase {
    func testMarkdownHasTitleDetailsTextAndPhotos() {
        let out = EntryExport.markdown(
            title: "Friday, October 24, 2026", details: "9:14 PM · Full moon · Home",
            body: "## Evening\n\nA walk.\n", photoFiles: ["a.jpg", "b.jpg"]
        )
        XCTAssertEqual(out, """
        # Friday, October 24, 2026

        *9:14 PM · Full moon · Home*

        ## Evening

        A walk.

        ![](photos/a.jpg)

        ![](photos/b.jpg)

        """)
    }

    func testMarkdownLeavesOutWhatIsMissing() {
        XCTAssertEqual(EntryExport.markdown(title: "T", details: "", body: "", photoFiles: []), "# T\n")
    }

    func testFileNameUsesTheEntrysOwnDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 04:30 UTC on 25 Oct is the evening of 24 Oct in Los Angeles.
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 21, minute: 30))!
        let entry = Entry(journalID: UUID(), createdAt: date, timeZoneID: "America/Los_Angeles")
        XCTAssertEqual(EntryExport.baseFileName(for: entry), "Entry 2026-10-24")
    }

    func testHtmlEscapesTheTitleAndKeepsTheBody() {
        let page = EntryExport.html(title: "A & B", details: "9 PM", body: "Hello **there**", photoSources: ["data:image/jpeg;base64,AAA"])
        XCTAssertTrue(page.contains("<h1 class=\"title\">A &amp; B</h1>"))
        XCTAssertTrue(page.contains("<p>Hello <strong>there</strong></p>"))
        XCTAssertTrue(page.contains("<img src=\"data:image/jpeg;base64,AAA\">"))
    }
}

final class FavoriteTests: XCTestCase {
    private func roundTrip(_ entry: Entry) -> Entry {
        let defaults = EntryFileDefaults(id: entry.id, journalID: entry.journalID, date: entry.createdAt)
        return EntryFile.decode(EntryFile.encode(entry), defaults: defaults)
    }

    func testFavoriteSurvivesTheFile() {
        let entry = Entry(journalID: UUID(), isFavorite: true, body: "Keep this.")
        XCTAssertTrue(roundTrip(entry).isFavorite)
    }

    func testNotFavoriteWritesNothingExtra() {
        let entry = Entry(journalID: UUID(), body: "Plain.")
        XCTAssertFalse(String(decoding: EntryFile.encode(entry), as: UTF8.self).contains("favorite"))
        XCTAssertFalse(roundTrip(entry).isFavorite)
    }

    func testFavoriteTypedByHandIsUnderstood() {
        let text = "---\nid: \"\(UUID().uuidString)\"\nfavorite: true\n---\n\nHi"
        let id = UUID()
        let entry = EntryFile.decode(Data(text.utf8), defaults: EntryFileDefaults(id: id, journalID: UUID(), date: Date()))
        XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(entry.body, "Hi")
    }
}
