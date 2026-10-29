import SwiftUI
import UIKit
import XCTest
@testable import Lamplight

/// Types into the real editor, in a real text view, and checks that the caret stays where the text is and stays on
/// screen. These need UIKit, so they only run in Xcode and in the Mac job on GitHub, not in `swift test`.
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

    private struct Run {
        var label = ""
        var readings: [Reading] = []
        var drift: CGFloat = 0

        var outOfView: [Reading] { readings.filter { !$0.isInView } }

        var summary: String {
            let bad = outOfView
            var lines = ["\(label): \(bad.count) of \(readings.count) readings had the caret out of view; "
                + "the caret moved \(drift) when the whole page was laid out."]
            if let first = readings.first { lines.append("  first: " + first.summary) }
            lines += bad.prefix(4).map { "  out: " + $0.summary }
            if let last = readings.last { lines.append("  last: " + last.summary) }
            return lines.joined(separator: "\n")
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

    /// The same amount of writing as plain paragraphs.
    private static func plainMarkdown() -> String {
        Array(repeating: paragraph + "\n", count: 12).joined(separator: "\n") + "\n"
    }

    private static let paragraph =
        "The morning was quiet and the light came in slowly across the table, and I sat there for a long while "
        + "with the first cup of coffee going cold beside me. Nothing needed doing yet, which was the point of it."

    private func settle(_ seconds: TimeInterval = 0.04) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func show(_ controller: UIViewController) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: Self.size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        settle(0.2)
        return window
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
        _ = show(host)
        return try XCTUnwrap(Self.findTextView(in: host.view), "The editor's text view wasn't found.")
    }

    /// An ordinary text view, for comparison.
    private func stockTextView(markdown: String, textKit1: Bool) -> UITextView {
        let view = UITextView(usingTextLayoutManager: !textKit1)
        view.font = .systemFont(ofSize: 20)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 24, bottom: 40, right: 24)
        view.text = markdown
        let controller = UIViewController()
        controller.view.addSubview(view)
        view.frame = CGRect(origin: .zero, size: Self.size)
        _ = show(controller)
        return view
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

    /// Goes to the end of the text and types several paragraphs, noting where the caret is after each step.
    private func typeAtTheEnd(_ label: String, in view: UITextView) -> Run {
        var run = Run()
        run.label = label
        XCTAssertTrue(view.becomeFirstResponder(), "The text view wouldn't take focus.")
        let length = (view.text as NSString).length
        view.selectedRange = NSRange(location: length, length: 0)
        view.scrollRangeToVisible(view.selectedRange)
        settle(0.2)
        run.readings.append(reading("at the end, before typing", of: view))

        let sentence = "Then the rain started, and I watched it run down the glass for a while. "
        for round in 1...6 {
            type(sentence, into: view)
            settle()
            run.readings.append(reading("round \(round), after a sentence", of: view))
            type("\n", into: view)
            settle()
            run.readings.append(reading("round \(round), after a line break", of: view))
            type("\n", into: view)
            settle()
            run.readings.append(reading("round \(round), after a second line break", of: view))
        }

        // The caret as laid out so far, against the caret once the whole page is laid out.
        let end = view.selectedTextRange?.end ?? view.endOfDocument
        let before = view.caretRect(for: end)
        view.layoutManager.ensureLayout(for: view.textContainer)
        run.drift = view.caretRect(for: end).minY - before.minY
        return run
    }

    // MARK: Tests

    func testEditorKeepsTheCaretInViewWhileTyping() throws {
        let run = typeAtTheEnd("editor, sections", in: try editorTextView(markdown: Self.sectionedMarkdown()))
        XCTAssertTrue(run.outOfView.isEmpty, run.summary)
    }

    func testAnOrdinaryTextViewKeepsTheCaretInView() {
        let run = typeAtTheEnd("stock TextKit 1", in: stockTextView(markdown: Self.plainMarkdown(), textKit1: true))
        XCTAssertTrue(run.outOfView.isEmpty, run.summary)
    }

    /// Temporary: always fails, to print how every setup behaves. Removed once the cause is found.
    func testInvestigation() throws {
        var report: [String] = []
        report.append(typeAtTheEnd("editor, sections", in: try editorTextView(markdown: Self.sectionedMarkdown())).summary)
        report.append(typeAtTheEnd("editor, plain", in: try editorTextView(markdown: Self.plainMarkdown())).summary)
        report.append(typeAtTheEnd("stock TextKit 1, plain", in: stockTextView(markdown: Self.plainMarkdown(), textKit1: true)).summary)
        let editor = try editorTextView(markdown: Self.sectionedMarkdown())
        editor.layoutManager.allowsNonContiguousLayout = false
        report.append(typeAtTheEnd("editor, sections, whole page laid out", in: editor).summary)
        XCTFail("\n" + report.joined(separator: "\n"))
    }
}
