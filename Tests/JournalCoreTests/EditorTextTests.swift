import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class EditorTextTests: XCTestCase {
    let bullet = "\u{2022}"
    let open = "\u{2610}"
    let done = "\u{2611}"

    func testBulletsBecomeSymbols() {
        XCTAssertEqual(EditorText.fromMarkdown("- one\n- two"), "\(bullet) one\n\(bullet) two")
        XCTAssertEqual(EditorText.fromMarkdown("* one\n+ two"), "\(bullet) one\n\(bullet) two")
    }

    func testTasksBecomeBoxes() {
        XCTAssertEqual(EditorText.fromMarkdown("- [ ] a\n- [x] b\n- [X] c"), "\(open) a\n\(done) b\n\(done) c")
        XCTAssertEqual(EditorText.fromMarkdown("- [ ]"), "\(open) ")
        XCTAssertEqual(EditorText.fromMarkdown("- [ ]x"), "\(bullet) [ ]x")
    }

    func testIndentIsKept() {
        XCTAssertEqual(EditorText.fromMarkdown("  - a\n    - [ ] b"), "  \(bullet) a\n    \(open) b")
    }

    func testNonListsAreUntouched() {
        let text = "# Heading\n\n-not a bullet\n1. numbered\n> quote\nplain - dash\n---\n***\n* * *"
        XCTAssertEqual(EditorText.fromMarkdown(text), text)
    }

    func testCodeBlocksAreUntouched() {
        let text = "```\n- not a bullet\n- [ ] not a task\n```\n- real"
        XCTAssertEqual(EditorText.fromMarkdown(text), "```\n- not a bullet\n- [ ] not a task\n```\n\(bullet) real")
        let editor = "```\n\(bullet) literal\n```\n\(bullet) real"
        XCTAssertEqual(EditorText.toMarkdown(editor), "```\n\(bullet) literal\n```\n- real")
    }

    func testBackToMarkdown() {
        XCTAssertEqual(EditorText.toMarkdown("\(bullet) one\n\(open) two\n\(done) three"), "- one\n- [ ] two\n- [x] three")
        XCTAssertEqual(EditorText.toMarkdown("  \(bullet) nested"), "  - nested")
        XCTAssertEqual(EditorText.toMarkdown("\(bullet) "), "- ")
    }

    func testSymbolsWithoutASpaceAreLeftAlone() {
        XCTAssertEqual(EditorText.toMarkdown("\(bullet)text"), "\(bullet)text")
        XCTAssertEqual(EditorText.toMarkdown("a \(bullet) b"), "a \(bullet) b")
    }

    func testRoundTrip() {
        let markdown = """
        # Evening

        ## What went well?

        The light.

        - one
          - nested
        - [ ] water
        - [x] walk

        1. first
        2. second

        > quoted **bold**

        ```
        - code
        ```

        ---
        """
        XCTAssertEqual(EditorText.toMarkdown(EditorText.fromMarkdown(markdown)), markdown)
    }

    func testWindowsLineEndingsBecomeNewlines() {
        XCTAssertEqual(EditorText.fromMarkdown("- a\r\n- b\r\n"), "\(bullet) a\n\(bullet) b\n")
        XCTAssertEqual(EditorText.fromMarkdown("a\r\nb"), "a\nb")
    }

    func testEmptyAndTrailingNewlines() {
        XCTAssertEqual(EditorText.fromMarkdown(""), "")
        XCTAssertEqual(EditorText.toMarkdown(""), "")
        XCTAssertEqual(EditorText.fromMarkdown("a\n"), "a\n")
        XCTAssertEqual(EditorText.fromMarkdown("\n\n"), "\n\n")
    }

    func testUnicodeSurvives() {
        let text = "- \u{1F319} moon\n- caf\u{00E9}"
        XCTAssertEqual(EditorText.toMarkdown(EditorText.fromMarkdown(text)), text)
    }

    func testTypingASlashCommandProducesTextThatSavesCorrectly() {
        // "/todo" then space makes a box in the editor. In the file it is a Markdown task.
        let edit = MarkdownEditing.intercept(text: "/todo", range: 5..<5, replacement: " ")
        let editorText = edit?.applied(to: "/todo") ?? ""
        XCTAssertEqual(EditorText.toMarkdown(editorText + "Water"), "- [ ] Water")
    }
}
