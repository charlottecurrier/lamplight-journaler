import Foundation

// MARK: - Folder layout

/// Where everything lives inside the journal folder:
///
///     Lamplight/
///       settings.json
///       Journals/<id>.json
///       Templates/<id>.json
///       Entries/<id>/entry.md
///       Entries/<id>/photos/<photo-id>.jpg
///       Recently Deleted/<id>/…
///
/// Every entry, journal and template is its own file, so two devices rarely touch the same file.
struct LibraryLayout {
    static let folderName = "Lamplight"

    let root: URL

    var journalsDir: URL { root.appendingPathComponent("Journals", isDirectory: true) }
    var templatesDir: URL { root.appendingPathComponent("Templates", isDirectory: true) }
    var entriesDir: URL { root.appendingPathComponent("Entries", isDirectory: true) }
    var trashDir: URL { root.appendingPathComponent("Recently Deleted", isDirectory: true) }
    var settingsFile: URL { root.appendingPathComponent("settings.json", isDirectory: false) }

    func journalFile(_ id: UUID) -> URL {
        journalsDir.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    func templateFile(_ id: UUID) -> URL {
        templatesDir.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    func entryDir(_ id: UUID) -> URL {
        entriesDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func entryFile(_ id: UUID) -> URL {
        entryDir(id).appendingPathComponent(EntryFile.fileName, isDirectory: false)
    }

    func photosDir(_ entryID: UUID) -> URL {
        entryDir(entryID).appendingPathComponent("photos", isDirectory: true)
    }

    func photoURL(entryID: UUID, fileName: String) -> URL {
        photosDir(entryID).appendingPathComponent(fileName, isDirectory: false)
    }

    func trashEntryDir(_ id: UUID) -> URL {
        trashDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func trashMarker(_ id: UUID) -> URL {
        trashEntryDir(id).appendingPathComponent("deleted.json", isDirectory: false)
    }
}

enum LibraryLocator {
    /// The user picks a folder in the Files app. Decide which folder is the library.
    ///
    /// - A "Lamplight" folder inside the pick is used (this is the second device finding the first one's data).
    /// - A pick that is already a library (named Lamplight, or holding an Entries folder) is used as is.
    /// - Otherwise a "Lamplight" folder is made inside the pick, so we never scatter folders in iCloud Drive's root.
    static func resolveRoot(picked: URL, files: FileAccess) -> URL {
        let items = (try? files.list(picked)) ?? []
        if let existing = items.first(where: { $0.isDirectory && $0.name == LibraryLayout.folderName }) {
            return existing.url
        }
        if picked.lastPathComponent == LibraryLayout.folderName
            || items.contains(where: { $0.isDirectory && $0.name == "Entries" }) {
            return picked
        }
        return picked.appendingPathComponent(LibraryLayout.folderName, isDirectory: true)
    }
}

// MARK: - Library

struct TrashedEntry: Identifiable {
    var entry: Entry
    var deletedAt: Date
    var id: UUID { entry.id }
}

struct LoadResult {
    var entries: [Entry]
    var failedIDs: [UUID]
}

enum LibraryError: Error {
    case alreadyExists
}

/// Reads and writes the journal folder. Holds no state besides where the folder is,
/// so it is safe to call from background tasks.
final class Library {
    let layout: LibraryLayout
    private let files: FileAccess

    init(root: URL, files: FileAccess = PlainFileAccess()) {
        self.layout = LibraryLayout(root: root)
        self.files = files
    }

    /// Creates the folders, and the first journal if there are none.
    func prepare() throws {
        for dir in [layout.root, layout.journalsDir, layout.templatesDir, layout.entriesDir, layout.trashDir] {
            try files.createDirectory(dir)
        }
        if loadJournals().isEmpty {
            try save(Journal.makeDefault())
        }
    }

    // MARK: Journals

    func loadJournals() -> [Journal] {
        let items = (try? files.list(layout.journalsDir)) ?? []
        let journals: [Journal] = items.compactMap { item in
            guard !item.isDirectory, item.name.hasSuffix(".json"),
                  let data = try? files.read(item.url) else { return nil }
            return try? JSONCoding.decoder().decode(Journal.self, from: data)
        }
        return journals.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func save(_ journal: Journal) throws {
        try files.write(try JSONCoding.encoder().encode(journal), to: layout.journalFile(journal.id))
    }

    func deleteJournal(id: UUID) throws {
        try files.remove(layout.journalFile(id))
    }

    // MARK: Templates

    func loadTemplates() -> [EntryTemplate] {
        let items = (try? files.list(layout.templatesDir)) ?? []
        let templates: [EntryTemplate] = items.compactMap { item in
            guard !item.isDirectory, item.name.hasSuffix(".json"),
                  let data = try? files.read(item.url) else { return nil }
            return try? JSONCoding.decoder().decode(EntryTemplate.self, from: data)
        }
        return templates.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func save(_ template: EntryTemplate) throws {
        try files.write(try JSONCoding.encoder().encode(template), to: layout.templateFile(template.id))
    }

    func deleteTemplate(id: UUID) throws {
        try files.remove(layout.templateFile(id))
    }

    // MARK: Settings

    func loadSettings() -> LibrarySettings {
        guard let data = try? files.read(layout.settingsFile),
              let settings = try? JSONCoding.decoder().decode(LibrarySettings.self, from: data) else {
            return LibrarySettings()
        }
        return settings
    }

    func save(_ settings: LibrarySettings) throws {
        try files.write(try JSONCoding.encoder().encode(settings), to: layout.settingsFile)
    }

    // MARK: Entries

    func entryIDs() throws -> [UUID] {
        try files.list(layout.entriesDir).compactMap { item in
            item.isDirectory ? UUID(uuidString: item.name) : nil
        }
    }

    func loadEntry(id: UUID) throws -> Entry {
        let data = try files.read(layout.entryFile(id))
        var entry = EntryFile.decode(
            data,
            defaults: EntryFileDefaults(id: id, journalID: Journal.defaultID, date: Date())
        )
        entry.id = id
        return entry
    }

    func loadAllEntries() -> LoadResult {
        var entries: [Entry] = []
        var failed: [UUID] = []
        for id in (try? entryIDs()) ?? [] {
            if let entry = try? loadEntry(id: id) {
                entries.append(entry)
            } else {
                failed.append(id)
            }
        }
        return LoadResult(entries: entries, failedIDs: failed)
    }

    func save(_ entry: Entry) throws {
        try files.write(EntryFile.encode(entry), to: layout.entryFile(entry.id))
    }

    /// Two devices edited the same entry. The newest one stays; the others are saved as new entries
    /// so nothing is lost. Returns the copies that were made.
    func resolveConflicts(for entry: Entry) -> [Entry] {
        let url = layout.entryFile(entry.id)
        let versions = files.conflictVersions(at: url)
        guard !versions.isEmpty else { return [] }

        var copies: [Entry] = []
        for version in versions {
            var copy = EntryFile.decode(
                version.data,
                defaults: EntryFileDefaults(id: UUID(), journalID: entry.journalID, date: entry.createdAt)
            )
            if copy.body == entry.body && copy.photos == entry.photos && copy.location == entry.location {
                continue
            }
            copy.id = UUID()
            if let modified = version.modified { copy.modifiedAt = modified }
            for photo in copy.photos {
                if let data = try? readPhoto(entryID: entry.id, fileName: photo.fileName) {
                    try? writePhoto(data, fileName: photo.fileName, entryID: copy.id)
                }
            }
            if (try? save(copy)) != nil { copies.append(copy) }
        }
        files.clearConflicts(at: url)
        return copies
    }

    // MARK: Photos

    func photoURL(entryID: UUID, photo: PhotoRef) -> URL {
        layout.photoURL(entryID: entryID, fileName: photo.fileName)
    }

    func writePhoto(_ data: Data, fileName: String, entryID: UUID) throws {
        try files.write(data, to: layout.photoURL(entryID: entryID, fileName: fileName))
    }

    func readPhoto(entryID: UUID, fileName: String) throws -> Data {
        try files.read(layout.photoURL(entryID: entryID, fileName: fileName))
    }

    /// Removed photos move to a "Removed" folder inside the entry instead of being deleted.
    func removePhoto(_ photo: PhotoRef, entryID: UUID) throws {
        let source = layout.photoURL(entryID: entryID, fileName: photo.fileName)
        guard files.exists(source) else { return }
        let destination = layout.photosDir(entryID)
            .appendingPathComponent("Removed", isDirectory: true)
            .appendingPathComponent(photo.fileName, isDirectory: false)
        if files.exists(destination) { try files.remove(destination) }
        try files.move(from: source, to: destination)
    }

    // MARK: Recently Deleted

    private struct TrashMarker: Codable {
        var deletedAt: Date
    }

    func moveToTrash(entryID: UUID, now: Date = Date()) throws {
        let target = layout.trashEntryDir(entryID)
        if files.exists(target) { try files.remove(target) }
        try files.move(from: layout.entryDir(entryID), to: target)
        let marker = try JSONCoding.encoder().encode(TrashMarker(deletedAt: now))
        try files.write(marker, to: layout.trashMarker(entryID))
    }

    func trashedEntries() -> [TrashedEntry] {
        let items = (try? files.list(layout.trashDir)) ?? []
        var result: [TrashedEntry] = []
        for item in items where item.isDirectory {
            guard let id = UUID(uuidString: item.name),
                  let data = try? files.read(item.url.appendingPathComponent(EntryFile.fileName)) else { continue }
            var entry = EntryFile.decode(
                data, defaults: EntryFileDefaults(id: id, journalID: Journal.defaultID, date: Date())
            )
            entry.id = id
            let deletedAt = (try? files.read(layout.trashMarker(id)))
                .flatMap { try? JSONCoding.decoder().decode(TrashMarker.self, from: $0) }?.deletedAt
                ?? entry.modifiedAt
            result.append(TrashedEntry(entry: entry, deletedAt: deletedAt))
        }
        return result.sorted { $0.deletedAt > $1.deletedAt }
    }

    func restore(entryID: UUID) throws {
        let destination = layout.entryDir(entryID)
        if files.exists(destination) { throw LibraryError.alreadyExists }
        try files.move(from: layout.trashEntryDir(entryID), to: destination)
        try? files.remove(destination.appendingPathComponent("deleted.json", isDirectory: false))
    }

    func deleteForever(entryID: UUID) throws {
        try files.remove(layout.trashEntryDir(entryID))
    }

    // MARK: Copying between libraries

    struct CopyReport: Equatable {
        var copied = 0
        var skipped = 0
        var failed = 0
    }

    /// Copies journals, templates, entries and photos into another library. Nothing in the destination is
    /// overwritten and nothing in this library is touched, so moving to a new folder can't lose anything.
    func copyContents(to destination: Library) -> CopyReport {
        var report = CopyReport()
        let pairs = [
            (layout.journalsDir, destination.layout.journalsDir),
            (layout.templatesDir, destination.layout.templatesDir),
            (layout.entriesDir, destination.layout.entriesDir),
        ]
        for (source, target) in pairs {
            copyTree(from: source, to: target, into: destination.files, report: &report)
        }
        if !destination.files.exists(destination.layout.settingsFile),
           let data = try? files.read(layout.settingsFile) {
            if (try? destination.files.write(data, to: destination.layout.settingsFile)) != nil {
                report.copied += 1
            } else {
                report.failed += 1
            }
        }
        return report
    }

    private func copyTree(from source: URL, to target: URL, into destination: FileAccess, report: inout CopyReport) {
        guard let items = try? files.list(source) else { return }
        for item in items {
            let targetURL = target.appendingPathComponent(item.name, isDirectory: item.isDirectory)
            if item.isDirectory {
                try? destination.createDirectory(targetURL)
                copyTree(from: item.url, to: targetURL, into: destination, report: &report)
            } else if destination.exists(targetURL) {
                report.skipped += 1
            } else if let data = try? files.read(item.url), (try? destination.write(data, to: targetURL)) != nil {
                report.copied += 1
            } else {
                report.failed += 1
            }
        }
    }

    /// Permanently removes entries that have been in Recently Deleted longer than `days`.
    @discardableResult
    func purgeTrash(olderThanDays days: Int = 30, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var removed = 0
        for trashed in trashedEntries() where trashed.deletedAt < cutoff {
            if (try? deleteForever(entryID: trashed.id)) != nil { removed += 1 }
        }
        return removed
    }
}

// Library keeps no mutable state; all work goes through the FileAccess it was given.
extension Library: @unchecked Sendable {}
