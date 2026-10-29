import SwiftUI
import UIKit
import XCTest
@testable import Lamplight

/// Types into the real editor, in a real text view, and checks that the caret stays on screen and stays level with
/// the text it belongs to. These need UIKit, so they only run in Xcode and in the Mac job on GitHub, not in
/// `swift test`.
@MainActor
final class EditorCaretTests: XCTestCase {
    private final class Box {
        var text: String
        init(_ text: String) { self.text = text }
    }

    private struct Reading {
        let step: String
        let caret: CGRect
        let visibleTop: CGFloat
        let visibleBottom: CGFloat
        let contentHeight: CGFloat

        var isInView: Bool {
            caret.minY >= visibleTop - 1 && caret.maxY <= visibleBottom + 1
        }

        var summary: String {
            String(
                format: "%@: caret %.0f to %.0f, showing %.0f to %.0f, content %.0f",
                step, caret.minY, caret.maxY, visibleTop, visibleBottom, contentHeight
            )
        }
    }

    // MARK: Setup

    private static let size = CGSize(width: 820, height: 520) // about what an iPad leaves for the page with the keyboard up

    private static func findTextView(in view: UIView) -> MarkdownUITextView? {
        if let found = view as? MarkdownUITextView { return found }
        for child in view.subviews {
            if let found = findTextView(in: child) { return found }
        }
        return nil
    }

    private static let paragraph =
        "The morning was quiet and the light came in slowly across the table, and I sat there for a long while "
        + "with the first cup of coffee going cold beside me. Nothing needed doing yet, which was the point of it."

    /// A few screens of an entry with sections, a heading and a list, ending on a line break, the way a page looks
    /// when the person comes back to add to it.
    private static func sectionedMarkdown() -> String {
        var parts: [String] = []
        for part in 1...6 {
            parts.append("--- Part \(part) ---")
            parts.append("")
            parts.append(paragraph)
            parts.append("")
            parts.append("# Things I noticed")
            parts.append("")
            parts.append("- the neighbour's radio, very faint")
            parts.append("- a bird on the wire that stayed all morning")
            parts.append("- how tired I still was")
            parts.append("")
        }
        return parts.joined(separator: "\n") + "\n"
    }

    private func settle(_ seconds: TimeInterval = 0.04) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Lamplight's own editor, as the entry page builds it.
    private func editorTextView(markdown: String) throws -> MarkdownUITextView {
        let box = Box(markdown)
        let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
        let media = MediaContext(
            photos: [], cached: { _, _ in nil }, load: { _, _ in nil }, onOpen: { _ in }, refreshToken: 0
        )
        let root = AnyView(
            MarkdownEditor(text: binding, isEditable: true, wantsFocus: false, media: media)
                .padding(.horizontal, 24)
                .frame(width: Self.size.width, height: Self.size.height)
        )
        let host = UIHostingController(rootView: root)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: Self.size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        settle(0.2)
        return try XCTUnwrap(Self.findTextView(in: host.view), "The editor's text view wasn't found.")
    }

    // MARK: Typing

    /// Types one character at a time, as the keyboard does.
    private func type(_ text: String, into view: UITextView) {
        for character in text {
            view.insertText(String(character))
            if character == " " || character == "\n" { settle(0.005) }
        }
    }

    private func reading(_ step: String, of view: UITextView) -> Reading {
        let end = view.selectedTextRange?.end ?? view.endOfDocument
        return Reading(
            step: step,
            caret: view.caretRect(for: end),
            visibleTop: view.contentOffset.y + view.adjustedContentInset.top,
            visibleBottom: view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom,
            contentHeight: view.contentSize.height
        )
    }

    // MARK: Tests

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
