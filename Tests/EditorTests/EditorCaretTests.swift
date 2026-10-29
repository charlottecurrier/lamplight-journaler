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
        let offset: CGFloat
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
        var readings: [Reading] = []
        var drift: CGFloat = 0
        var nonContiguous = true

        var outOfView: [Reading] { readings.filter { !$0.isInView } }
    }

    // MARK: Setup

    private static func findTextView(in view: UIView) -> MarkdownUITextView? {
        if let found = view as? MarkdownUITextView { return found }
        for child in view.subviews {
            if let found = findTextView(in: child) { return found }
        }
        return nil
    }

    /// A few screens of an entry with sections, a heading and a list, ending on a line break, the way a page looks
    /// when the person comes back to add to it.
    private static func sampleMarkdown() -> String {
        var parts: [String] = []
        for part in 1...6 {
            parts.append("--- Part \(part) ---")
            parts.append("")
            parts.append(
                "The morning was quiet and the light came in slowly across the table, and I sat there for a long "
                    + "while with the first cup of coffee going cold beside me. Nothing needed doing yet, which was "
                    + "the point of it."
            )
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
            offset: view.contentOffset.y,
            visibleTop: view.contentOffset.y + view.adjustedContentInset.top,
            visibleBottom: view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom,
            contentHeight: view.contentSize.height
        )
    }

    /// Opens the editor on a long entry, goes to the end and types several paragraphs.
    /// `nonContiguous` overrides how the text is laid out, to compare the two.
    private func typeAtTheEnd(nonContiguous: Bool?) throws -> Run {
        // About the room an iPad leaves for the page with the keyboard up.
        let size = CGSize(width: 820, height: 520)
        let box = Box(Self.sampleMarkdown())
        let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
        let media = MediaContext(
            photos: [], cached: { _, _ in nil }, load: { _, _ in nil }, onOpen: { _ in }, refreshToken: 0
        )
        let root = AnyView(
            MarkdownEditor(text: binding, isEditable: true, wantsFocus: false, media: media)
                .padding(.horizontal, 24)
                .frame(width: size.width, height: size.height)
        )
        let host = UIHostingController(rootView: root)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        settle(0.2)

        let view = try XCTUnwrap(Self.findTextView(in: host.view), "The editor's text view wasn't found.")
        if let nonContiguous { view.layoutManager.allowsNonContiguousLayout = nonContiguous }
        var run = Run()
        run.nonContiguous = view.layoutManager.allowsNonContiguousLayout

        XCTAssertTrue(view.becomeFirstResponder(), "The text view wouldn't take focus.")
        let length = (view.text as NSString).length
        view.selectedRange = NSRange(location: length, length: 0)
        view.scrollRangeToVisible(view.selectedRange)
        settle(0.2)
        run.readings.append(reading("at the end, before typing", of: view))

        let sentence = "Then the rain started, and I watched it run down the glass for a while. "
        for round in 1...10 {
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
        let after = view.caretRect(for: end)
        run.drift = after.minY - before.minY
        return run
    }

    private func describe(_ run: Run) -> String {
        let bad = run.outOfView
        let shown = bad.prefix(6).map(\.summary).joined(separator: "\n")
        return "non-contiguous layout \(run.nonContiguous); \(bad.count) of \(run.readings.count) readings had the caret "
            + "out of view; the caret moved \(run.drift) when the whole page was laid out.\n\(shown)"
    }

    // MARK: Tests

    func testCaretStaysInViewWhileTyping() throws {
        let run = try typeAtTheEnd(nonContiguous: nil)
        XCTAssertTrue(run.outOfView.isEmpty, describe(run))
    }

    func testCaretStaysWhereTheTextIs() throws {
        let run = try typeAtTheEnd(nonContiguous: nil)
        XCTAssertLessThan(abs(run.drift), 1, describe(run))
    }

    /// For comparison while finding the cause: the same typing with the whole page laid out up front.
    func testCaretStaysInViewWithTheWholePageLaidOut() throws {
        let run = try typeAtTheEnd(nonContiguous: false)
        XCTAssertTrue(run.outOfView.isEmpty, describe(run))
        XCTAssertLessThan(abs(run.drift), 1, describe(run))
    }
}
