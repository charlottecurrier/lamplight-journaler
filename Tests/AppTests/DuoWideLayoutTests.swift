import SwiftUI
import UIKit
import XCTest
@testable import Lamplight

/// Shows the real main screen in windows the size of the iPhone Duo's inner screen, and writes down what it sees: how
/// wide each column of the split view is, where the page's buttons sit, and a picture of each step. It checks very
/// little. Its job is to show, because nothing else can open the Duo and look.
///
/// The inner screen's size in points isn't known for certain. Two sizes have been reported for the 7.6 inch display,
/// 626 x 890 and 669 x 951, so each is tried upright and on its side. The window is given the regular size class, as
/// the Duo gives its open screen. `docs/DISCOVERIES.md` says why the facts matter.
///
/// The facts are lines that start with FACTS. They are kept as text next to each picture, and the Mac job prints them.
/// The test fails only when it can't look: the journal doesn't open, or there is no split view to measure.
@MainActor
final class DuoWideLayoutTests: EditorTestCase {
    private struct Screen {
        let model: AppModel
        let window: UIWindow
        let host: UIHostingController<AnyView>
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func splitViews(in controller: UIViewController) -> [UISplitViewController] {
        var found: [UISplitViewController] = []
        if let split = controller as? UISplitViewController { found.append(split) }
        for child in controller.children { found += splitViews(in: child) }
        if let presented = controller.presentedViewController { found += splitViews(in: presented) }
        return found
    }

    /// The main screen over a journal in a temporary folder, in a window of the given size, with the regular size class.
    private func openMainScreen(size: CGSize) async throws -> Screen {
        let defaults = UserDefaults.standard
        let storageKeys = ["storage.mode", "storage.bookmark", "storage.name"]
        let saved = storageKeys.map { ($0, defaults.object(forKey: $0)) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DuoWideTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "DuoWideLayoutTests"
        let prefsDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        prefsDefaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            prefsDefaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        let model = AppModel()
        model.useFolder(folder)
        var waited = 0.0
        while model.phase != .ready && waited < 20 {
            await pause(0.1)
            waited += 0.1
        }
        _ = try XCTUnwrap(
            model.phase == .ready ? model : nil,
            "The journal didn't open: \(model.phase), \(model.loadingStep), \(model.loadedCount) of \(model.totalCount)"
        )

        // A few entries, so the list has something to show. The words are not the person's.
        let journal = model.defaultJournalID(for: .all)
        for number in 1...6 {
            let id = model.beginNewEntry(journalID: journal, body: "")
            var entry = try XCTUnwrap(model.entry(id))
            entry.body = "An entry, number \(number). The light came in slowly across the table."
            entry.createdAt = Date().addingTimeInterval(-86_400 * 3 * Double(number))
            model.update(entry)
            model.finishEditing(id, announce: false, calendar: DayCalendar())
        }

        let prefs = AppPrefs(defaults: prefsDefaults)
        prefs.openToNewEntry = false
        let lock = LockManager(startLocked: false)
        let root = AnyView(MainView().environment(model).environment(lock).environmentObject(prefs))
        let host = UIHostingController(rootView: root)
        host.traitOverrides.horizontalSizeClass = .regular
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
        await pause(1.0)
        return Screen(model: model, window: window, host: host)
    }

    /// The place of every button the screen offers to accessibility, in the window's own coordinates. SwiftUI's buttons
    /// aren't views of their own, so they are found through the accessibility tree.
    private func buttons(in screen: Screen) -> [(label: String, frame: CGRect)] {
        var found: [(label: String, frame: CGRect)] = []
        var seen = Set<ObjectIdentifier>()

        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if object.accessibilityTraits.contains(.button), let label = object.accessibilityLabel, !label.isEmpty {
                let inScreen = object.accessibilityFrame
                let inWindow = screen.window.convert(inScreen, from: screen.window.screen.coordinateSpace)
                found.append((label, inWindow))
            }
            if let elements = object.accessibilityElements {
                for element in elements {
                    if let element = element as? NSObject { visit(element, depth: depth + 1) }
                }
            }
            if let view = object as? UIView {
                for subview in view.subviews { visit(subview, depth: depth + 1) }
            }
        }
        visit(screen.window, depth: 0)
        return found
    }

    /// Writes down what the screen looks like now, keeps it as text and a picture, and returns the text.
    @discardableResult
    private func report(_ name: String, _ screen: Screen) -> String {
        let window = screen.window
        let size = window.bounds.size
        var lines = [
            "FACTS \(name): device \(UIDevice.current.name), window \(Int(size.width)) x \(Int(size.height)) points, "
                + "size class \(screen.host.traitCollection.horizontalSizeClass == .regular ? "regular" : "other")"
        ]

        let splits = splitViews(in: screen.host)
        if splits.isEmpty { lines.append("FACTS \(name): no split view found") }
        for split in splits {
            lines.append(
                "FACTS \(name): split view \(split.isCollapsed ? "collapsed" : "open"), "
                    + "style \(split.style.rawValue), display mode \(split.displayMode.rawValue)"
            )
            let columns: [(UISplitViewController.Column, String)] = [
                (.primary, "sidebar"), (.supplementary, "list"), (.secondary, "page"),
            ]
            for (column, label) in columns {
                guard let controller = split.viewController(for: column) else {
                    lines.append("FACTS \(name): \(label) column: none")
                    continue
                }
                let frame = controller.view.convert(controller.view.bounds, to: window)
                let offScreen = frame.maxX <= 0 || frame.minX >= size.width
                lines.append(
                    "FACTS \(name): \(label) column from \(Int(frame.minX)) to \(Int(frame.maxX)), "
                        + "\(Int(frame.width)) wide\(offScreen ? ", off screen" : "")"
                )
            }
        }

        if let text = Self.findTextView(in: screen.host.view) {
            let frame = text.convert(text.bounds, to: window)
            lines.append("FACTS \(name): text view from \(Int(frame.minX)) to \(Int(frame.maxX)), \(Int(frame.width)) wide")
        }

        var outside = 0
        for button in buttons(in: screen) {
            let frame = button.frame
            let sticksOut = frame.minX < -1 || frame.maxX > size.width + 1 || frame.minY < -1 || frame.maxY > size.height + 1
            if sticksOut { outside += 1 }
            lines.append(
                "FACTS \(name): button \"\(button.label)\" at \(Int(frame.minX)),\(Int(frame.minY)) "
                    + "size \(Int(frame.width)) x \(Int(frame.height))\(sticksOut ? "  STICKS OUT" : "")"
            )
        }
        lines.append("FACTS \(name): \(outside) buttons stick out past the window")

        let output = lines.joined(separator: "\n")
        print(output)
        let facts = XCTAttachment(string: output)
        facts.name = "\(name) facts"
        facts.lifetime = .keepAlways
        add(facts)

        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if drawn {
            let picture = XCTAttachment(image: image)
            picture.name = name
            picture.lifetime = .keepAlways
            add(picture)
        }
        return output
    }

    /// The list with nothing open, then a new entry (which takes the whole screen here), then back to the list.
    private func look(_ label: String, size: CGSize) async throws {
        let screen = try await openMainScreen(size: size)

        let list = report("\(label) list", screen)
        XCTAssertFalse(splitViews(in: screen.host).isEmpty, "No split view was found, so the layout can't be measured.\n\(list)")

        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        var waited = 0.0
        while Self.findTextView(in: screen.host.view) == nil && waited < 5 {
            await pause(0.1)
            waited += 0.1
        }
        // The columns slide away over a third of a second.
        await pause(1.0)
        let page = report("\(label) new page", screen)
        XCTAssertNotNil(Self.findTextView(in: screen.host.view), "The new entry's page didn't open.\n\(page)")

        NotificationCenter.default.post(name: .lamplightFinishEntry, object: nil)
        await pause(1.5)
        report("\(label) list again", screen)
    }

    func testTheInnerScreenAt626By890() async throws {
        try await look("626x890", size: CGSize(width: 626, height: 890))
    }

    func testTheInnerScreenAt669By951() async throws {
        try await look("669x951", size: CGSize(width: 669, height: 951))
    }

    func testTheInnerScreenAt890By626OnItsSide() async throws {
        try await look("890x626", size: CGSize(width: 890, height: 626))
    }

    func testTheInnerScreenAt951By669OnItsSide() async throws {
        try await look("951x669", size: CGSize(width: 951, height: 669))
    }
}
