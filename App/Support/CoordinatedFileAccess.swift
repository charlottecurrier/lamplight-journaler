import Foundation

/// File access that goes through NSFileCoordinator, which is how apps share files safely with iCloud Drive.
/// It makes sure a file isn't read while it is being synced, and asks iCloud to download files
/// that are only stored online.
struct CoordinatedFileAccess: FileAccess {
    /// Reads and listings give up waiting on iCloud after these many seconds, so opening the journal never sits on
    /// one file that won't come down. The entry is tried again later. Writes are never given up on: a half-finished
    /// save is worse than a slow one.
    var textTimeout: TimeInterval = 12
    var listTimeout: TimeInterval = 15
    var photoTimeout: TimeInterval = 60
    /// Shared by every copy of this value. After a few waits in a row run out, reads stop being started for a while.
    private let wait = BoundedWait()

    private func coordinator() -> NSFileCoordinator {
        NSFileCoordinator(filePresenter: nil)
    }

    private func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    /// If iCloud only has a stub of this file, ask for it.
    ///
    /// Text files (entries, journals, templates) fail right away and are picked up by the next refresh,
    /// so opening the journal never waits on a slow or missing connection. A photo is worth a short wait,
    /// because someone is looking at it.
    private func prepareForRead(_ url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: placeholderURL(for: url).path) else { return }
        try? manager.startDownloadingUbiquitousItem(at: url)
        guard url.pathExtension.lowercased() == "jpg" else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        for _ in 0..<16 {
            if manager.fileExists(atPath: url.path) { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    func read(_ url: URL) throws -> Data {
        try prepareForRead(url)
        let coordinator = coordinator()
        let timeout = url.pathExtension.lowercased() == "jpg" ? photoTimeout : textTimeout
        return try wait.run(timeout: timeout, cancel: { coordinator.cancel() }) {
            var outcome: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
            var coordinationError: NSError?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                outcome = Result { try Data(contentsOf: readURL) }
            }
            if let coordinationError { throw coordinationError }
            return try outcome.get()
        }
    }

    func write(_ data: Data, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        var outcome: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        coordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            outcome = Result { try data.write(to: writeURL, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }

    func createDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        var outcome: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        coordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { directoryURL in
            outcome = Result {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }

    func list(_ url: URL) throws -> [DirectoryItem] {
        let coordinator = coordinator()
        return try wait.run(timeout: listTimeout, cancel: { coordinator.cancel() }) {
            var outcome: Result<[DirectoryItem], Error> = .success([])
            var coordinationError: NSError?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                outcome = Result { try PlainFileAccess().list(readURL) }
            }
            if let coordinationError { throw coordinationError }
            return try outcome.get()
        }
    }

    func exists(_ url: URL) -> Bool {
        let manager = FileManager.default
        return manager.fileExists(atPath: url.path) || manager.fileExists(atPath: placeholderURL(for: url).path)
    }

    func move(from: URL, to: URL) throws {
        try createDirectory(to.deletingLastPathComponent())
        var outcome: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        coordinator().coordinate(
            writingItemAt: from, options: .forMoving,
            writingItemAt: to, options: .forReplacing,
            error: &coordinationError
        ) { source, destination in
            outcome = Result { try FileManager.default.moveItem(at: source, to: destination) }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }

    func remove(_ url: URL) throws {
        var outcome: Result<Void, Error> = .success(())
        var coordinationError: NSError?
        coordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { removeURL in
            outcome = Result { try FileManager.default.removeItem(at: removeURL) }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }

    // MARK: Conflicts

    func conflictVersions(at url: URL) -> [ConflictVersion] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            return []
        }
        return versions.compactMap { version in
            guard let data = try? Data(contentsOf: version.url) else { return nil }
            return ConflictVersion(data: data, modified: version.modificationDate)
        }
    }

    /// Marks the conflicts that were read (and saved as copies) as resolved. A version that couldn't be read
    /// yet is left alone, so it is tried again later instead of being thrown away.
    func clearConflicts(at url: URL) {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) else { return }
        var everyVersionRead = true
        for version in versions {
            if (try? Data(contentsOf: version.url)) != nil {
                version.isResolved = true
            } else {
                everyVersionRead = false
            }
        }
        if everyVersionRead {
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
    }
}
