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
    }

    private var phone: CGSize { CGSize(width: 390, height: 844) }
    private var pad: CGSize { CGSize(width: 1024, height: 768) }

    /// The main screen over a journal in a temporary folder, with a few entries in it.
    private func openMainScreen(compact: Bool, entries: Int = 3, openToNewEntry: Bool = false) async throws -> Screen {
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

        let model = AppModel()
        model.useFolder(folder)
        var waited = 0.0
        while model.phase != .ready && waited < 20 {
            settle(0.1)
            waited += 0.1
        }
        _ = try XCTUnwrap(model.phase == .ready ? model : nil, "The journal didn't open: \(model.phase)")

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

        let prefs = AppPrefs(defaults: prefsDefaults)
        prefs.openToNewEntry = openToNewEntry
        let lock = LockManager(startLocked: false)
        let root = AnyView(MainView().environment(model).environment(lock).environmentObject(prefs))
        let host = UIHostingController(rootView: root)
        if compact { host.traitOverrides.horizontalSizeClass = .compact }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: compact ? phone : pad)
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        settle(1.0)
        return Screen(model: model, window: window, host: host)
    }

    /// What there is to see a moment after the entry was started.
    private func snapshot(_ step: String, _ screen: Screen) -> (ok: Bool, line: String) {
        let model = screen.model
        let editing = model.editingEntryID
        let found = editing.flatMap { model.entry($0) } != nil
        let editor = Self.findTextView(in: screen.host.view) != nil
        return (
            editing != nil && found && editor,
            "\(step): editing \(editing != nil), entry in the journal \(found), editor on screen \(editor)"
        )
    }

    private func checkPageStaysOpen(compact: Bool) async throws {
        let screen = try await openMainScreen(compact: compact)
        XCTAssertNil(screen.model.editingEntryID, "Nothing should be being written yet.")
        NotificationCenter.default.post(name: .lamplightNewEntry, object: nil)

        var lines: [String] = []
        var allOK = true
        for (step, wait) in [("after 0.1 s", 0.1), ("after 0.6 s", 0.5), ("after 1.6 s", 1.0), ("after 3.6 s", 2.0)] {
            settle(wait)
            let result = snapshot(step, screen)
            lines.append(result.line)
            allOK = allOK && result.ok
        }
        XCTAssertTrue(
            allOK, "The new entry didn't stay open in the \(compact ? "phone" : "iPad") layout.\n" + lines.joined(separator: "\n")
        )
    }

    func testANewEntryStaysOpenInThePhonesLayout() async throws {
        try await checkPageStaysOpen(compact: true)
    }

    func testANewEntryStaysOpenInTheIPadsLayout() async throws {
        try await checkPageStaysOpen(compact: false)
    }
}
