import SwiftUI
import UIKit
import XCTest
@testable import Lamplight

/// Takes pictures of the screens that are hard to reach by tapping: the loading screen, which is gone in a moment,
/// and the pages with nothing on them. The Mac job keeps the pictures with the UI tests' pictures, so a change to
/// one of these screens can be looked at. They check only that each screen draws.
@MainActor
final class QuietScreenPictureTests: XCTestCase {
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Shows a view in a window of its own, waits for it to settle, and keeps a picture of it under `name`.
    private func picture<Content: View>(
        _ name: String,
        style: UIUserInterfaceStyle = .dark,
        size: CGSize = CGSize(width: 390, height: 700),
        wait: Double = 2.2,
        @ViewBuilder _ content: () -> Content
    ) async {
        let root = content()
            .tint(Theme.accent)
            .foregroundStyle(Theme.ink)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = style
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        await pause(wait)

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size, size, "The picture of \(name) is the wrong size.")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLoadingScreen() async {
        let model = AppModel()
        await picture("loading before the light", wait: 0.1) { LoadingView().environment(model) }
        await picture("loading dark") { LoadingView().environment(model) }
        await picture("loading light", style: .light) { LoadingView().environment(model) }
        model.loadingStep = "Reading your entries"
        model.loadedCount = 212
        model.totalCount = 840
        await picture("loading with a count") { LoadingView().environment(model) }
    }

    func testEmptyPages() async {
        await picture("empty journal dark") {
            EmptyStateView(
                title: "A blank page",
                message: "Your entries will gather here.",
                actionTitle: "Write an entry",
                action: {}
            )
            .background(PaperBackground())
        }
        await picture("empty journal light", style: .light) {
            EmptyStateView(
                title: "A blank page",
                message: "Your entries will gather here.",
                actionTitle: "Write an entry",
                action: {}
            )
            .background(PaperBackground())
        }
        await picture("no entry chosen", size: CGSize(width: 700, height: 700)) {
            DetailPlaceholder(onCompose: { _ in })
        }
        await picture("no matches") {
            EmptyStateView(title: "No matches", message: "Nothing in this journal has those words.")
                .background(PaperBackground())
        }
    }
}
