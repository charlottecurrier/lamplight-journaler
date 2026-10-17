import XCTest
@testable import JournalCore

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

final class TemplateComposerTests: XCTestCase {
    let template = EntryTemplate(name: "Evening", questions: ["What went well?", "  ", "What was\nhard?"])

    func testCleanQuestionsDropBlanksAndFlattenWhitespace() {
        XCTAssertEqual(template.cleanQuestions, ["What went well?", "What was hard?"])
    }

    func testAnswersBecomeSections() {
        let body = TemplateComposer.body(for: template, answers: ["The light.", "Not much."])
        XCTAssertEqual(body, "## What went well?\n\nThe light.\n\n## What was hard?\n\nNot much.\n")
    }

    func testSkippedQuestionsAreLeftOut() {
        let body = TemplateComposer.body(for: template, answers: ["  ", "Not much."])
        XCTAssertEqual(body, "## What was hard?\n\nNot much.\n")
    }

    func testNoAnswersMeansNoText() {
        XCTAssertEqual(TemplateComposer.body(for: template, answers: []), "")
        XCTAssertEqual(TemplateComposer.body(for: template, answers: ["", ""]), "")
    }

    func testComposedBodySurvivesTheEntryFile() {
        let body = TemplateComposer.body(for: template, answers: ["Line one\nLine two", "Two"])
        var entry = T.entry("2026-10-17T21:00:00Z", body: body, template: template.id)
        entry.location = nil
        let decoded = EntryFile.decode(
            EntryFile.encode(entry),
            defaults: EntryFileDefaults(id: UUID(), journalID: Journal.defaultID, date: Date())
        )
        XCTAssertEqual(decoded.body, body)
        XCTAssertEqual(decoded.templateID, template.id)
    }
}
