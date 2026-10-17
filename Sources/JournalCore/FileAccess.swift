import Foundation

struct DirectoryItem: Equatable {
    /// Real file name. iCloud placeholders (".note.md.icloud") are shown under the name they stand for.
    var name: String
    var url: URL
    var isDirectory: Bool
    /// True when iCloud has the item but hasn't downloaded it to this device yet.
    var isPlaceholder: Bool
}

struct ConflictVersion {
    var data: Data
    var modified: Date?
}

/// Everything the journal needs from the file system.
///
/// The app uses a version that goes through NSFileCoordinator, which is what iCloud Drive wants.
/// Tests use `PlainFileAccess`.
protocol FileAccess {
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func createDirectory(_ url: URL) throws
    func list(_ url: URL) throws -> [DirectoryItem]
    func exists(_ url: URL) -> Bool
    func move(from: URL, to: URL) throws
    func remove(_ url: URL) throws
    /// Other versions of a file that two devices changed at once. Empty when there is no conflict.
    func conflictVersions(at url: URL) -> [ConflictVersion]
    func clearConflicts(at url: URL)
}

extension FileAccess {
    func conflictVersions(at url: URL) -> [ConflictVersion] { [] }
    func clearConflicts(at url: URL) {}
}

enum ICloudPlaceholder {
    /// ".note.md.icloud" -> "note.md". Returns nil for any other name.
    static func realName(forPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}

struct PlainFileAccess: FileAccess {
    func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func list(_ url: URL) throws -> [DirectoryItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )
        var items: [DirectoryItem] = []
        for itemURL in urls {
            let rawName = itemURL.lastPathComponent
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if let real = ICloudPlaceholder.realName(forPlaceholder: rawName) {
                items.append(DirectoryItem(
                    name: real,
                    url: url.appendingPathComponent(real, isDirectory: false),
                    isDirectory: false,
                    isPlaceholder: true
                ))
            } else if !rawName.hasPrefix(".") {
                items.append(DirectoryItem(name: rawName, url: itemURL, isDirectory: isDirectory, isPlaceholder: false))
            }
        }
        return items
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func move(from: URL, to: URL) throws {
        try FileManager.default.createDirectory(
            at: to.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: from, to: to)
    }

    func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
