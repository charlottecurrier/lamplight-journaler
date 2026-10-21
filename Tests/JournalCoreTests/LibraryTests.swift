import XCTest
#if canImport(JournalCore)
@testable import JournalCore
#else
@testable import Lamplight
#endif

/// Wraps the real file system and pretends another device left conflicting versions behind.
private struct ConflictingFileAccess: FileAccess {
    let base = PlainFileAccess()
    var conflicts: [URL: [ConflictVersion]]
    var cleared: Box = Box()

    final class Box { var urls: [URL] = [] }

    func read(_ url: URL) throws -> Data { try base.read(url) }
    func write(_ data: Data, to url: URL) throws { try base.write(data, to: url) }
    func createDirectory(_ url: URL) throws { try base.createDirectory(url) }
    func list(_ url: URL) throws -> [DirectoryItem] { try base.list(url) }
    func exists(_ url: URL) -> Bool { base.exists(url) }
    func move(from: URL, to: URL) throws { try base.move(from: from, to: to) }
    func remove(_ url: URL) throws { try base.remove(url) }
    func conflictVersions(at url: URL) -> [ConflictVersion] { conflicts[url] ?? [] }
    func clearConflicts(at url: URL) { cleared.urls.append(url) }
}

final class LibraryTests: XCTestCase {
    var dir: URL!
    var library: Library!

    override func setUpWithError() throws {
        dir = try T.tempDirectory()
        library = Library(root: dir.appendingPathComponent("Lamplight", isDirectory: true))
        try library.prepare()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Setup

    func testPrepareCreatesFoldersAndTheFirstJournalOnce() throws {
        let fm = FileManager.default
        for name in ["Journals", "Templates", "Entries", "Recently Deleted"] {
            XCTAssertTrue(fm.fileExists(atPath: library.layout.root.appendingPathComponent(name).path), name)
        }
        XCTAssertEqual(library.loadJournals().map(\.id), [Journal.defaultID])
        try library.prepare()
        XCTAssertEqual(library.loadJournals().count, 1)
    }

    func testLocatorMakesAFolderInsideAPlainPick() throws {
        let picked = dir.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let root = LibraryLocator.resolveRoot(picked: picked, files: PlainFileAccess())
        XCTAssertEqual(root.lastPathComponent, "Lamplight")
        XCTAssertEqual(root.deletingLastPathComponent().lastPathComponent, "Documents")
    }

    func testLocatorFindsAnExistingLibraryInsideThePick() {
        let root = LibraryLocator.resolveRoot(picked: dir, files: PlainFileAccess())
        XCTAssertEqual(root.standardizedFileURL.path, library.layout.root.standardizedFileURL.path)
    }

    func testLocatorUsesAPickThatIsAlreadyALibrary() {
        let root = LibraryLocator.resolveRoot(picked: library.layout.root, files: PlainFileAccess())
        XCTAssertEqual(root.standardizedFileURL.path, library.layout.root.standardizedFileURL.path)
    }

    func testPlaceholderNames() {
        XCTAssertEqual(ICloudPlaceholder.realName(forPlaceholder: ".entry.md.icloud"), "entry.md")
        XCTAssertNil(ICloudPlaceholder.realName(forPlaceholder: "entry.md"))
        XCTAssertNil(ICloudPlaceholder.realName(forPlaceholder: ".DS_Store"))
        XCTAssertNil(ICloudPlaceholder.realName(forPlaceholder: ".icloud"))
    }

    func testListingShowsPlaceholdersUnderTheirRealName() throws {
        let folder = library.layout.root.appendingPathComponent("Probe", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent(".photo.jpg.icloud"))
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        try Data("x".utf8).write(to: folder.appendingPathComponent("note.md"))
        let items = try PlainFileAccess().list(folder).sorted { $0.name < $1.name }
        XCTAssertEqual(items.map(\.name), ["note.md", "photo.jpg"])
        XCTAssertEqual(items.map(\.isPlaceholder), [false, true])
    }

    // MARK: Entries

    func testSaveAndLoadAnEntry() throws {
        let entry = T.entry("2026-10-17T21:14:03Z", body: "Saved on disk.")
        try library.save(entry)
        XCTAssertEqual(try library.entryIDs(), [entry.id])
        XCTAssertEqual(try library.loadEntry(id: entry.id), entry)
        let path = library.layout.entryFile(entry.id).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testLoadAllEntriesSkipsFoldersThatAreNotEntries() throws {
        try library.save(T.entry("2026-10-17T21:14:03Z"))
        try library.save(T.entry("2026-10-16T21:14:03Z"))
        try FileManager.default.createDirectory(
            at: library.layout.entriesDir.appendingPathComponent("not-an-id"), withIntermediateDirectories: true
        )
        let result = library.loadAllEntries()
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertTrue(result.failedIDs.isEmpty)
    }

    func testFolderIDWinsOverTheIDInsideTheFile() throws {
        let entry = T.entry("2026-10-17T21:14:03Z")
        try library.save(entry)
        // Someone copied the folder in Files and renamed it.
        let copyID = UUID()
        try FileManager.default.copyItem(
            at: library.layout.entryDir(entry.id), to: library.layout.entryDir(copyID)
        )
        XCTAssertEqual(try library.loadEntry(id: copyID).id, copyID)
    }

    func testEditingOverwritesInPlace() throws {
        var entry = T.entry("2026-10-17T21:14:03Z", body: "first")
        try library.save(entry)
        entry.body = "second"
        try library.save(entry)
        XCTAssertEqual(try library.loadEntry(id: entry.id).body, "second")
        XCTAssertEqual(try library.entryIDs().count, 1)
    }

    // MARK: Photos

    func testPhotoWriteReadAndRemoveKeepsTheFile() throws {
        let entry = T.entry("2026-10-17T21:14:03Z")
        try library.save(entry)
        let photo = PhotoRef(fileName: "p.jpg", width: 10, height: 10)
        try library.writePhoto(Data([1, 2, 3]), fileName: photo.fileName, entryID: entry.id)
        XCTAssertEqual(try library.readPhoto(entryID: entry.id, fileName: "p.jpg"), Data([1, 2, 3]))

        try library.removePhoto(photo, entryID: entry.id)
        XCTAssertThrowsError(try library.readPhoto(entryID: entry.id, fileName: "p.jpg"))
        let kept = library.layout.photosDir(entry.id).appendingPathComponent("Removed/p.jpg")
        XCTAssertEqual(try Data(contentsOf: kept), Data([1, 2, 3]))
    }

    // MARK: Recently Deleted

    func testDeleteRestoreAndPurge() throws {
        var entry = T.entry("2026-10-17T21:14:03Z", body: "keep me")
        entry.photos = [PhotoRef(fileName: "p.jpg", width: 1, height: 1)]
        try library.save(entry)
        try library.writePhoto(Data([9]), fileName: "p.jpg", entryID: entry.id)

        let deletedAt = T.date("2026-10-18T10:00:00Z")
        try library.moveToTrash(entryID: entry.id, now: deletedAt)
        XCTAssertTrue(library.loadAllEntries().entries.isEmpty)
        let trashed = library.trashedEntries()
        XCTAssertEqual(trashed.map(\.id), [entry.id])
        XCTAssertEqual(trashed[0].deletedAt, deletedAt)
        XCTAssertEqual(trashed[0].entry.body, "keep me")

        // Not old enough yet.
        XCTAssertEqual(library.purgeTrash(olderThanDays: 30, now: T.date("2026-11-01T00:00:00Z")), 0)

        try library.restore(entryID: entry.id)
        XCTAssertEqual(try library.loadEntry(id: entry.id).body, "keep me")
        XCTAssertEqual(try library.readPhoto(entryID: entry.id, fileName: "p.jpg"), Data([9]))
        XCTAssertTrue(library.trashedEntries().isEmpty)

        try library.moveToTrash(entryID: entry.id, now: deletedAt)
        XCTAssertEqual(library.purgeTrash(olderThanDays: 30, now: T.date("2026-12-01T00:00:00Z")), 1)
        XCTAssertTrue(library.trashedEntries().isEmpty)
    }

    func testRestoreRefusesToOverwriteALiveEntry() throws {
        let entry = T.entry("2026-10-17T21:14:03Z")
        try library.save(entry)
        try library.moveToTrash(entryID: entry.id)
        try library.save(entry)
        XCTAssertThrowsError(try library.restore(entryID: entry.id))
    }

    // MARK: Journals, templates, settings

    func testJournalsAndTemplatesRoundTripAndSort() throws {
        let second = Journal(id: UUID(), name: "Dreams", colorKey: "sage", sortOrder: 2, createdAt: T.date("2026-10-01T00:00:00Z"))
        try library.save(second)
        XCTAssertEqual(library.loadJournals().map(\.name), ["Journal", "Dreams"])

        let t1 = EntryTemplate(name: "Evening", body: "## What went well?\n\n## What was hard?\n\n", sortOrder: 1, createdAt: T.date("2026-10-01T00:00:00Z"))
        let t0 = EntryTemplate(name: "Gratitude", body: "## Three things\n\n", sortOrder: 0, createdAt: T.date("2026-10-02T00:00:00Z"))
        try library.save(t1)
        try library.save(t0)
        XCTAssertEqual(library.loadTemplates(), [t0, t1])

        try library.deleteTemplate(id: t0.id)
        XCTAssertEqual(library.loadTemplates(), [t1])
    }

    func testSettingsRoundTrip() throws {
        XCTAssertNil(library.loadSettings().home)
        let settings = LibrarySettings(home: EntryLocation(name: "Home", latitude: 1.5, longitude: -2.5, isHome: true))
        try library.save(settings)
        XCTAssertEqual(library.loadSettings(), settings)
    }

    // MARK: Conflicts

    func testConflictingVersionIsKeptAsACopy() throws {
        var entry = T.entry("2026-10-17T21:14:03Z", body: "version on this iPad")
        entry.photos = [PhotoRef(fileName: "p.jpg", width: 1, height: 1)]
        try library.save(entry)
        try library.writePhoto(Data([7]), fileName: "p.jpg", entryID: entry.id)

        var other = entry
        other.body = "version from the iPhone"
        let identical = entry
        let access = ConflictingFileAccess(conflicts: [
            library.layout.entryFile(entry.id): [
                ConflictVersion(data: EntryFile.encode(other), modified: T.date("2026-10-17T22:00:00Z")),
                ConflictVersion(data: EntryFile.encode(identical), modified: nil),
            ],
        ])
        let withConflicts = Library(root: library.layout.root, files: access)

        let copies = withConflicts.resolveConflicts(for: entry)
        XCTAssertEqual(copies.count, 1, "an identical version is not worth a copy")
        XCTAssertNotEqual(copies[0].id, entry.id)
        XCTAssertEqual(copies[0].body, "version from the iPhone")
        XCTAssertEqual(copies[0].modifiedAt, T.date("2026-10-17T22:00:00Z"))
        XCTAssertEqual(try library.loadEntry(id: copies[0].id).body, "version from the iPhone")
        XCTAssertEqual(try library.readPhoto(entryID: copies[0].id, fileName: "p.jpg"), Data([7]))
        XCTAssertEqual(try library.loadEntry(id: entry.id).body, "version on this iPad")
        XCTAssertEqual(access.cleared.urls, [library.layout.entryFile(entry.id)])
    }

    // MARK: Copying

    func testCopyContentsBringsEverythingAndNeverOverwrites() throws {
        var entry = T.entry("2026-10-17T21:14:03Z", body: "from the old folder")
        entry.photos = [PhotoRef(fileName: "p.jpg", width: 1, height: 1)]
        try library.save(entry)
        try library.writePhoto(Data([4, 2]), fileName: "p.jpg", entryID: entry.id)
        let template = EntryTemplate(name: "Evening", body: "## Q1\n\n", createdAt: T.date("2026-10-01T00:00:00Z"))
        try library.save(template)
        try library.save(LibrarySettings(home: EntryLocation(name: "Home", isHome: true)))

        let other = Library(root: dir.appendingPathComponent("New", isDirectory: true))
        try other.prepare()
        let sameID = T.entry("2026-10-01T10:00:00Z", body: "already in the new folder")
        try other.save(sameID)
        var clash = sameID
        clash.body = "old folder's different version"
        try library.save(clash)

        let report = library.copyContents(to: other)
        XCTAssertEqual(report.failed, 0)
        XCTAssertGreaterThan(report.copied, 0)
        XCTAssertGreaterThan(report.skipped, 0)

        XCTAssertEqual(try other.loadEntry(id: entry.id).body, "from the old folder")
        XCTAssertEqual(try other.readPhoto(entryID: entry.id, fileName: "p.jpg"), Data([4, 2]))
        XCTAssertEqual(try other.loadEntry(id: sameID.id).body, "already in the new folder")
        XCTAssertEqual(other.loadTemplates(), [template])
        XCTAssertEqual(other.loadSettings().home?.name, "Home")
        XCTAssertEqual(other.loadJournals().count, 1)
        // The source is untouched.
        XCTAssertEqual(try library.loadEntry(id: entry.id).body, "from the old folder")
    }

    func testNoConflictsMeansNoWork() {
        let entry = T.entry("2026-10-17T21:14:03Z")
        XCTAssertTrue(library.resolveConflicts(for: entry).isEmpty)
    }
}
