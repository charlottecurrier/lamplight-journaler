import Foundation

/// What to use when a hand-edited entry file is missing a field.
struct EntryFileDefaults {
    var id: UUID
    var journalID: UUID
    var date: Date
}

/// Reads and writes one entry as a Markdown file with a small header.
///
///     ---
///     id: "5B0C…"
///     journal: "00000000-0000-4000-8000-000000000001"
///     created: "2026-10-17T21:14:03.000Z"
///     modified: "2026-10-17T21:30:41.000Z"
///     timezone: "America/Los_Angeles"
///     template: "…"
///     location: {"home":true,"name":"Home"}
///     photos: [{"file":"….jpg","h":1600,"id":"…","w":2400}]
///     ---
///
///     The text of the entry.
///
/// Every header value is JSON, so quotes and odd characters can't break the format.
/// The file opens fine in any text editor or Markdown app.
enum EntryFile {
    static let fileName = "entry.md"
    private static let fence = "---"

    // MARK: Encode

    static func encode(_ entry: Entry) -> Data {
        var lines: [String] = [fence]
        lines.append("id: \(json(entry.id.uuidString))")
        lines.append("journal: \(json(entry.journalID.uuidString))")
        lines.append("created: \(json(ISODate.string(entry.createdAt)))")
        lines.append("modified: \(json(ISODate.string(entry.modifiedAt)))")
        lines.append("timezone: \(json(entry.timeZoneID))")
        if let templateID = entry.templateID {
            lines.append("template: \(json(templateID.uuidString))")
        }
        if let location = entry.location {
            lines.append("location: \(json(location))")
        }
        if !entry.photos.isEmpty {
            lines.append("photos: \(json(entry.photos))")
        }
        lines.append(fence)
        lines.append("")
        let text = lines.joined(separator: "\n") + "\n" + entry.body
        return Data(text.utf8)
    }

    // MARK: Decode

    static func decode(_ data: Data, defaults: EntryFileDefaults) -> Entry {
        let text = String(decoding: data, as: UTF8.self)
        let lines = splitLines(data)

        var fields: [String: String] = [:]
        var body = text

        if let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == fence,
           let close = lines.indices.dropFirst().first(where: {
               lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == fence
           }) {
            for line in lines[1..<close] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { fields[key] = value }
            }
            var bodyLines = Array(lines[(close + 1)...])
            if bodyLines.first == "" { bodyLines.removeFirst() }
            body = bodyLines.joined(separator: "\n")
        }

        let created = fields["created"].flatMap { ISODate.date(unquoted($0)) } ?? defaults.date
        let modified = fields["modified"].flatMap { ISODate.date(unquoted($0)) } ?? created

        return Entry(
            id: fields["id"].flatMap { UUID(uuidString: unquoted($0)) } ?? defaults.id,
            journalID: fields["journal"].flatMap { UUID(uuidString: unquoted($0)) } ?? defaults.journalID,
            createdAt: created,
            modifiedAt: modified,
            timeZoneID: fields["timezone"].map(unquoted) ?? TimeZone.current.identifier,
            templateID: fields["template"].flatMap { UUID(uuidString: unquoted($0)) },
            location: fields["location"].flatMap { decodeValue(EntryLocation.self, from: $0) },
            photos: fields["photos"].flatMap { decodeValue([PhotoRef].self, from: $0) } ?? [],
            body: body
        )
    }

    // MARK: Helpers

    /// Splits on the "\n" byte. Swift treats "\r\n" as one character, so splitting the String would miss it.
    /// A "\r" stays at the end of its line and is trimmed where headers are read.
    private static func splitLines(_ data: Data) -> [String] {
        data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeValue<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    /// A JSON string value without its quotes. Also accepts a bare value someone typed by hand.
    private static func unquoted(_ raw: String) -> String {
        if let s = decodeValue(String.self, from: raw) { return s }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }
}

enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date) -> String { withFraction.string(from: date) }

    static func date(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
