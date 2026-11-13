import Foundation

/// A note of each step in opening and closing an entry's page, so a test can print what happened when one goes wrong.
/// The navigation tests run only in the Mac job, and this is how a failure there gets explained.
/// It only records in a debug build, which is what the tests use, and keeps only the latest steps.
enum NavTrace {
    static var events: [String] = []
    private static let limit = 200

    static func note(_ text: @autoclosure () -> String) {
        #if DEBUG
        events.append(text())
        if events.count > limit { events.removeFirst(events.count - limit) }
        #endif
    }

    static func short(_ id: UUID?) -> String { id.map { String($0.uuidString.prefix(4)) } ?? "none" }
}
