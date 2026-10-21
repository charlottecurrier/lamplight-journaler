import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class MarkdownEditingTests: XCTestCase {
    let context = SlashContext(
        now: ISODate.date("2026-10-17T21:14:03Z")!,
        timeZone: TimeZone(identifier: "UTC")!,
        locale: Locale(identifier: "en_US")
    )

    /// Types `replacement` at `caret` and returns the text and caret afterwards, or nil if the text view should do it.
    func type(_ text: String, caret: Int, _ replacement: String) -> (text: String, caret: Int)? {
        guard let edit = MarkdownEditing.intercept(
            text: text, range: caret..<caret, replacement: replacement, context: context
        ) else { return nil }
        return (edit.applied(to: text), edit.selection.lowerBound)
    }

    func backspace(_ text: String, caret: Int) -> (text: String, caret: Int)? {
        guard let edit = MarkdownEditing.intercept(
            text: text, range: (caret - 1)..<caret, replacement: "", context: context
        ) else { return nil }
        return (edit.applied(to: text), edit.selection.lowerBound)
    }

    func format(_ command: FormatCommand, _ text: String, _ selection: Range<Int>) -> (text: String, selection: Range<Int>)? {
        guard let edit = MarkdownEditing.apply(command, to: text, selection: selection) else { return nil }
        return (edit.applied(to: text), edit.selection)
    }

    // MARK: Return

    func testReturnContinuesABullet() {
        let result = type("\u{2022} one", caret: 5, "\n")
        XCTAssertEqual(result?.text, "\u{2022} one\n\u{2022} ")
        XCTAssertEqual(result?.caret, 8)
    }

    func testReturnOnAnEmptyItemEndsTheList() {
        let result = type("\u{2022} one\n\u{2022} ", caret: 8, "\n")
        XCTAssertEqual(result?.text, "\u{2022} one\n")
        XCTAssertEqual(result?.caret, 6)
    }

    func testReturnNumbersTheNextItem() {
        XCTAssertEqual(type("1. a", caret: 4, "\n")?.text, "1. a\n2. ")
        XCTAssertEqual(type("9. a", caret: 4, "\n")?.text, "9. a\n10. ")
    }

    func testReturnOnAChecklistStartsAnUncheckedItem() {
        XCTAssertEqual(type("\u{2611} done", caret: 6, "\n")?.text, "\u{2611} done\n\u{2610} ")
        XCTAssertEqual(type("\u{2610} todo", caret: 6, "\n")?.text, "\u{2610} todo\n\u{2610} ")
    }

    func testReturnContinuesAQuote() {
        XCTAssertEqual(type("> a", caret: 3, "\n")?.text, "> a\n> ")
        XCTAssertEqual(type("> ", caret: 2, "\n")?.text, "")
    }

    func testReturnKeepsTheIndent() {
        XCTAssertEqual(type("  \u{2022} a", caret: 5, "\n")?.text, "  \u{2022} a\n  \u{2022} ")
    }

    func testReturnInTheMiddleSplitsTheItem() {
        let result = type("\u{2022} abcd", caret: 4, "\n")
        XCTAssertEqual(result?.text, "\u{2022} ab\n\u{2022} cd")
        XCTAssertEqual(result?.caret, 7)
    }

    func testReturnElsewhereIsAnOrdinaryNewline() {
        XCTAssertNil(type("## Heading", caret: 10, "\n"))
        XCTAssertNil(type("plain", caret: 5, "\n"))
        XCTAssertNil(type("\u{2022} abc", caret: 2, "\n")) // caret right after the marker
        XCTAssertNil(type("```\n\u{2022} x", caret: 9, "\n")) // inside a code block
    }

    // MARK: Space

    func testDashSpaceBecomesABullet() {
        let result = type("-", caret: 1, " ")
        XCTAssertEqual(result?.text, "\u{2022} ")
        XCTAssertEqual(result?.caret, 2)
        XCTAssertEqual(type("*", caret: 1, " ")?.text, "\u{2022} ")
        XCTAssertEqual(type("+", caret: 1, " ")?.text, "\u{2022} ")
        XCTAssertEqual(type("  -", caret: 3, " ")?.text, "  \u{2022} ")
    }

    func testDashInTheMiddleOfALineIsLeftAlone() {
        XCTAssertNil(type("a-", caret: 2, " "))
        XCTAssertNil(type("a -", caret: 3, " "))
    }

    func testBracketsAfterABulletBecomeACheckbox() {
        let empty = type("\u{2022} []", caret: 4, " ")
        XCTAssertEqual(empty?.text, "\u{2610} ")
        XCTAssertEqual(empty?.caret, 2)
        XCTAssertEqual(type("\u{2022} [ ]", caret: 5, " ")?.text, "\u{2610} ")
        XCTAssertEqual(type("\u{2022} [x]", caret: 5, " ")?.text, "\u{2611} ")
        XCTAssertEqual(type("  \u{2022} [X]", caret: 7, " ")?.text, "  \u{2611} ")
    }

    func testNothingHappensInsideACodeBlock() {
        XCTAssertNil(type("```\n-", caret: 5, " "))
        XCTAssertNil(type("```\n/todo", caret: 9, " "))
    }

    func testPlainSpacesAreLeftAlone() {
        XCTAssertNil(type("hello", caret: 5, " "))
        XCTAssertNil(type("1.", caret: 2, " "))
        XCTAssertNil(type("#", caret: 1, " "))
    }

    // MARK: Backspace

    func testBackspaceRightAfterAMarkerRemovesTheMarker() {
        XCTAssertEqual(backspace("\u{2022} ", caret: 2)?.text, "")
        XCTAssertEqual(backspace("\u{2022} abc", caret: 2)?.text, "abc")
        XCTAssertEqual(backspace("\u{2610} abc", caret: 2)?.text, "abc")
        XCTAssertEqual(backspace("1. abc", caret: 3)?.text, "abc")
        XCTAssertEqual(backspace("> abc", caret: 2)?.text, "abc")
        XCTAssertEqual(backspace("## abc", caret: 3)?.text, "abc")
        XCTAssertEqual(backspace("a\n\u{2022} b", caret: 4)?.text, "a\nb")
        XCTAssertEqual(backspace("a\n\u{2022} b", caret: 4)?.caret, 2)
    }

    func testBackspaceElsewhereIsOrdinary() {
        XCTAssertNil(backspace("\u{2022} abc", caret: 4))
        XCTAssertNil(backspace("plain", caret: 5))
        XCTAssertNil(backspace("## abc", caret: 2))
    }

    // MARK: Tab

    func testTabIndentsAListItem() {
        let result = type("\u{2022} a", caret: 3, "\t")
        XCTAssertEqual(result?.text, "  \u{2022} a")
        XCTAssertEqual(result?.caret, 5)
        XCTAssertNil(type("plain", caret: 5, "\t"))
    }

    // MARK: Slash commands typed

    func testSlashCommandsRunOnSpace() {
        let todo = type("/todo", caret: 5, " ")
        XCTAssertEqual(todo?.text, "\u{2610} ")
        XCTAssertEqual(todo?.caret, 2)
        XCTAssertEqual(type("/h2", caret: 3, " ")?.text, "## ")
        XCTAssertEqual(type("/line", caret: 5, " ")?.text, "---\n")
        XCTAssertEqual(type("/quote", caret: 6, " ")?.text, "> ")
        XCTAssertEqual(type("/code", caret: 5, " ")?.text, "```\n\n```")
        XCTAssertEqual(type("/code", caret: 5, " ")?.caret, 4)
        XCTAssertEqual(type("/list", caret: 5, " ")?.text, "\u{2022} ")
        XCTAssertEqual(type("/num", caret: 4, " ")?.text, "1. ")
    }

    func testSlashCommandsKeepTextAfterTheCaret() {
        XCTAssertEqual(type("/h1 Title", caret: 3, " ")?.text, "#  Title")
    }

    func testDateCommandsInsertAtTheWord() {
        XCTAssertEqual(type("Met on /today", caret: 13, " ")?.text, "Met on 10/17/2026")
        XCTAssertEqual(type("/tomorrow", caret: 9, " ")?.text, "10/18/2026")
        XCTAssertEqual(type("/yesterday", caret: 10, " ")?.text, "10/16/2026")
        XCTAssertEqual(type("/today-full", caret: 11, " ")?.text, "Saturday, October 17, 2026")
        let time = type("It is /time", caret: 11, " ")?.text
        XCTAssertTrue(time?.hasPrefix("It is 9:14") == true, time ?? "nil")
    }

    func testBlockCommandsOnlyWorkAtTheStartOfALine() {
        XCTAssertNil(type("abc /todo", caret: 9, " "))
        XCTAssertNotNil(type("  /todo", caret: 7, " "))
    }

    func testUnknownSlashWordsAreLeftAlone() {
        XCTAssertNil(type("/nothing", caret: 8, " "))
        XCTAssertNil(type("a/b", caret: 3, " "))
    }

    // MARK: Format commands: headings

    func testHeadingToggles() {
        XCTAssertEqual(format(.heading(2), "Title", 0..<0)?.text, "## Title")
        XCTAssertEqual(format(.heading(2), "## Title", 3..<3)?.text, "Title")
        XCTAssertEqual(format(.heading(1), "## Title", 3..<3)?.text, "# Title")
        XCTAssertEqual(format(.heading(0), "### Title", 4..<4)?.text, "Title")
    }

    func testHeadingKeepsTheCaretInTheText() {
        let result = format(.heading(2), "Title", 3..<3)
        XCTAssertEqual(result?.text, "## Title")
        XCTAssertEqual(result?.selection, 6..<6)
    }

    func testHeadingReplacesAListMarker() {
        XCTAssertEqual(format(.heading(2), "\u{2022} item", 4..<4)?.text, "## item")
    }

    func testHeadingOnSeveralLines() {
        XCTAssertEqual(format(.heading(3), "a\nb\n\nc", 0..<6)?.text, "### a\n### b\n\n### c")
    }

    // MARK: Format commands: inline

    func testBoldAroundASelection() {
        let result = format(.bold, "a word b", 2..<6)
        XCTAssertEqual(result?.text, "a **word** b")
        XCTAssertEqual(result?.selection, 4..<8)
    }

    func testBoldAgainRemovesIt() {
        let result = format(.bold, "a **word** b", 4..<8)
        XCTAssertEqual(result?.text, "a word b")
        XCTAssertEqual(result?.selection, 2..<6)
    }

    func testBoldAroundTheWordAtTheCaret() {
        XCTAssertEqual(format(.bold, "hello world", 2..<2)?.text, "**hello** world")
        XCTAssertEqual(format(.bold, "hello world", 5..<5)?.text, "**hello** world")
    }

    func testBoldWithNoWordInsertsAPair() {
        let result = format(.bold, "a  b", 2..<2)
        XCTAssertEqual(result?.text, "a **** b")
        XCTAssertEqual(result?.selection, 4..<4)
    }

    func testItalicAndBoldDoNotConfuseEachOther() {
        XCTAssertEqual(format(.italic, "**bold**", 2..<6)?.text, "***bold***")
        XCTAssertEqual(format(.italic, "*it*", 1..<3)?.text, "it")
        XCTAssertEqual(format(.bold, "***both***", 3..<7)?.text, "*both*")
        XCTAssertEqual(format(.italic, "***both***", 3..<7)?.text, "**both**")
        XCTAssertEqual(format(.bold, "*it*", 1..<3)?.text, "***it***")
    }

    func testStrikeHighlightAndCode() {
        XCTAssertEqual(format(.strike, "gone", 0..<4)?.text, "~~gone~~")
        XCTAssertEqual(format(.highlight, "look", 0..<4)?.text, "==look==")
        XCTAssertEqual(format(.code, "x", 0..<1)?.text, "`x`")
        XCTAssertEqual(format(.strike, "~~gone~~", 2..<6)?.text, "gone")
    }

    func testInlineFormattingWorksWithEmoji() {
        let result = format(.bold, "\u{1F319} moon", 3..<7)
        XCTAssertEqual(result?.text, "\u{1F319} **moon**")
    }

    // MARK: Format commands: lists and quotes

    func testBulletToggle() {
        XCTAssertEqual(format(.bullet, "a\nb", 0..<3)?.text, "\u{2022} a\n\u{2022} b")
        XCTAssertEqual(format(.bullet, "\u{2022} a\n\u{2022} b", 0..<7)?.text, "a\nb")
    }

    func testBulletKeepsTheCaretOnTheSameLetter() {
        let result = format(.bullet, "abc", 1..<1)
        XCTAssertEqual(result?.text, "\u{2022} abc")
        XCTAssertEqual(result?.selection, 3..<3)
    }

    func testChecklistReplacesABullet() {
        XCTAssertEqual(format(.checklist, "\u{2022} a", 2..<2)?.text, "\u{2610} a")
        XCTAssertEqual(format(.checklist, "\u{2611} a", 2..<2)?.text, "a")
    }

    func testNumberedListCountsFromOne() {
        XCTAssertEqual(format(.numbered, "a\nb\n\nc", 0..<6)?.text, "1. a\n2. b\n\n3. c")
        XCTAssertEqual(format(.numbered, "1. a\n2. b", 0..<9)?.text, "a\nb")
    }

    func testQuoteToggle() {
        XCTAssertEqual(format(.quote, "a", 0..<0)?.text, "> a")
        XCTAssertEqual(format(.quote, "> a", 2..<2)?.text, "a")
    }

    func testListCommandsLeaveCodeAndDividersAlone() {
        XCTAssertEqual(format(.bullet, "a\n---\nb", 0..<7)?.text, "\u{2022} a\n---\n\u{2022} b")
        XCTAssertNil(format(.bullet, "---", 0..<0))
    }

    func testIndentedListItemsKeepTheirIndent() {
        XCTAssertEqual(format(.checklist, "  \u{2022} a", 4..<4)?.text, "  \u{2610} a")
    }

    // MARK: Format commands: other

    func testDivider() {
        XCTAssertEqual(format(.divider, "abc", 3..<3)?.text, "abc\n---\n")
        XCTAssertEqual(format(.divider, "abc\n", 4..<4)?.text, "abc\n---\n")
        XCTAssertEqual(format(.divider, "abc", 3..<3)?.selection, 8..<8)
    }

    func testLink() {
        let result = format(.link, "see site now", 4..<8)
        XCTAssertEqual(result?.text, "see [site](url) now")
        XCTAssertEqual(result?.selection, 11..<14) // "url" is selected, ready to be replaced
        XCTAssertEqual(format(.link, "", 0..<0)?.text, "[link](url)")
        XCTAssertEqual(format(.link, "", 0..<0)?.selection, 1..<5)
    }

    func testIndentAndOutdent() {
        let indented = format(.indent, "\u{2022} a", 3..<3)
        XCTAssertEqual(indented?.text, "  \u{2022} a")
        XCTAssertEqual(indented?.selection, 5..<5)
        let outdented = format(.outdent, "  \u{2022} a", 5..<5)
        XCTAssertEqual(outdented?.text, "\u{2022} a")
        XCTAssertEqual(outdented?.selection, 3..<3)
        XCTAssertNil(format(.indent, "plain", 0..<0))
        XCTAssertEqual(format(.outdent, "\u{2022} a", 3..<3)?.text, "\u{2022} a")
    }

    func testIndentOnSeveralItems() {
        XCTAssertEqual(format(.indent, "\u{2022} a\n\u{2022} b", 0..<7)?.text, "  \u{2022} a\n  \u{2022} b")
    }

    // MARK: Checklist taps

    func testTappingABoxFlipsIt() {
        let text = "\u{2610} task\n\u{2611} done"
        let checked = MarkdownEditing.toggleCheckbox(in: text, near: 0, keeping: 3..<3)
        XCTAssertEqual(checked?.applied(to: text), "\u{2611} task\n\u{2611} done")
        let nearTheSpace = MarkdownEditing.toggleCheckbox(in: text, near: 1, keeping: 3..<3)
        XCTAssertEqual(nearTheSpace?.applied(to: text), "\u{2611} task\n\u{2611} done")
        let unchecked = MarkdownEditing.toggleCheckbox(in: text, near: 7, keeping: 3..<3)
        XCTAssertEqual(unchecked?.applied(to: text), "\u{2610} task\n\u{2610} done")
        XCTAssertEqual(checked?.selection, 3..<3)
    }

    func testTappingTheTextOfAChecklistItemDoesNothing() {
        XCTAssertNil(MarkdownEditing.toggleCheckbox(in: "\u{2610} task", near: 4, keeping: 0..<0))
        XCTAssertNil(MarkdownEditing.toggleCheckbox(in: "\u{2022} bullet", near: 0, keeping: 0..<0))
    }
}

final class SlashCommandTests: XCTestCase {
    func testMatchingIsByPrefixShortestFirst() {
        XCTAssertEqual(SlashCommand.matching("h").map(\.rawValue), ["h1", "h2", "h3", "h4", "h5", "h6"])
        XCTAssertEqual(SlashCommand.matching("to").first, .todo)
        XCTAssertTrue(SlashCommand.matching("to").contains(.tomorrowFull))
        XCTAssertEqual(SlashCommand.matching("").count, SlashCommand.allCases.count)
        XCTAssertEqual(SlashCommand.matching("TODO"), [.todo])
        XCTAssertTrue(SlashCommand.matching("zzz").isEmpty)
    }

    func testSuggestionsWhileTyping() {
        XCTAssertEqual(SlashCommand.suggestions(in: "/to", caret: 3).first, .todo)
        XCTAssertTrue(SlashCommand.suggestions(in: "/", caret: 1).count > 10)
        XCTAssertTrue(SlashCommand.suggestions(in: "hello", caret: 5).isEmpty)
        XCTAssertTrue(SlashCommand.suggestions(in: "a/b", caret: 3).isEmpty)
    }

    func testBlockCommandsAreNotOfferedMidLine() {
        let midLine = SlashCommand.suggestions(in: "see /t", caret: 6)
        XCTAssertTrue(midLine.contains(.time))
        XCTAssertFalse(midLine.contains(.todo))
        XCTAssertTrue(SlashCommand.suggestions(in: "/t", caret: 2).contains(.todo))
    }

    func testNoSuggestionsInCode() {
        XCTAssertTrue(SlashCommand.suggestions(in: "```\n/to", caret: 7).isEmpty)
    }

    func testEveryCommandHasATitle() {
        for command in SlashCommand.allCases {
            XCTAssertFalse(command.title.isEmpty, command.rawValue)
        }
    }
}
