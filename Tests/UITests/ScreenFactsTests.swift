import XCTest

/// Starts the app and writes down how big the screen is and where the controls sit, with a picture of each. Run it on
/// the iPhone Duo's simulator to see how the app lays out there. It checks very little. Its job is to show.
///
/// The facts are printed in the log as lines that start with FACTS, and kept as text next to each picture.
final class ScreenFactsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-storage.mode", "local",
            "-prefs.onboardingComplete", "YES",
            "-prefs.lockEnabled", "NO",
            "-prefs.openToNewEntry", "NO",
        ]
        app.launch()
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Prints the screen's size, and every button with its place, and says which buttons stick out past the window.
    private func report(_ name: String) {
        let window = app.windows.firstMatch.frame
        var lines = [
            "FACTS \(name): device \(UIDevice.current.name), window \(Int(window.width)) x \(Int(window.height)) points, "
                + "screen \(Int(UIScreen.main.bounds.width)) x \(Int(UIScreen.main.bounds.height)), "
                + "orientation \(XCUIDevice.shared.orientation.rawValue)"
        ]
        var outside = 0
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            let frame = button.frame
            let sticksOut = frame.minX < window.minX - 1 || frame.maxX > window.maxX + 1
                || frame.minY < window.minY - 1 || frame.maxY > window.maxY + 1
            if sticksOut { outside += 1 }
            lines.append(
                "FACTS \(name): button \"\(button.label)\" at \(Int(frame.minX)),\(Int(frame.minY)) size "
                    + "\(Int(frame.width)) x \(Int(frame.height))\(sticksOut ? "  STICKS OUT" : "")"
            )
        }
        lines.append("FACTS \(name): \(outside) buttons stick out past the window")
        let text = lines.joined(separator: "\n")
        print(text)

        let facts = XCTAttachment(string: text + "\n\n" + app.debugDescription)
        facts.name = "\(name) facts"
        facts.lifetime = .keepAlways
        add(facts)
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = name
        picture.lifetime = .keepAlways
        add(picture)
    }

    func testTheListAndAnOpenPage() throws {
        XCTAssertTrue(element("New Entry").waitForExistence(timeout: 60), "The journal didn't open.")
        report("list")

        element("New Entry").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10), "The new entry's page didn't open.")
        Thread.sleep(forTimeInterval: 1)
        report("page")

        // Rotating shows the other layout the size classes give, if the device allows it.
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        report("page on its side")
    }
}
