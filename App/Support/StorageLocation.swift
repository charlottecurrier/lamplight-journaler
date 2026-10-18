import Foundation

enum StorageMode: String {
    /// A folder the person picked in the Files app, usually inside iCloud Drive.
    case folder
    /// The app's own Documents folder on this device.
    case local
}

enum StorageError: LocalizedError {
    case folderMissing

    var errorDescription: String? {
        switch self {
        case .folderMissing:
            return "Lamplight can't find the folder your journal is in. It may have been moved or deleted."
        }
    }
}

/// Remembers where the journal lives and keeps access to it.
///
/// A folder picked in the Files app is only reachable through a "security-scoped bookmark".
/// The bookmark is saved in UserDefaults and turned back into a URL on each launch.
@MainActor
final class StorageLocation {
    private let defaults = UserDefaults.standard
    private let modeKey = "storage.mode"
    private let bookmarkKey = "storage.bookmark"
    private let nameKey = "storage.name"

    /// Folders we have started accessing. Older ones are released once a switch has finished.
    private var accessed: [URL] = []

    var mode: StorageMode? {
        defaults.string(forKey: modeKey).flatMap(StorageMode.init(rawValue:))
    }

    /// A short name for Settings.
    var displayName: String {
        switch mode {
        case .folder: return defaults.string(forKey: nameKey) ?? "Chosen folder"
        case .local: return "On this device"
        case nil: return "Not set"
        }
    }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func chooseLocal() {
        defaults.set(StorageMode.local.rawValue, forKey: modeKey)
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
    }

    func chooseFolder(_ url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        accessed.append(url)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: nameKey)
        defaults.set(StorageMode.folder.rawValue, forKey: modeKey)
    }

    /// Turns the saved choice back into a folder URL and starts accessing it.
    /// For a folder, this is the folder the person picked. The library may be a "Lamplight" folder inside it.
    func openSaved() throws -> URL {
        switch mode {
        case .local:
            return documentsURL
        case .folder:
            guard let data = defaults.data(forKey: bookmarkKey) else { throw StorageError.folderMissing }
            var stale = false
            let url: URL
            do {
                url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            } catch {
                throw StorageError.folderMissing
            }
            _ = url.startAccessingSecurityScopedResource()
            accessed.append(url)
            if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
            return url
        case nil:
            throw StorageError.folderMissing
        }
    }

    var localParent: URL { documentsURL }

    /// Stops accessing every folder except the one in use now.
    func releaseOlderAccess() {
        guard let current = accessed.last else { return }
        for url in accessed.dropLast() where url != current {
            url.stopAccessingSecurityScopedResource()
        }
        accessed = [current]
    }
}
