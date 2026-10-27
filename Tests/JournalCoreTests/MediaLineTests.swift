import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

final class MediaLineTests: XCTestCase {
    private let pic = "![](photos/a.jpg)"

    private func lines(_ text: String) -> [MDLine] { MarkdownDocument(text).lines }

    /// Types `replacement` at `caret` the way the editor sees it: through the rules, else the natural edit.
    private func type(_ text: String, caret: Int, _ replacement: String) -> (text: String, caret: Int) {
        let natural = TextEdit(range: caret..<caret, replacement: replacement, selection: (caret + replacement.utf16.count)..<(caret + replacement.utf16.count))
        let edit = MarkdownEditing.intercept(text: text, range: caret..<caret, replacement: replacement) ?? natural
        return (edit.applied(to: text), edit.selection.lowerBound)
    }

    /// Deletes `range` the way the editor sees it.
    private func delete(_ text: String, _ range: Range<Int>) -> (text: String, caret: Int) {
        let natural = TextEdit(range: range, replacement: "", selection: range.lowerBound..<range.lowerBound)
        let edit = MarkdownEditing.intercept(text: text, range: range, replacement: "") ?? natural
        return (edit.applied(to: text), edit.selection.lowerBound)
    }

    // MARK: Recognising a picture line

    func testAPictureLineHasTheFileNameAsItsContent() {
        let doc = MarkdownDocument(pic)
        XCTAssertEqual(doc.lines[0].kind, .media)
        XCTAssertEqual(doc.string(doc.lines[0].content), "a.jpg")
        XCTAssertNil(doc.lines[0].marker)
        XCTAssertTrue(doc.lines[0].inlines.isEmpty)
    }

    func testAltTextIndentAndTrailingSpacesAreAllowed() {
        XCTAssertEqual(lines("![the lake](photos/a.jpg)")[0].kind, .media)
        XCTAssertEqual(lines("  ![](photos/a.jpg)")[0].kind, .media)
        XCTAssertEqual(lines("![](photos/a.jpg)  ")[0].kind, .media)
        XCTAssertEqual(lines("![](photos/a.jpg)\r")[0].kind, .media)
    }

    func testOtherImageLinesAreNotPictureLines() {
        XCTAssertEqual(lines("![](https://example.com/a.png)")[0].kind, .paragraph)
        XCTAssertEqual(lines("![](photos/Removed/a.jpg)")[0].kind, .paragraph)
        XCTAssertEqual(lines("![](photos/)")[0].kind, .paragraph)
        XCTAssertEqual(lines("![](photos/a b.jpg)")[0].kind, .paragraph)
        XCTAssertEqual(lines("text ![](photos/a.jpg)")[0].kind, .paragraph)
        XCTAssertEqual(lines("![](photos/a.jpg) text")[0].kind, .paragraph)
        XCTAssertEqual(lines("    ![](photos/a.jpg)")[0].kind, .paragraph)
        XCTAssertEqual(lines("![](photos/a.jpg")[0].kind, .paragraph)
    }

    func testAPictureLineInsideACodeBlockIsCode() {
        let doc = MarkdownDocument("```\n\(pic)\n```")
        XCTAssertEqual(doc.lines.map(\.kind), [.fence, .code, .fence])
    }

    func testPictureLinesDoNotDisturbTheLinesAroundThem() {
        let kinds = lines("# Day\n\(pic)\n\u{2022} item\n\(pic)").map(\.kind)
        XCTAssertEqual(kinds, [.heading(level: 1), .media, .bullet, .media])
    }

    func testPictureLinesSurviveTheEditorConversion() {
        let markdown = "- one\n\(pic)\n- [ ] two\n"
        XCTAssertEqual(EditorText.toMarkdown(EditorText.fromMarkdown(markdown)), markdown)
    }

    func testFileNamesComeInTheOrderTheyAppear() {
        let text = "![](photos/b.jpg)\ntext\n![](photos/a.jpg)\n![](photos/b.jpg)"
        XCTAssertEqual(MediaLine.fileNames(in: text), ["b.jpg", "a.jpg", "b.jpg"])
        XCTAssertEqual(MediaLine.fileNames(in: "no pictures"), [])
    }

    // MARK: Words only

    func testSummariesLeavePicturesOut() {
        let summary = EntryText.summarize(body: "\(pic)\nA walk by the lake.\n\(pic)\nCold wind.", answersFirst: false)
        XCTAssertEqual(summary.title, "A walk by the lake.")
        XCTAssertEqual(summary.preview, "Cold wind.")
    }

    func testStrippedKeepsTheWordsAndTidiesTheGaps() {
        XCTAssertEqual(MediaLine.stripped("One\n\n\(pic)\n\nTwo"), "One\n\nTwo")
        XCTAssertEqual(MediaLine.stripped("\(pic)\n"), "")
        XCTAssertEqual(MediaLine.stripped("plain"), "plain")
    }

    func testWordCountAndSearchIgnorePictures() {
        let entry = T.entry("2026-10-24T20:00:00Z", body: "Two words\n\(pic)")
        XCTAssertEqual(entry.wordCount, 2)
        XCTAssertFalse(entry.matches(query: "jpg"))
        XCTAssertTrue(entry.matches(query: "words"))
    }

    // MARK: Inserting

    private func insert(_ names: [String], _ text: String, caret: Int) -> (text: String, caret: Int) {
        let edit = MediaLine.insertionEdit(fileNames: names, into: text, caret: caret)
        return (edit.applied(to: text), edit.selection.lowerBound)
    }

    func testInsertingOnAnEmptyPageLeavesTheCaretBelow() {
        let result = insert(["a.jpg"], "", caret: 0)
        XCTAssertEqual(result.text, "\(pic)\n")
        XCTAssertEqual(result.caret, pic.utf16.count + 1)
    }

    func testInsertingOnAnEmptyLineBetweenParagraphs() {
        let result = insert(["a.jpg"], "A\n\nB", caret: 2)
        XCTAssertEqual(result.text, "A\n\(pic)\n\nB")
        XCTAssertEqual(result.caret, 2 + pic.utf16.count + 1)
        XCTAssertEqual(MarkdownDocument(result.text).lines[MarkdownDocument(result.text).lineIndex(containing: result.caret)].kind, .blank)
    }

    func testInsertingAtTheEndOfALine() {
        let result = insert(["a.jpg"], "A walk", caret: 6)
        XCTAssertEqual(result.text, "A walk\n\(pic)\n")
        XCTAssertEqual(result.caret, 6 + 1 + pic.utf16.count + 1)
    }

    func testInsertingAtTheEndOfALineUsesAnEmptyLineThatIsAlreadyBelow() {
        let result = insert(["a.jpg"], "A walk\n\nThen home", caret: 6)
        XCTAssertEqual(result.text, "A walk\n\(pic)\n\nThen home")
        XCTAssertEqual(result.caret, 6 + 1 + pic.utf16.count + 1)
    }

    func testInsertingInTheMiddleOfALineSplitsIt() {
        let result = insert(["a.jpg"], "A walk", caret: 2)
        XCTAssertEqual(result.text, "A \n\(pic)\nwalk")
        XCTAssertEqual(result.caret, 2 + 1 + pic.utf16.count + 1)
    }

    func testInsertingAtTheStartOfALine() {
        let result = insert(["a.jpg"], "A walk", caret: 0)
        XCTAssertEqual(result.text, "\(pic)\nA walk")
        XCTAssertEqual(result.caret, pic.utf16.count + 1)
    }

    func testInsertingWhileOnAPictureLineGoesBelowIt() {
        let result = insert(["b.jpg"], "\(pic)\nText", caret: 3)
        // An empty line is left after the new picture to write on.
        XCTAssertEqual(result.text, "\(pic)\n![](photos/b.jpg)\n\nText")
    }

    func testSeveralPhotosGoInTogether() {
        let result = insert(["a.jpg", "b.jpg"], "", caret: 0)
        XCTAssertEqual(result.text, "\(pic)\n![](photos/b.jpg)\n")
        XCTAssertEqual(MediaLine.fileNames(in: result.text), ["a.jpg", "b.jpg"])
    }

    // MARK: Typing next to a picture

    func testTypingAfterAPictureStartsANewLine() {
        let text = "\(pic)\nNext"
        let result = type(text, caret: pic.utf16.count, "a")
        XCTAssertEqual(result.text, "\(pic)\na\nNext")
        XCTAssertEqual(result.caret, pic.utf16.count + 2)
    }

    func testTypingBeforeAPictureGoesOnTheLineAbove() {
        let result = type(pic, caret: 0, "a")
        XCTAssertEqual(result.text, "a\n\(pic)")
        XCTAssertEqual(result.caret, 1)
    }

    func testReturnNextToAPictureIsLeftToTheTextView() {
        XCTAssertNil(MarkdownEditing.intercept(text: pic, range: pic.utf16.count..<pic.utf16.count, replacement: "\n"))
        XCTAssertNil(MarkdownEditing.intercept(text: pic, range: 0..<0, replacement: "\n"))
    }

    func testTypingInsideAPictureLineLandsAfterIt() {
        let result = type(pic, caret: 5, "a")
        XCTAssertEqual(result.text, "\(pic)\na")
    }

    func testTypingAwayFromPicturesIsLeftToTheTextView() {
        let text = "Hello\n\(pic)\nWorld"
        XCTAssertNil(MarkdownEditing.intercept(text: text, range: 5..<5, replacement: "!"))
        XCTAssertNil(MarkdownEditing.intercept(text: text, range: 24..<24, replacement: "!"))
        XCTAssertNil(MarkdownEditing.intercept(text: "no pictures here", range: 2..<2, replacement: "x"))
    }

    func testPastingNextToAPictureKeepsThemApart() {
        let result = type("\(pic)\nNext", caret: pic.utf16.count, "line one\nline two")
        XCTAssertEqual(result.text, "\(pic)\nline one\nline two\nNext")
    }

    func testAPicturePastedIntoALineGoesOnALineOfItsOwn() {
        // The text has no picture in it yet, so this is the paste bringing one in.
        let result = type("Hello", caret: 5, pic)
        XCTAssertEqual(result.text, "Hello\n\(pic)")
        XCTAssertEqual(result.caret, 5 + 1 + pic.utf16.count)
    }

    func testAPicturePastedInTheMiddleOfAWordSplitsAroundIt() {
        let result = type("Hello", caret: 2, pic)
        XCTAssertEqual(result.text, "He\n\(pic)\nllo")
    }

    func testAPicturePastedOnAnEmptyLineIsLeftAlone() {
        XCTAssertNil(MarkdownEditing.intercept(text: "", range: 0..<0, replacement: pic))
        XCTAssertNil(MarkdownEditing.intercept(text: "A\n\nB", range: 2..<2, replacement: pic))
    }

    func testTypingAfterAPicturesTrailingSpaceStillStartsANewLine() {
        let text = "\(pic) "
        let result = type(text, caret: text.utf16.count, "a")
        XCTAssertEqual(result.text, "\(pic) \na")
    }

    // MARK: Putting right what got through

    func testSeparatedSplitsAPictureThatSharesALine() {
        let text = "Hello\(pic) there"
        let edit = MediaLine.separated(text, caret: text.utf16.count)
        XCTAssertEqual(edit?.applied(to: text), "Hello\n\(pic) \nthere")
        XCTAssertEqual(edit?.selection.lowerBound, text.utf16.count + 2)
    }

    func testSeparatedLeavesCleanTextAlone() {
        XCTAssertNil(MediaLine.separated("Hello\n\(pic)\nThere", caret: 3))
        XCTAssertNil(MediaLine.separated("  \(pic)  \nThere", caret: 3))
        XCTAssertNil(MediaLine.separated("no pictures", caret: 3))
    }

    func testSeparatedLeavesPicturesInCodeAlone() {
        XCTAssertNil(MediaLine.separated("```\nlook: \(pic)\n```", caret: 0))
        XCTAssertNil(MediaLine.separated("see `\(pic)` here", caret: 0))
    }

    func testSeparatedFixesSeveralInOnePass() {
        let text = "a\(pic)b\(pic)c"
        let result = MediaLine.separated(text, caret: 0)?.applied(to: text)
        XCTAssertEqual(result, "a\n\(pic)\nb\n\(pic)\nc")
    }

    // MARK: Pictures that aren't here

    func testPicturesForPhotosThisEntryDoesNotHaveAreDropped() {
        let text = "Before\n\(pic)\n![](photos/other.jpg)\nAfter"
        XCTAssertEqual(MediaLine.removingUnknown(from: text, known: ["a.jpg"]), "Before\n\(pic)\nAfter")
        XCTAssertEqual(MediaLine.removingUnknown(from: text, known: ["a.jpg", "other.jpg"]), text)
        XCTAssertEqual(MediaLine.removingUnknown(from: "plain", known: []), "plain")
    }

    // MARK: Deleting

    func testBackspaceOnTheLineBelowAPictureDoesNotJoinThem() {
        let text = "\(pic)\nNext"
        let start = pic.utf16.count + 1
        let result = delete(text, (start - 1)..<start)
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.caret, pic.utf16.count)
    }

    func testBackspaceAtTheStartOfAPictureDoesNotJoinItToTheLineAbove() {
        let text = "Above\n\(pic)"
        let result = delete(text, 5..<6)
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.caret, 5)
    }

    func testBackspaceOnAnEmptyLineBelowAPictureRemovesThatLine() {
        let text = "\(pic)\n\nNext"
        let start = pic.utf16.count + 1
        let result = delete(text, (start - 1)..<start)
        XCTAssertEqual(result.text, "\(pic)\nNext")
    }

    func testBackspaceAtTheEndOfAPictureRemovesThePictureAndOneLineBreak() {
        let text = "Above\n\(pic)\nBelow"
        let end = 6 + pic.utf16.count
        let result = delete(text, (end - 1)..<end)
        XCTAssertEqual(result.text, "Above\nBelow")
        XCTAssertEqual(result.caret, 5)
    }

    func testDeletingOnePictureLeavesTheOneBesideIt() {
        let text = "\(pic)\n![](photos/b.jpg)"
        let end = text.utf16.count
        let result = delete(text, (end - 1)..<end)
        XCTAssertEqual(result.text, pic)
    }

    func testRemovingThePictureAtTheStartTakesTheBreakAfterIt() {
        let text = "\(pic)\nBelow"
        let result = delete(text, 0..<1)
        XCTAssertEqual(result.text, "Below")
        XCTAssertEqual(result.caret, 0)
    }

    func testRemovingTheOnlyPictureLeavesAnEmptyPage() {
        let result = delete(pic, 3..<4)
        XCTAssertEqual(result.text, "")
    }

    func testDeletingASelectionThatEndsAtThePictureDoesNotJoinThem() {
        let text = "Hello world\n\(pic)"
        // "world" and the line break after it.
        let result = delete(text, 6..<12)
        XCTAssertEqual(result.text, "Hello \n\(pic)")
        XCTAssertEqual(result.caret, 6)
    }

    func testDeletingAWholePictureLineWithASelectionIsLeftToTheTextView() {
        let text = "A\n\(pic)\nB"
        XCTAssertNil(MarkdownEditing.intercept(text: text, range: 2..<(2 + pic.utf16.count), replacement: ""))
    }

    func testASelectionCuttingIntoAPictureTakesTheWholeLine() {
        let text = "Hi\n\(pic)\nBye"
        // From inside "Hi" to the middle of the picture.
        let result = delete(text, 1..<8)
        XCTAssertEqual(result.text, "H\nBye")
        XCTAssertFalse(MediaLine.mayContain(result.text))
    }

    // MARK: Whatever is done, pictures stay on lines of their own

    func testNoEditEverMixesAPictureWithOtherText() {
        let bases = [
            "\(pic)\nHello\n![](photos/b.jpg)\n\nWorld",
            "Start\n\(pic)\n![](photos/b.jpg)",
            "\(pic)",
            "A\n\n\(pic)\n\n\(pic)\nZ\n",
            "![](photos/b.jpg)\n\u{2022} one\n\u{2022} two\n\(pic)",
            "Hello world",
            "",
        ]
        let pieces = ["a", " ", "\n", "xy", "\n\n", "é", "😀", "", "![](photos/a.jpg)", "x ![](photos/b.jpg) y", "![](photos/a.jpg)\n"]
        var seed: UInt64 = 12345
        func next(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(limit))
        }

        for _ in 0..<4000 {
            let text = bases[next(bases.count)]
            let units = Array(text.utf16)
            let lower = next(units.count + 1)
            let upper = min(units.count, lower + (next(3) == 0 ? next(12) : 0))
            let replacement = pieces[next(pieces.count)]
            let range = lower..<upper

            let natural = TextEdit(range: range, replacement: replacement, selection: (range.lowerBound + replacement.utf16.count)..<(range.lowerBound + replacement.utf16.count))
            let edit = MarkdownEditing.intercept(text: text, range: range, replacement: replacement) ?? natural
            XCTAssertLessThanOrEqual(edit.range.upperBound, units.count)
            let result = edit.applied(to: text)

            for name in ["a.jpg", "b.jpg"] {
                let token = MediaLine.markdown(fileName: name)
                var search = result.startIndex..<result.endIndex
                while let found = result.range(of: token, range: search) {
                    // Spaces beside a picture on its line are fine. Anything else is not.
                    var before = found.lowerBound
                    while before > result.startIndex, result[result.index(before: before)] == " " { before = result.index(before: before) }
                    if before > result.startIndex {
                        XCTAssertEqual(result[result.index(before: before)], "\n", "before \(name): \(text.debugDescription) -> \(result.debugDescription) via \(edit)")
                    }
                    var after = found.upperBound
                    while after < result.endIndex, result[after] == " " { after = result.index(after: after) }
                    if after < result.endIndex {
                        XCTAssertEqual(result[after], "\n", "after \(name): \(text.debugDescription) -> \(result.debugDescription) via \(edit)")
                    }
                    search = found.upperBound..<result.endIndex
                }
            }
            let end = result.utf16.count
            XCTAssertTrue(edit.selection.lowerBound >= 0 && edit.selection.upperBound <= end, "selection \(edit.selection) in \(end)")
        }
    }

    // MARK: Format commands

    func testFormatCommandsLeavePictureLinesAlone() {
        let selection = 4..<4
        for command: FormatCommand in [.bold, .italic, .strike, .highlight, .code, .link, .heading(1), .bullet, .quote, .section] {
            XCTAssertNil(MarkdownEditing.apply(command, to: pic, selection: selection), "\(command)")
        }
    }

    func testSlashCommandsDoNotRunOnAPictureLine() {
        let doc = MarkdownDocument(pic)
        XCTAssertNil(SlashCommand.typedToken(in: doc, caret: 3))
    }

    // MARK: Entries

    func testPhotosNotInTheTextStayAboveIt() {
        var entry = T.entry("2026-10-24T20:00:00Z", body: "Words\n![](photos/b.jpg)\nMore")
        entry.photos = [
            PhotoRef(fileName: "a.jpg", width: 4, height: 3),
            PhotoRef(fileName: "b.jpg", width: 3, height: 4),
        ]
        XCTAssertEqual(entry.unplacedPhotos.map(\.fileName), ["a.jpg"])
        XCTAssertEqual(entry.orderedPhotos.map(\.fileName), ["b.jpg", "a.jpg"])
    }

    func testAnEntryWithNoPicturesInTheTextKeepsAllPhotosAbove() {
        var entry = T.entry("2026-10-24T20:00:00Z", body: "Words")
        entry.photos = [PhotoRef(fileName: "a.jpg", width: 4, height: 3)]
        XCTAssertEqual(entry.unplacedPhotos, entry.photos)
        XCTAssertEqual(entry.orderedPhotos, entry.photos)
    }

    func testAPictureNamingAMissingPhotoIsSkippedInTheOrder() {
        var entry = T.entry("2026-10-24T20:00:00Z", body: "![](photos/gone.jpg)\n![](photos/a.jpg)")
        entry.photos = [PhotoRef(fileName: "a.jpg", width: 4, height: 3)]
        XCTAssertEqual(entry.orderedPhotos.map(\.fileName), ["a.jpg"])
        XCTAssertTrue(entry.unplacedPhotos.isEmpty)
    }

    // MARK: Leaving the file alone

    func testAPictureLineIsPlainMarkdownInTheFile() {
        var entry = T.entry("2026-10-24T20:00:00Z", body: "Words\n\(pic)\nMore")
        entry.photos = [PhotoRef(fileName: "a.jpg", width: 4, height: 3)]
        let data = EntryFile.encode(entry)
        let back = EntryFile.decode(data, defaults: EntryFileDefaults(id: UUID(), journalID: Journal.defaultID, date: Date()))
        XCTAssertEqual(back.body, entry.body)
        XCTAssertEqual(back.photos, entry.photos)
    }

    func testTemplateHeadingsWithAPictureUnderThemAreKept() {
        let template = "## Today\n\n## Photos\n\n"
        let body = "## Today\n\nA good day.\n\n## Photos\n\n\(pic)\n"
        XCTAssertEqual(TemplateText.removingEmptyHeadings(from: body, template: template), body)
    }

    // MARK: Printing

    func testPicturesInTheTextBecomeImagesInThePage() {
        let html = MarkdownHTML.render("Before\n\n\(pic)\n\nAfter", mediaSource: { $0 == "a.jpg" ? "data:image/jpeg;base64,AAA" : nil })
        XCTAssertTrue(html.contains("<p>Before</p>\n<figure><img src=\"data:image/jpeg;base64,AAA\"></figure>\n<p>After</p>"), html)
    }

    func testAPictureWithNoSourceIsLeftOutOfThePage() {
        let html = MarkdownHTML.render("Before\n\n\(pic)\n\nAfter")
        XCTAssertFalse(html.contains("img"))
        XCTAssertFalse(html.contains("photos/"))
    }

    func testTheExportPageUsesInlineSources() {
        let page = EntryExport.html(
            title: "T", details: "", body: "Hello\n\n\(pic)", photoSources: ["data:image/jpeg;base64,BBB"],
            inlineSources: ["a.jpg": "data:image/jpeg;base64,AAA"]
        )
        XCTAssertTrue(page.contains("base64,AAA"))
        XCTAssertTrue(page.contains("base64,BBB"))
    }
}
