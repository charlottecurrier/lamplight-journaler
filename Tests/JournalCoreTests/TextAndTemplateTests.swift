import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class EntryTextTests: XCTestCase {
    func testPlainEntryUsesFirstLineAsTitle() {
        let s = EntryText.summarize(body: "A slow Sunday.\n\nWe walked to the river and sat for a while.", answersFirst: false)
        XCTAssertEqual(s.title, "A slow Sunday.")
        XCTAssertEqual(s.preview, "We walked to the river and sat for a while.")
    }

    func testHeadingMarksAreStripped() {
        let s = EntryText.summarize(body: "# Big day\n- first thing\n> a quote", answersFirst: false)
        XCTAssertEqual(s.title, "Big day")
        XCTAssertEqual(s.preview, "first thing a quote")
    }

    func testTemplateEntriesUseTheFirstAnswerAsTitle() {
        let body = "## What went well?\n\nThe light in the kitchen.\n\n## What was hard?\n\nNot much.\n"
        let s = EntryText.summarize(body: body, answersFirst: true)
        XCTAssertEqual(s.title, "The light in the kitchen.")
        XCTAssertEqual(s.preview, "Not much.")
    }

    func testTemplateEntryWithOnlyHeadingsStillHasATitle() {
        let s = EntryText.summarize(body: "## Only a question", answersFirst: true)
        XCTAssertEqual(s.title, "Only a question")
    }

    func testLongPreviewIsCut() {
        let long = "Title\n" + String(repeating: "word ", count: 100)
        let s = EntryText.summarize(body: long, answersFirst: false, maxPreview: 40)
        XCTAssertTrue(s.preview.hasSuffix("…"))
        XCTAssertLessThanOrEqual(s.preview.count, 41)
    }

    func testChecklistBoxesAreNotPartOfTheTitle() {
        let s = EntryText.summarize(body: "## Habits\n\n- [ ] Drink water\n- [x] Walk\n", answersFirst: true)
        XCTAssertEqual(s.title, "Drink water")
        XCTAssertEqual(s.preview, "Walk")
    }

    func testEmptyBody() {
        XCTAssertEqual(EntryText.summarize(body: " \n\n ", answersFirst: false), EntrySummary(title: "", preview: ""))
    }

    func testSearchIgnoresCaseAndAccents() {
        var e = T.entry("2026-10-17T21:00:00Z", body: "Walked to the café by the river")
        e.location = EntryLocation(name: "Mount Tabor")
        XCTAssertTrue(e.matches(query: "CAFE"))
        XCTAssertTrue(e.matches(query: "tabor"))
        XCTAssertTrue(e.matches(query: "   "))
        XCTAssertFalse(e.matches(query: "mountain"))
    }

    func testBlankEntries() {
        var e = T.entry("2026-10-17T21:00:00Z", body: " \n ")
        XCTAssertTrue(e.isBlank)
        e.photos = [PhotoRef(fileName: "a.jpg", width: 1, height: 1)]
        XCTAssertFalse(e.isBlank)
    }

    func testWordCount() {
        XCTAssertEqual(T.entry("2026-10-17T21:00:00Z", body: "one two\nthree   four").wordCount, 4)
    }
}

final class TemplateModelTests: XCTestCase {
    func testTemplateRoundTripsAsAPage() throws {
        let template = EntryTemplate(
            name: "Evening", body: "## What went well?\n\n- [ ] Drink water\n",
            defaultJournalID: UUID(), sortOrder: 3, createdAt: T.date("2026-10-01T00:00:00Z")
        )
        let data = try JSONCoding.encoder().encode(template)
        let decoded = try JSONCoding.decoder().decode(EntryTemplate.self, from: data)
        XCTAssertEqual(decoded, template)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("questions"))
    }

    func testTemplatesFromTheFirstVersionBecomeHeadings() throws {
        let legacy = """
        {"id":"11111111-1111-4111-8111-111111111111","name":"Evening","questions":["What went well?","  ","What was\\nhard?"],
         "sortOrder":2,"createdAt":"2026-10-01T00:00:00Z","modifiedAt":"2026-10-02T00:00:00Z"}
        """
        let decoded = try JSONCoding.decoder().decode(EntryTemplate.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.name, "Evening")
        XCTAssertEqual(decoded.body, "## What went well?\n\n\n## What was hard?\n\n")
        XCTAssertEqual(decoded.sortOrder, 2)
    }

    func testJournalsWithoutADefaultTemplateStillLoad() throws {
        let json = #"{"id":"00000000-0000-4000-8000-000000000001","name":"Journal","colorKey":"ember","sortOrder":0,"createdAt":"2026-10-01T00:00:00Z"}"#
        let journal = try JSONCoding.decoder().decode(Journal.self, from: Data(json.utf8))
        XCTAssertNil(journal.defaultTemplateID)
        var withTemplate = journal
        withTemplate.defaultTemplateID = UUID()
        let data = try JSONCoding.encoder().encode(withTemplate)
        XCTAssertEqual(try JSONCoding.decoder().decode(Journal.self, from: data), withTemplate)
    }

    func testCaretStartsUnderTheFirstHeading() {
        let text = "## What went well?\n\n\n## What was hard?\n\n"
        XCTAssertEqual(TemplateText.initialCaret(inEditorText: text), "## What went well?\n".utf16.count)
    }

    func testCaretWithoutAHeadingGoesToTheEnd() {
        XCTAssertEqual(TemplateText.initialCaret(inEditorText: "Just a line"), 11)
        XCTAssertEqual(TemplateText.initialCaret(inEditorText: ""), 0)
    }

    func testCaretWhenTheHeadingHasTextRightUnderIt() {
        XCTAssertEqual(TemplateText.initialCaret(inEditorText: "## Q\nanswer"), 4)
    }

    func testInsertingATemplateIntoAnEntryKeepsABlankLineBetween() {
        let template = "## Gratitude\n\n"
        let edit = TemplateText.insertionEdit(templateEditorText: template, into: "Already wrote this.", caret: 19)
        XCTAssertEqual(edit.applied(to: "Already wrote this."), "Already wrote this.\n\n## Gratitude\n\n")
        // The caret lands on the blank line under the new heading.
        XCTAssertEqual(edit.selection.lowerBound, "Already wrote this.\n\n## Gratitude\n".utf16.count)
    }

    func testInsertingATemplateIntoAnEmptyEntry() {
        let edit = TemplateText.insertionEdit(templateEditorText: "## Q\n\n", into: "", caret: 0)
        XCTAssertEqual(edit.applied(to: ""), "## Q\n\n")
        XCTAssertEqual(edit.selection.lowerBound, 5)
    }

    func testInsertingInTheMiddleSeparatesBothSides() {
        let text = "Before\nAfter"
        let edit = TemplateText.insertionEdit(templateEditorText: "## Q\n", into: text, caret: 7)
        XCTAssertEqual(edit.applied(to: text), "Before\n\n## Q\nAfter")
    }
}

final class MarkdownBlocksTests: XCTestCase {
    func testHeadingsAndParagraphs() {
        let blocks = MarkdownBlocks.parse("## What went well?\n\nThe light.\nSecond line.\n\n## What was hard?\n\nNot much.\n")
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "What went well?"),
            .paragraph("The light.\nSecond line."),
            .heading(level: 2, text: "What was hard?"),
            .paragraph("Not much."),
        ])
    }

    func testHashtagIsNotAHeading() {
        XCTAssertEqual(MarkdownBlocks.parse("#grateful for today"), [.paragraph("#grateful for today")])
        XCTAssertEqual(MarkdownBlocks.parse("#"), [.paragraph("#")])
        XCTAssertEqual(MarkdownBlocks.parse("####### seven"), [.paragraph("####### seven")])
    }

    func testHeadingRightAfterTextStartsANewBlock() {
        XCTAssertEqual(MarkdownBlocks.parse("Intro\n# Title\nMore"), [
            .paragraph("Intro"), .heading(level: 1, text: "Title"), .paragraph("More"),
        ])
    }

    func testBlankInput() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("\n \n\n"), [])
    }

    func testWindowsLineEndings() {
        XCTAssertEqual(MarkdownBlocks.parse("## Q\r\n\r\nA\r\n"), [.heading(level: 2, text: "Q"), .paragraph("A")])
    }
}

final class EmptyHeadingTests: XCTestCase {
    let evening = "## What went well?\n\n## What was hard?\n\n## Looking forward to\n\n"

    private func clean(_ body: String, template: String? = nil) -> String {
        TemplateText.removingEmptyHeadings(from: body, template: template ?? evening)
    }

    func testNothingWrittenRemovesEverything() {
        XCTAssertEqual(clean(evening), "")
    }

    func testKeepsAnsweredHeadingsAndDropsTheRest() {
        let body = "## What went well?\n\nA long walk.\n\n## What was hard?\n\n## Looking forward to\n\n"
        XCTAssertEqual(clean(body), "## What went well?\n\nA long walk.\n")
    }

    func testDropsAnEmptyHeadingInTheMiddle() {
        let body = "## What went well?\n\nGood.\n\n## What was hard?\n\n## Looking forward to\n\nSleep.\n"
        XCTAssertEqual(clean(body), "## What went well?\n\nGood.\n\n## Looking forward to\n\nSleep.\n")
    }

    func testTextTheSameAsAHeadingIsKeptWhenWrittenUnderIt() {
        let body = "## What was hard?\n\n- [ ] call the bank\n"
        XCTAssertEqual(clean(body), body)
    }

    func testHeadingsNotInTheTemplateAreNeverRemoved() {
        let body = "# Thursday\n\n## What went well?\n\n"
        XCTAssertEqual(clean(body), "# Thursday\n")
    }

    func testTitleOnlyEntryWithoutMatchingTemplateIsUntouched() {
        XCTAssertEqual(clean("# Thursday\n", template: evening), "# Thursday\n")
    }

    func testWhitespaceOnlyLinesCountAsEmpty() {
        XCTAssertEqual(clean("## What went well?\n   \n\t\n## What was hard?\nHard.\n"), "## What was hard?\nHard.\n")
    }

    func testUnchangedWhenThereIsNothingToRemove() {
        let body = "## What went well?\nA\n## What was hard?\nB\n## Looking forward to\nC"
        XCTAssertEqual(clean(body), body)
    }

    func testNestedHeadingsStayWhenAnythingUnderThemIsWritten() {
        let template = "# Day\n\n## Morning\n\n## Evening\n\n"
        let body = "# Day\n\n## Morning\n\nRan.\n\n## Evening\n\n"
        XCTAssertEqual(clean(body, template: template), "# Day\n\n## Morning\n\nRan.\n")
    }

    func testNestedHeadingsGoTogetherWhenNothingIsWritten() {
        let template = "# Day\n\n## Morning\n\n## Evening\n\n"
        XCTAssertEqual(clean(template, template: template), "")
    }

    func testHeadingInsideACodeBlockIsNotAHeading() {
        let body = "```\n## What went well?\n```\n"
        XCTAssertEqual(clean(body), body)
    }

    func testKeepsWindowsLineEndings() {
        let body = "## What went well?\r\n\r\n## What was hard?\r\nHard.\r\n"
        XCTAssertEqual(clean(body), "## What was hard?\r\nHard.\r\n")
    }

    func testTemplateWithoutHeadingsChangesNothing() {
        XCTAssertEqual(clean("Hello\n", template: "Just text"), "Hello\n")
    }

    func testWritingBelowLastHeadingWithNoBlankLineBeforeIt() {
        XCTAssertEqual(clean("## What went well?\nOk\n## What was hard?\n"), "## What went well?\nOk\n")
    }
}
