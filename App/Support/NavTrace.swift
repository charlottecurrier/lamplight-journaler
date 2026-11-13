import Foundation

/// A note of each step in opening and closing an entry's page, so a test can print what happened when one goes wrong.
/// It only records in a debug build, which is what the tests use.
enum NavTrace {
    static var events: [String] = []

    static func note(_ text: @autoclosure () -> String) {
        #if DEBUG
        events.append(text())
        #endif
    }

    static func short(_ id: UUID?) -> String { id.map { String($0.uuidString.prefix(4)) } ?? "none" }
}
