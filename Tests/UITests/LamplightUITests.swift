import XCTest

/// Runs the real app in a simulator and uses it the way a person does: taps, typing, going back.
///
/// The other tests call the app's code. These tap its buttons, so they catch what only shows when the whole app is
/// running, and they save a picture of the screen at each step. The Mac job keeps the pictures.
///
/// The app is started with a journal on the device, past the first-run screens, with no lock, and without opening
/// to a new entry by itself. Entries written by one test are still there for the next, so nothing here counts them.
final class LamplightUITests: XCTestCase {
    private var app: XCUIApplication!

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-storage.mode", "local",
            "-prefs.onboardingComplete", "YES",
            "-prefs.lockEnabled", "NO",
            "-prefs.openToNewEntry", "NO",
        ]
        // An iPad held upright shows only the page. On its side it shows the list beside it, which the tests read.
        if !isPhone { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launch()
        if find("New Entry", timeout: 20) == nil {
            describeScreen("journal didn't open")
            shot("journal didn't open")
            XCTFail("The journal didn't open: there is nothing labelled New Entry.")
        }
    }

    // MARK: Helpers

    /// Saves a picture of the screen under a name, kept whether the test passes or fails.
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(isPhone ? "phone" : "ipad") \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first thing on screen with this label, of any kind. One that can be tapped is preferred: a screen can
    /// hold more than one New Entry button, and some are behind others.
    private func find(_ label: String, timeout: TimeInterval = 5) -> XCUIElement? {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        let deadline = Date().addingTimeInterval(timeout)
        var fallback: XCUIElement?
        repeat {
            let matches = query.allElementsBoundByIndex.filter(\.exists)
            if let hittable = matches.first(where: \.isHittable) { return hittable }
            fallback = matches.first
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return fallback
    }

    /// Kept for the tests' wording: something to tap with this label, or nil.
    private func firstHittable(_ label: String, timeout: TimeInterval = 5) -> XCUIElement? {
        find(label, timeout: timeout)
    }

    /// Writes down everything the test can see on screen, for when it can't find what it wants.
    private func describeScreen(_ name: String) {
        let text = app.debugDescription
        let attachment = XCTAttachment(string: text)
        attachment.name = "\(isPhone ? "phone" : "ipad") \(name) tree"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SCREEN TREE (\(name)):\n\(text)")
    }

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        guard let element = find(label) else {
            describeScreen("no \(label)")
            shot("no \(label)")
            XCTFail("There is nothing labelled \"\(label)\" to tap.", file: file, line: line)
            throw NothingToTap()
        }
        press(element)
    }

    private struct NothingToTap: Error {}

    /// Taps where a thing is. The app lays a see-through layer over every screen for its lamp light, and the test
    /// tools count that as covering what is under it, so "can this be tapped" says no for things that can.
    private func press(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The page being written: its text and its Done button.
    private var editor: XCUIElement { app.textViews.firstMatch }
    private var done: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Done")).firstMatch
    }

    private func startEntry(file: StaticString = #filePath, line: UInt = #line) throws {
        try tap("New Entry", file: file, line: line)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The new entry's page didn't open.", file: file, line: line)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The new entry has no Done button.", file: file, line: line)
    }

    /// Types a line no other entry has, and returns it.
    private func write(_ what: String) -> String {
        let text = "\(what) \(UUID().uuidString.prefix(6))"
        press(editor)
        editor.typeText(text)
        return text
    }

    private func anything(saying text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Checks the page is still there after a few seconds. The bug this guards against closed it within one.
    private func assertPageStaysOpen(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(editor.exists && done.exists, "\(what) didn't stay open.", file: file, line: line)
    }

    // MARK: Tests

    func testWritingAnEntryAndFinishingIt() throws {
        shot("1 journal")
        try startEntry()
        shot("2 new entry")
        let text = write("Written by a test")
        shot("3 entry with text")
        press(done)
        XCTAssertTrue(anything(saying: text).waitForExistence(timeout: 10), "The finished entry isn't in the journal.")
        shot("4 journal after Done")
    }

    /// The first new entry after the app started stayed open and every later one closed at once.
    func testASecondEntryStaysOpen() throws {
        try startEntry()
        _ = write("First of two")
        press(done)
        XCTAssertTrue(firstHittable("New Entry", timeout: 10) != nil, "The journal didn't come back after Done.")
        try startEntry()
        assertPageStaysOpen("The second entry")
        shot("second entry")
        _ = write("Second of two")
        press(done)
    }

    /// The same, leaving the first entry with the back button instead of Done. Only a phone has that button.
    func testAnEntryAfterGoingBackStaysOpen() throws {
        try XCTSkipUnless(isPhone, "Only a phone leaves the page with a back button.")
        try startEntry()
        _ = write("Left with the back button")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "There is no back button.")
        press(back)
        XCTAssertTrue(firstHittable("New Entry", timeout: 10) != nil, "The journal didn't come back after going back.")
        try startEntry()
        assertPageStaysOpen("The entry after going back")
        shot("entry after going back")
        _ = write("After going back")
        press(done)
    }

    func testReadingAnEntry() throws {
        try startEntry()
        let text = write("To be read")
        press(done)
        let row = anything(saying: text)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The finished entry isn't in the journal.")
        press(row)
        XCTAssertTrue(firstHittable("Edit", timeout: 10) != nil, "The entry didn't open for reading.")
        shot("reading an entry")
    }

    /// Goes round the other screens and keeps a picture of each. It checks nothing: the pictures are the point.
    func testPicturesOfTheOtherScreens() throws {
        for screen in ["Today", "Calendar", "Journal"] {
            guard let button = firstHittable(screen, timeout: 3) else { continue }
            press(button)
            Thread.sleep(forTimeInterval: 1)
            shot("screen \(screen)")
        }
        if let settings = firstHittable("Settings", timeout: 3) {
            press(settings)
            Thread.sleep(forTimeInterval: 1)
            shot("screen Settings")
        }
    }
}
