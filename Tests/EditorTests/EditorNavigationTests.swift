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
        /// How far the page moved by itself when only the caret moved, before anything scrolled to it.
        let movedByItself: CGFloat
        /// Where the page was after the view scrolled to the caret, and once everything had settled.
        let offsetAfterScroll: CGFloat
        let offsetSettled: CGFloat
        /// How many characters of the text had their style rewritten by moving the caret.
        let restyled: Int
        let reading: Reading
        /// Where the blinking caret is actually drawn, if the text view lets us find it.
        let drawnCaret: CGRect?

        var jumpAfterScroll: CGFloat { offsetSettled - offsetAfterScroll }
    }

    /// Counts the characters whose style is rewritten, from the text storage's own notices.
    private final class StyleEdits {
        private(set) var characters = 0
        private var token: NSObjectProtocol?

        init(_ storage: NSTextStorage) {
            token = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
            ) { [weak self] note in
                guard let storage = note.object as? NSTextStorage else { return }
                self?.characters += storage.editedRange.length
            }
        }

        func take() -> Int {
            defer { characters = 0 }
            return characters
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }

    /// One press of an arrow key. The caret moves, and then the view scrolls to it, as the text view does.
    private func arrow(_ direction: UITextLayoutDirection, in view: UITextView, edits: StyleEdits) -> (moved: CGFloat, restyled: Int)? {
        guard let current = view.selectedTextRange?.end,
              let next = view.position(from: current, in: direction, offset: 1),
              let range = view.textRange(from: next, to: next) else { return nil }
        let before = view.contentOffset.y
        _ = edits.take()
        view.selectedTextRange = range
        let moved = view.contentOffset.y - before
        let restyled = edits.take()
        view.scrollRectToVisible(view.caretRect(for: next).insetBy(dx: 0, dy: -8), animated: false)
        return (moved, restyled)
    }

    private func drawnCaret(in view: UITextView) -> CGRect? {
        let interaction = view.interactions.compactMap { $0 as? UITextSelectionDisplayInteraction }.first
        guard let cursor = interaction?.cursorView, !cursor.isHidden else { return nil }
        return cursor.convert(cursor.bounds, to: view)
    }

    private func walk(_ direction: UITextLayoutDirection, steps: Int, in view: UITextView) -> [Step] {
        let edits = StyleEdits(view.textStorage)
        var taken: [Step] = []
        for number in 1...steps {
            guard let result = arrow(direction, in: view, edits: edits) else { break }
            let afterScroll = view.contentOffset.y
            settle(0.06)
            taken.append(Step(
                number: number,
                direction: direction == .down ? "down" : "up",
                movedByItself: result.moved,
                offsetAfterScroll: afterScroll,
                offsetSettled: view.contentOffset.y,
                restyled: result.restyled,
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
        // The text view lays out only what it needs, so the page isn't as tall as it will be until the caret is found.
        view.layoutManager.ensureLayout(for: view.textContainer)
        view.layoutIfNeeded()
        let caret = view.caretRect(for: view.selectedTextRange?.end ?? view.endOfDocument)
        view.setContentOffset(CGPoint(x: 0, y: max(0, caret.minY - 150)), animated: false)
        settle(0.3)
        return view
    }

    func testArrowingDoesNotMoveThePageOnItsOwn() throws {
        let view = try openInTheMiddle()
        XCTAssertGreaterThan(view.contentOffset.y, 100, "The page didn't start part way down.")
        let steps = walk(.down, steps: 45, in: view) + walk(.up, steps: 45, in: view)

        let moved = steps.filter { abs($0.movedByItself) > 1 }
        let lost = steps.filter { !$0.reading.isInView }
        let jumps = steps.filter { abs($0.jumpAfterScroll) > Self.size.height / 2 }
        var report = "\(steps.count) steps; \(moved.count) where the page moved by itself; "
        report += "\(lost.count) with the caret out of view; \(jumps.count) where the page jumped after the view scrolled.\n"
        report += moved.prefix(3).map {
            String(format: "  moved by itself, %@ %d: by %.0f", $0.direction, $0.number, $0.movedByItself)
        }.joined(separator: "\n")
        report += lost.prefix(3).map { "\n  out of view, \($0.direction) \($0.number): " + $0.reading.summary }.joined()
        report += jumps.prefix(3).map {
            String(format: "\n  jumped, %@ %d: from %.0f to %.0f", $0.direction, $0.number, $0.offsetAfterScroll, $0.offsetSettled)
        }.joined()
        XCTAssertTrue(moved.isEmpty && lost.isEmpty && jumps.isEmpty, report)
    }

    /// Moving the caret should restyle the lines it leaves and enters, not the whole page. Rewriting all of the text
    /// throws away the text view's layout for every line each time.
    func testArrowingRestylesOnlyTheLinesItTouches() throws {
        let view = try openInTheMiddle()
        let length = (view.text as NSString).length
        let steps = walk(.down, steps: 45, in: view) + walk(.up, steps: 45, in: view)
        let whole = steps.filter { $0.restyled > length / 2 }
        let most = steps.map(\.restyled).max() ?? 0
        let report = "The text is \(length) characters. \(whole.count) of \(steps.count) caret moves rewrote more than "
            + "half of it; the most was \(most)."
        XCTAssertTrue(whole.isEmpty, report)
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
