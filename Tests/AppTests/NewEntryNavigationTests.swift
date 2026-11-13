import SwiftUI
import UIKit
import XCTest
@testable import Lamplight

/// Starts a new entry in the real main screen, in a phone's layout and in an iPad's, and checks that the page stays
/// open. A bug had the phone open the page and drop back to the list at once: the page was gone before it could be
/// written in.
///
/// A unit test can't tap a SwiftUI button, so the entry is started with `.lamplightNewEntry`, which runs the same
/// action as the New Entry buttons.
@MainActor
final class NewEntryNavigationTests: EditorTestCase {
    private struct Screen {
        let model: AppModel
        let window: UIWindow
        let host: UIHostingController<AnyView>
        /// What the layout looks like, for the report.
        let layout: String
    }

    private struct NoFirstEntry: Error {}

    private struct Options {
        var compact: Bool
        /// The journal starts new entries with a page of sections, as the person's does.
        var template = false
        /// The app opens to a new entry by itself, as it does by default when nothing is written yet today.
        var openToNewEntry = false
    }

    /// Waits by suspending, so the work the model started can run. Spinning the run loop in place doesn't let it.
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private let phone = CGSize(width: 390, height: 844)
    private let pad = CGSize(width: 1024, height: 768)

    private static let templateBody = """
    --- Morning ---


    --- Evening ---


    # Things I noticed

    -
    """

    private func splitViews(in controller: UIViewController) -> [UISplitViewController] {
        var found: [UISplitViewController] = []
        if let split = controller as? UISplitViewController { found.append(split) }
        for child in controller.children { found += splitViews(in: child) }
        if let presented = controller.presentedViewController { found += splitViews(in: presented) }
        return found
    }

    private func navigationControllers(in controller: UIViewController) -> [UINavigationController] {
        var found: [UINavigationController] = []
        if let navigation = controller as? UINavigationController { found.append(navigation) }
        for child in controller.children { found += navigationControllers(in: child) }
        if let presented = controller.presentedViewController { found += navigationControllers(in: presented) }
        return found
    }

    /// Goes back one screen, as the back button and the swipe from the edge do. Fails if there is nothing to go back
    /// from.
    private func goBack(_ screen: Screen) {
        let stacks = navigationControllers(in: screen.host).filter { $0.viewControllers.count > 1 }
        guard let stack = stacks.last else {
            XCTFail("There is no screen to go back from. Navigation stacks: \(navigationControllers(in: screen.host).map { $0.viewControllers.count })")
            return
        }
        stack.popViewController(animated: true)
    }

    /// The main screen over a journal in a temporary folder, with a few entries in it.
    private func openMainScreen(_ options: Options, entries: Int = 3) async throws -> Screen {
        // The Mac job runs these tests again on a phone. A wide window on a phone is not an iPad.
        if !options.compact, UIDevice.current.userInterfaceIdiom == .phone {
            throw XCTSkip("An iPad's layout needs an iPad.")
        }
        let defaults = UserDefaults.standard
        let storageKeys = ["storage.mode", "storage.bookmark", "storage.name"]
        let saved = storageKeys.map { ($0, defaults.object(forKey: $0)) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NewEntryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "NewEntryNavigationTests"
        let prefsDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        prefsDefaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            prefsDefaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        NavTrace.events = []
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

        let journal = model.defaultJournalID(for: .all)
        for number in 1...max(entries, 1) where entries > 0 {
            let id = model.beginNewEntry(journalID: journal, body: "")
            var entry = try XCTUnwrap(model.entry(id))
            entry.body = "An entry, number \(number)."
            entry.createdAt = Date().addingTimeInterval(-86_400 * 3 * Double(number))
            model.update(entry)
            model.finishEditing(id, announce: false, calendar: DayCalendar())
        }
        XCTAssertEqual(model.entries(in: .all).count, entries)

        if options.template {
            var template = model.newTemplate()
            template.name = "Day"
            template.body = Self.templateBody
            model.save(template: template)
            var chosen = try XCTUnwrap(model.journal(journal))
            chosen.defaultTemplateID = template.id
            model.save(journal: chosen)
            XCTAssertNotNil(model.defaultTemplate(for: journal), "The journal's template wasn't set.")
        }

        let prefs = AppPrefs(defaults: prefsDefaults)
        prefs.openToNewEntry = options.openToNewEntry
        let lock = LockManager(startLocked: false)
        let root = AnyView(MainView().environment(model).environment(lock).environmentObject(prefs))
        let host = UIHostingController(rootView: root)
        host.traitOverrides.horizontalSizeClass = options.compact ? .compact : .regular
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: options.compact ? phone : pad)
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        await pause(1.0)

        let splits = splitViews(in: host)
        let layout = splits.isEmpty
            ? "no split view found"
            : splits.map { "split view \($0.isCollapsed ? "collapsed" : "open")" }.joined(separator: ", ")
        if options.compact {
            XCTAssertFalse(splits.isEmpty, "No split view was found, so the layout can't be checked.")
            XCTAssertTrue(splits.allSatisfy(\.isCollapsed), "The phone layout isn't collapsed, so this isn't a phone's screen.")
        }
        return Screen(model: model, window: window, host: host, layout: layout)
    }

    /// What there is to see a moment after the entry was started.
    private func snapshot(_ step: String, _ screen: Screen) -> (ok: Bool, open: Bool, line: String) {
        let model = screen.model
        let editing = model.editingEntryID
        let found = editing.flatMap { model.entry($0) } != nil
        let editor = Self.findTextView(in: screen.host.view) != nil
        return (
            editing != nil && found && editor,
            editing != nil && found,
            "\(step): editing \(editing != nil), entry in the journal \(found), editor on screen \(editor)"
        )
    }

    private func watch(_ screen: Screen, what: String, compact: Bool) async {
        var lines: [String] = ["layout: \(screen.layout)"]
        var allOK = true
        // The entry has to be there at every look. Its editor can take a moment to be built (on a phone simulator a
        // page of sections wasn't there yet at 0.1 s), so it has to be there by the end, and stay once it is seen.
        var editorSeen = false
        let looks = [("after 0.1 s", 0.1), ("after 0.6 s", 0.5), ("after 1.6 s", 1.0), ("after 3.6 s", 2.0)]
        for (index, (step, wait)) in looks.enumerated() {
            await pause(wait)
            let result = snapshot(step, screen)
            lines.append(result.line)
            let editorDue = editorSeen || index == looks.count - 1
            allOK = allOK && result.open && (result.ok || !editorDue)
            editorSeen = editorSeen || result.ok
        }
        XCTAssertTrue(
            allOK,
            "\(what) didn't stay open in the \(compact ? "phone" : "iPad") layout.\n" + lines.joined(separator: "\n")
                + "\nWhat happened, in order:\n" + NavTrace.events.joined(separator: "\n")
        )
    }

    /// Waits for the first entry's editor, then lets the page settle. The page has four seconds to open. On a phone
    /// simulator it was once not there after 1.5, and the step log is printed so a slow page can be told from one
    /// that never came.
    private func waitForFirstEntry(_ screen: Screen) async throws {
        var waited = 0.0
        while !snapshot("", screen).ok && waited < 4 {
            await pause(0.1)
            waited += 0.1
        }
        let first = snapshot("first entry, after \(String(format: "%.1f", waited)) s", screen)
        if !first.ok {
            XCTFail("The first entry didn't open.\n" + first.line + "\nWhat happened, in order:\n" + NavTrace.events.joined(separator: "\n"))
            throw NoFirstEntry()
        }
        // The fixed wait this replaces was 1.5 s, and the steps after it were written for a page at rest.
        await pause(max(1.5 - waited, 0.5))
    }

    private func checkNewEntryStaysOpen(_ options: Options) async throws {
        let screen = try await openMainScreen(options)
        XCTAssertNil(screen.model.editingEntryID, "Nothing should be being written yet.")
        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        await watch(screen, what: "The new entry", compact: options.compact)
    }

    private func checkLaunchEntryStaysOpen(_ options: Options) async throws {
        var options = options
        options.openToNewEntry = true
        let screen = try await openMainScreen(options)
        // The app began the entry by itself when the screen appeared.
        await watch(screen, what: "The entry the app opened to", compact: options.compact)
    }

    /// Start an entry, write in it, finish it with Done, and start another. The person found the first entry after
    /// opening the app worked and the later ones didn't.
    private func checkASecondEntryStaysOpen(_ options: Options) async throws {
        let screen = try await openMainScreen(options)
        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        try await waitForFirstEntry(screen)
        let editor = try XCTUnwrap(Self.findTextView(in: screen.host.view), "The first entry has no editor.")
        _ = editor.becomeFirstResponder()
        editor.insertText("Something written in the first entry.")
        await pause(0.5)

        NotificationCenter.default.post(name: .lamplightFinishEntry, object: nil)
        await pause(1.5)
        XCTAssertNil(screen.model.editingEntryID, "The first entry wasn't finished.")
        XCTAssertEqual(screen.model.entries(in: .all).count, 4, "The first entry wasn't kept.")

        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        await watch(screen, what: "The second entry", compact: options.compact)
    }

    func testASecondEntryStaysOpenInThePhonesLayout() async throws {
        try await checkASecondEntryStaysOpen(Options(compact: true))
    }

    func testASecondEntryFromATemplateStaysOpenInThePhonesLayout() async throws {
        try await checkASecondEntryStaysOpen(Options(compact: true, template: true))
    }

    func testASecondEntryStaysOpenInTheIPadsLayout() async throws {
        try await checkASecondEntryStaysOpen(Options(compact: false))
    }

    /// The person leaves the page by swiping back instead of tapping Done, then starts another entry.
    private func checkAnEntryAfterSwipingBack(_ options: Options, writing: Bool) async throws {
        let screen = try await openMainScreen(options)
        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        try await waitForFirstEntry(screen)
        if writing {
            let editor = try XCTUnwrap(Self.findTextView(in: screen.host.view), "The first entry has no editor.")
            _ = editor.becomeFirstResponder()
            editor.insertText("Something written in the first entry.")
            await pause(0.5)
        }

        goBack(screen)
        await pause(1.5)
        XCTAssertNil(screen.model.editingEntryID, "The first entry wasn't finished by going back.")
        XCTAssertEqual(screen.model.entries(in: .all).count, writing ? 4 : 3)

        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        await watch(screen, what: "The entry after going back", compact: options.compact)
    }

    func testAnEntryAfterSwipingBackFromAWrittenOneInThePhonesLayout() async throws {
        try await checkAnEntryAfterSwipingBack(Options(compact: true), writing: true)
    }

    func testAnEntryAfterSwipingBackFromABlankOneInThePhonesLayout() async throws {
        try await checkAnEntryAfterSwipingBack(Options(compact: true), writing: false)
    }

    func testAnEntryAfterSwipingBackFromATemplateOneInThePhonesLayout() async throws {
        try await checkAnEntryAfterSwipingBack(Options(compact: true, template: true), writing: true)
    }

    // MARK: Phone

    func testANewEntryStaysOpenInThePhonesLayout() async throws {
        try await checkNewEntryStaysOpen(Options(compact: true))
    }

    func testANewEntryFromATemplateStaysOpenInThePhonesLayout() async throws {
        try await checkNewEntryStaysOpen(Options(compact: true, template: true))
    }

    func testTheEntryTheAppOpensToStaysOpenInThePhonesLayout() async throws {
        try await checkLaunchEntryStaysOpen(Options(compact: true, template: true))
    }

    /// New Entry twice with nothing in between, as two very quick taps might be. One page opens, and the entry that
    /// never got a page isn't left in the journal.
    func testTwoNewEntriesAtOnceLeaveOneOpenInThePhonesLayout() async throws {
        let screen = try await openMainScreen(Options(compact: true))
        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)
        await watch(screen, what: "The second of two entries started at once", compact: true)
        XCTAssertEqual(
            screen.model.entries(in: .all).count, 4,
            "The journal should hold its three entries and the one being written.\n" + NavTrace.events.joined(separator: "\n")
        )
    }

    // MARK: iPad

    func testANewEntryStaysOpenInTheIPadsLayout() async throws {
        try await checkNewEntryStaysOpen(Options(compact: false))
    }

    func testANewEntryFromATemplateStaysOpenInTheIPadsLayout() async throws {
        try await checkNewEntryStaysOpen(Options(compact: false, template: true))
    }
}
