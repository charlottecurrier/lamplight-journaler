import SwiftUI
import UIKit
import XCTest
@testable import Lamplight

/// What the editor tests share: the real editor in a window, some sample text, and a way to read where the caret is.
/// These need UIKit, so they only run in Xcode and in the Mac job on GitHub, not in `swift test`.
@MainActor
class EditorTestCase: XCTestCase {
    final class Box {
        var text: String
        init(_ text: String) { self.text = text }
    }

    struct Reading {
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

    // MARK: Sample text

    /// About what an iPad leaves for the page with the keyboard up.
    static let size = CGSize(width: 820, height: 520)

    static let paragraph =
        "The morning was quiet and the light came in slowly across the table, and I sat there for a long while "
        + "with the first cup of coffee going cold beside me. Nothing needed doing yet, which was the point of it."

    /// A few screens of an entry with sections, a heading and a list, ending on a line break, the way a page looks
    /// when the person comes back to add to it.
    static func sectionedMarkdown() -> String {
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

    // MARK: The editor

    static func findTextView(in view: UIView) -> MarkdownUITextView? {
        if let found = view as? MarkdownUITextView { return found }
        for child in view.subviews {
            if let found = findTextView(in: child) { return found }
        }
        return nil
    }

    func settle(_ seconds: TimeInterval = 0.04) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Lamplight's own editor, as the entry page builds it.
    func editorTextView(markdown: String) throws -> MarkdownUITextView {
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

    /// Types one character at a time, as the keyboard does.
    func type(_ text: String, into view: UITextView) {
        for character in text {
            view.insertText(String(character))
            if character == " " || character == "\n" { settle(0.005) }
        }
    }

    func reading(_ step: String, of view: UITextView) -> Reading {
        let end = view.selectedTextRange?.end ?? view.endOfDocument
        return Reading(
            step: step,
            caret: view.caretRect(for: end),
            visibleTop: view.contentOffset.y + view.adjustedContentInset.top,
            visibleBottom: view.contentOffset.y + view.bounds.height - view.adjustedContentInset.bottom,
            contentHeight: view.contentSize.height
        )
    }
}
