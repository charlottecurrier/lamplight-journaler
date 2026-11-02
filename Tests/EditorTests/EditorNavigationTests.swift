import UIKit
import XCTest
@testable import Lamplight

/// Moves the caret around a long page with the up and down arrows, the way someone does when writing in a template,
/// and checks that the page stays where the caret is.
@MainActor
final class EditorNavigationTests: EditorTestCase {
    private struct Step {
        let number: Int
        let direction: String
        /// Where the page was scrolled to right after the caret moved and the view followed it.
        let offsetAfterMove: CGFloat
        /// Where it was once everything had settled.
        let offsetSettled: CGFloat
        let reading: Reading
        /// Where the blinking caret is actually drawn, if the text view lets us find it.
        let drawnCaret: CGRect?

        var jump: CGFloat { offsetSettled - offsetAfterMove }
    }

    /// One press of an arrow key, the way the text view takes it: the caret moves, then the view scrolls to it.
    private func arrow(_ direction: UITextLayoutDirection, in view: UITextView) -> Bool {
        guard let current = view.selectedTextRange?.end,
              let next = view.position(from: current, in: direction, offset: 1),
              let range = view.textRange(from: next, to: next) else { return false }
        view.selectedTextRange = range
        view.scrollRectToVisible(view.caretRect(for: next).insetBy(dx: 0, dy: -8), animated: false)
        return true
    }

    private func drawnCaret(in view: UITextView) -> CGRect? {
        let interaction = view.interactions.compactMap { $0 as? UITextSelectionDisplayInteraction }.first
        guard let cursor = interaction?.cursorView, !cursor.isHidden else { return nil }
        return cursor.convert(cursor.bounds, to: view)
    }

    private func walk(_ direction: UITextLayoutDirection, steps: Int, in view: UITextView) -> [Step] {
        var taken: [Step] = []
        for number in 1...steps {
            guard arrow(direction, in: view) else { break }
            let afterMove = view.contentOffset.y
            settle(0.06)
            taken.append(Step(
                number: number,
                direction: direction == .down ? "down" : "up",
                offsetAfterMove: afterMove,
                offsetSettled: view.contentOffset.y,
                reading: reading("step \(number)", of: view),
                drawnCaret: drawnCaret(in: view)
            ))
        }
        return taken
    }

    /// Opens a long page with the caret in the title of the second section, which is part way down.
    private func openInTheMiddle() throws -> MarkdownUITextView {
        let view = try editorTextView(markdown: Self.sectionedMarkdown())
        XCTAssertTrue(view.becomeFirstResponder(), "The text view wouldn't take focus.")
        let title = (view.text as NSString).range(of: "Part 2")
        view.selectedRange = NSRange(location: title.location + title.length, length: 0)
        view.scrollRangeToVisible(view.selectedRange)
        settle(0.3)
        return view
    }

    func testArrowsKeepThePageWhereTheCaretIs() throws {
        let view = try openInTheMiddle()
        let startingOffset = view.contentOffset.y
        let steps = walk(.down, steps: 45, in: view) + walk(.up, steps: 45, in: view)
        XCTAssertGreaterThan(startingOffset, 100, "The page didn't start part way down.")

        let lost = steps.filter { !$0.reading.isInView }
        let jumps = steps.filter { abs($0.jump) > Self.size.height / 2 }
        var report = "started at \(Int(startingOffset)); \(steps.count) steps; "
        report += "\(lost.count) with the caret out of view; \(jumps.count) where the page jumped on its own.\n"
        report += lost.prefix(3).map { "  out of view, \($0.direction) \($0.number): " + $0.reading.summary }.joined(separator: "\n")
        report += "\n"
        report += jumps.prefix(3).map {
            String(format: "  jumped, %@ %d: from %.0f to %.0f", $0.direction, $0.number, $0.offsetAfterMove, $0.offsetSettled)
        }.joined(separator: "\n")
        XCTAssertTrue(lost.isEmpty && jumps.isEmpty, report)
    }

    func testTheDrawnCaretStaysOnItsLineWhileArrowing() throws {
        let view = try openInTheMiddle()
        let steps = walk(.down, steps: 45, in: view) + walk(.up, steps: 45, in: view)
        guard steps.contains(where: { $0.drawnCaret != nil }) else {
            // The text view keeps its caret to itself. Nothing to compare.
            throw XCTSkip("The drawn caret couldn't be found.")
        }
        let off = steps.filter { step in
            guard let drawn = step.drawnCaret else { return false }
            return abs(drawn.midY - step.reading.caret.midY) > 4
        }
        let report = "\(off.count) of \(steps.count) steps had the drawn caret away from where the text is.\n"
            + off.prefix(4).map { step in
                String(
                    format: "  %@ %d: drawn %.0f to %.0f, text caret %.0f to %.0f", step.direction, step.number,
                    step.drawnCaret?.minY ?? 0, step.drawnCaret?.maxY ?? 0, step.reading.caret.minY, step.reading.caret.maxY
                )
            }.joined(separator: "\n")
        XCTAssertTrue(off.isEmpty, report)
    }
}
