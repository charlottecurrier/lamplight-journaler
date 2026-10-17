import Foundation

// MARK: - Journal

struct Journal: Codable, Identifiable, Hashable {
    /// Fixed id so two devices that both create the first journal write the same file.
    static let defaultID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    var id: UUID
    var name: String
    var colorKey: String
    var sortOrder: Int
    var createdAt: Date

    static func makeDefault(now: Date = Date()) -> Journal {
        Journal(id: defaultID, name: "Journal", colorKey: JournalColors.keys[0], sortOrder: 0, createdAt: now)
    }
}

enum JournalColors {
    /// The theme maps each key to a color. Keep these short and stable: they are saved in files.
    static let keys = ["ember", "sage", "gold", "clay", "moss", "stone"]
}

// MARK: - Location

struct EntryLocation: Codable, Hashable {
    var name: String
    var latitude: Double?
    var longitude: Double?
    var isHome: Bool

    init(name: String, latitude: Double? = nil, longitude: Double? = nil, isHome: Bool = false) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isHome = isHome
    }

    enum CodingKeys: String, CodingKey {
        case name
        case latitude = "lat"
        case longitude = "lon"
        case isHome = "home"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        isHome = try c.decodeIfPresent(Bool.self, forKey: .isHome) ?? false
    }
}

// MARK: - Photos

struct PhotoRef: Codable, Identifiable, Hashable {
    var id: UUID
    var fileName: String
    var width: Int
    var height: Int

    init(id: UUID = UUID(), fileName: String, width: Int, height: Int) {
        self.id = id
        self.fileName = fileName
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fileName = "file"
        case width = "w"
        case height = "h"
    }

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

// MARK: - Entry

struct Entry: Identifiable, Hashable {
    var id: UUID
    var journalID: UUID
    var createdAt: Date
    var modifiedAt: Date
    var timeZoneID: String
    var templateID: UUID?
    var location: EntryLocation?
    var photos: [PhotoRef]
    var body: String

    init(
        id: UUID = UUID(),
        journalID: UUID,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        timeZoneID: String = TimeZone.current.identifier,
        templateID: UUID? = nil,
        location: EntryLocation? = nil,
        photos: [PhotoRef] = [],
        body: String = ""
    ) {
        self.id = id
        self.journalID = journalID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.timeZoneID = timeZoneID
        self.templateID = templateID
        self.location = location
        self.photos = photos
        self.body = body
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// An entry with no words and no photos is not worth a file.
    var isBlank: Bool {
        photos.isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func dayStamp(using calendar: DayCalendar) -> DayStamp {
        calendar.stamp(for: createdAt, timeZone: timeZone)
    }
}

// MARK: - Templates

struct EntryTemplate: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var questions: [String]
    var defaultJournalID: UUID?
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        questions: [String],
        defaultJournalID: UUID? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.questions = questions
        self.defaultJournalID = defaultJournalID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }

    /// Questions with blank ones removed and whitespace flattened to single spaces.
    var cleanQuestions: [String] {
        questions
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Library settings (synced with the journal folder)

struct LibrarySettings: Codable, Equatable {
    var home: EntryLocation?

    init(home: EntryLocation? = nil) {
        self.home = home
    }
}

// MARK: - JSON helpers

enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
