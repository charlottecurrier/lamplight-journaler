import UIKit
import XCTest
@testable import Lamplight

/// Types into the real editor and checks that the caret stays on screen and stays level with the text it belongs to.
@MainActor
final class EditorCaretTests: EditorTestCase {
    /// Return, and the other edits the editor makes itself, used to leave the new line below the visible page.
    func testCaretStaysInViewWhileTypingAtTheEnd() throws {
        let view = try editorTextView(markdown: Self.sectionedMarkdown())
        XCTAssertTrue(view.becomeFirstResponder(), "The text view wouldn't take focus.")
        view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
        view.scrollRangeToVisible(view.selectedRange)
        settle(0.2)

        var readings: [Reading] = []
        let sentence = "Then the rain started, and I watched it run down the glass for a while. "
        for round in 1...6 {
            type(sentence, into: view)
            settle()
            readings.append(reading("round \(round), after a sentence", of: view))
            type("\n", into: view)
            settle()
            readings.append(reading("round \(round), after a line break", of: view))
            type("\n", into: view)
            settle()
            readings.append(reading("round \(round), after a second line break", of: view))
        }
        let bad = readings.filter { !$0.isInView }
        XCTAssertTrue(
            bad.isEmpty,
            "\(bad.count) of \(readings.count) readings had the caret out of view.\n" + bad.prefix(4).map(\.summary).joined(separator: "\n")
        )
    }

    /// The text view draws a caret as tall as the whole line, which includes the space a heading or a section title
    /// has above it. The caret hung above the text.
    func testCaretIsLevelWithTheTextOnEveryKindOfLine() throws {
        let view = try editorTextView(markdown: Self.sectionedMarkdown())
        XCTAssertTrue(view.becomeFirstResponder(), "The text view wouldn't take focus.")
        let text = view.text as NSString
        var problems: [String] = []
        for (name, marker) in [
            ("first section title", "Part 1"), ("later section title", "Part 3"), ("heading", "Things I noticed"),
            ("list item", "the neighbour's radio"), ("paragraph", "the point of it."),
        ] {
            let found = text.range(of: marker)
            XCTAssertNotEqual(found.location, NSNotFound, "\(marker) isn't in the sample text.")
            let end = found.location + found.length
            view.selectedRange = NSRange(location: end, length: 0)
            settle(0.1)
            guard let endPosition = view.position(from: view.beginningOfDocument, offset: end),
                  let startPosition = view.position(from: view.beginningOfDocument, offset: end - 1),
                  let letterRange = view.textRange(from: startPosition, to: endPosition)
            else { continue }
            let caret = view.caretRect(for: endPosition)
            let letter = view.firstRect(for: letterRange)
            if caret.minY < letter.minY - 3 || caret.maxY > letter.maxY + 3 {
                problems.append(String(
                    format: "%@: caret %.0f to %.0f, the last letter %.0f to %.0f",
                    name, caret.minY, caret.maxY, letter.minY, letter.maxY
                ))
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }
}
