import Foundation
@testable import JournalCore

enum T {
    /// "2026-10-17T21:14:03Z" -> Date
    static func date(_ iso: String) -> Date {
        ISODate.date(iso)!
    }

    static func entry(
        _ iso: String,
        zone: String = "UTC",
        body: String = "text",
        journal: UUID = Journal.defaultID,
        template: UUID? = nil
    ) -> Entry {
        Entry(
            journalID: journal,
            createdAt: date(iso),
            timeZoneID: zone,
            templateID: template,
            body: body
        )
    }

    static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lamplight-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
