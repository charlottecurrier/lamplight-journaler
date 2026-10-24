import SwiftUI
import Observation
import UIKit

/// An entry from this date in an earlier year, shown for a moment after you save.
struct LookBack: Equatable {
    var entryID: UUID
    /// "1 year ago"
    var label: String
    var title: String
    var preview: String
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var lookBack: LookBack?
}

enum EntryScope: Hashable {
    case all
    case journal(UUID)
}

private struct LoadedEntry: Sendable {
    var entry: Entry?
    var copies: [Entry]
}

private struct LoadSnapshot: Sendable {
    var journals: [Journal]
    var templates: [EntryTemplate]
    var settings: LibrarySettings
    var entries: [Entry]
    var failedCount: Int
    var conflictCopies: Int
}

/// Everything the screens read and change. Entries live in memory for fast lists and are written to the
/// journal folder one file at a time, on a background queue, so typing never waits on iCloud.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case needsStorage
        case loading
        case ready
        case problem(String)
    }

    // MARK: State the screens watch

    var phase: Phase = .needsStorage
    var entries: [Entry] = []
    var journals: [Journal] = []
    var templates: [EntryTemplate] = []
    var settings = LibrarySettings()
    var editingEntryID: UUID?
    var toast: Toast?
    var loadedCount = 0
    var totalCount = 0
    /// Entries that exist in the folder but haven't finished downloading from iCloud yet.
    var stillDownloading = 0
    var saveProblem = false
    /// How often each template has been used on this device. Used to list the favorites first.
    var templateUseCounts: [UUID: Int] = AppModel.loadUseCounts()
    /// Entries just made, not yet written in. The editor uses this to put the caret under a template's first heading.
    private(set) var freshEntryIDs: Set<UUID> = []
    /// The text a new entry started with (a template's page). An entry that still holds only that is not worth a file.
    @ObservationIgnored private var startingBodies: [UUID: String] = [:]
    /// Set once the app has opened to a new entry for this launch, so reopening the journal doesn't do it again.
    @ObservationIgnored var didOpenToNewEntry = false
    /// Bumps after each refresh, so photos that failed to load can try again.
    var refreshCounter = 0
    var storageName = ""

    // MARK: Plumbing

    let storage = StorageLocation()
    private let files = CoordinatedFileAccess()
    private let thumbnails = NSCache<NSString, UIImage>()
    private(set) var library: Library?

    @ObservationIgnored private let writeQueue = DispatchQueue(label: "lamplight.writes", qos: .utility)
    @ObservationIgnored private var writesInFlight = 0
    @ObservationIgnored private var persistedIDs: Set<UUID> = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryCount = 0
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshRequested = false
    /// Counts every write. A folder read that started before a write finished is out of date and is thrown away.
    @ObservationIgnored private var writeGeneration = 0

    init() {
        thumbnails.totalCostLimit = 160 * 1024 * 1024
    }

    // MARK: Opening the journal

    func start() {
        guard storage.mode != nil else {
            phase = .needsStorage
            return
        }
        openSaved()
    }

    func openSaved() {
        do {
            let picked = try storage.openSaved()
            open(picked: picked, copyingFrom: nil)
        } catch {
            phase = .problem(error.localizedDescription)
        }
    }

    func useLocalStorage() {
        let previous = library
        storage.chooseLocal()
        open(picked: storage.localParent, copyingFrom: previous)
    }

    func useFolder(_ url: URL) {
        let previous = library
        do {
            try storage.chooseFolder(url)
        } catch {
            phase = .problem(error.localizedDescription)
            return
        }
        open(picked: url, copyingFrom: previous)
    }

    private func open(picked: URL, copyingFrom previous: Library?) {
        phase = .loading
        loadedCount = 0
        totalCount = 0
        let files = self.files
        Task {
            let root = await IO.run { LibraryLocator.resolveRoot(picked: picked, files: files) }
            let newLibrary = Library(root: root, files: files)
            if let previous, previous.layout.root.standardizedFileURL != root.standardizedFileURL {
                // Moving to a new folder: bring everything along. The old folder is left as it is.
                await IO.run {
                    try? newLibrary.prepare()
                    _ = previous.copyContents(to: newLibrary)
                }
            }
            library = newLibrary
            storageName = storage.displayName
            await load(newLibrary, initial: true)
            storage.releaseOlderAccess()
        }
    }

    private func load(_ library: Library, initial: Bool) async {
        do {
            try await IO.runThrowing { try library.prepare() }
        } catch {
            phase = .problem("Lamplight couldn't open the journal folder. \(error.localizedDescription)")
            return
        }
        let snapshot = await Self.readEverything(library) { [weak self] done, total in
            Task { @MainActor in
                self?.loadedCount = done
                self?.totalCount = total
            }
        }
        apply(snapshot)
        if initial {
            Task { await IO.run { _ = library.purgeTrash() } }
        }
    }

    private func apply(_ snapshot: LoadSnapshot) {
        journals = snapshot.journals.isEmpty ? [Journal.makeDefault()] : snapshot.journals
        templates = snapshot.templates
        settings = snapshot.settings
        persistedIDs = Set(snapshot.entries.map(\.id))

        var merged = snapshot.entries
        if let id = editingEntryID, let local = entries.first(where: { $0.id == id }) {
            merged.removeAll { $0.id == id }
            merged.append(local)
        }
        entries = merged.sorted { $0.createdAt > $1.createdAt }
        phase = .ready

        stillDownloading = snapshot.failedCount
        if snapshot.failedCount > 0 {
            scheduleRetry()
        } else {
            retryCount = 0
        }
        if snapshot.conflictCopies > 0 {
            show("Two devices edited the same entry. Both versions are kept.")
        }
    }

    /// Entries still downloading from iCloud: look again in a few seconds.
    private func scheduleRetry() {
        guard retryCount < 20 else { return }
        retryCount += 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Reads the journal folder again. Runs when the app comes forward and on pull-to-refresh.
    func refresh() async {
        guard phase == .ready else { return }
        if isRefreshing {
            // Someone asked while a read was running. Read once more when it finishes.
            refreshRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        var attempts = 0
        repeat {
            refreshRequested = false
            guard let library else { return }
            attempts += 1

            var waited = 0
            while writesInFlight > 0 && waited < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            let generation = writeGeneration
            let snapshot = await Self.readEverything(library) { _, _ in }

            // Something was saved while the folder was being read, so this picture is already old.
            // Read again rather than put back an entry that was just deleted or an old version of one that was edited.
            if generation != writeGeneration || writesInFlight > 0 {
                refreshRequested = true
                continue
            }
            apply(snapshot)
            refreshCounter += 1
        } while refreshRequested && attempts < 3
    }

    nonisolated private static func readEverything(
        _ library: Library,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> LoadSnapshot {
        let (journals, templates, settings, ids) = await IO.run {
            (library.loadJournals(), library.loadTemplates(), library.loadSettings(), (try? library.entryIDs()) ?? [])
        }

        var entries: [Entry] = []
        var failed = 0
        var copies = 0
        var done = 0
        var cursor = 0

        await withTaskGroup(of: LoadedEntry.self) { group in
            while cursor < min(8, ids.count) {
                let id = ids[cursor]
                cursor += 1
                group.addTask { await IO.run { Self.loadOne(library, id: id) } }
            }
            while let item = await group.next() {
                done += 1
                if let entry = item.entry { entries.append(entry) } else { failed += 1 }
                entries.append(contentsOf: item.copies)
                copies += item.copies.count
                if done % 8 == 0 || done == ids.count { progress(done, ids.count) }
                if cursor < ids.count {
                    let id = ids[cursor]
                    cursor += 1
                    group.addTask { await IO.run { Self.loadOne(library, id: id) } }
                }
            }
        }
        return LoadSnapshot(
            journals: journals, templates: templates, settings: settings,
            entries: entries, failedCount: failed, conflictCopies: copies
        )
    }

    nonisolated private static func loadOne(_ library: Library, id: UUID) -> LoadedEntry {
        guard let entry = try? library.loadEntry(id: id) else { return LoadedEntry(entry: nil, copies: []) }
        return LoadedEntry(entry: entry, copies: library.resolveConflicts(for: entry))
    }

    // MARK: Reading

    func entry(_ id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    func journal(_ id: UUID) -> Journal? {
        journals.first { $0.id == id }
    }

    func journalName(_ id: UUID) -> String {
        journal(id)?.name ?? "Journal"
    }

    func template(_ id: UUID) -> EntryTemplate? {
        templates.first { $0.id == id }
    }

    /// Entries for a list. A new entry you haven't typed in yet is shown only while you're editing it.
    func entries(in scope: EntryScope, matching query: String = "") -> [Entry] {
        entries.filter { entry in
            guard !isUnwritten(entry) || entry.id == editingEntryID else { return false }
            if case .journal(let id) = scope, entry.journalID != id { return false }
            return entry.matches(query: query)
        }
    }

    private var writtenEntries: [Entry] {
        entries.filter { !isUnwritten($0) }
    }

    /// Nothing the person wrote: no photos, and no text beyond what the entry started with.
    func isUnwritten(_ entry: Entry) -> Bool {
        if entry.isBlank { return true }
        guard let start = startingBodies[entry.id], entry.photos.isEmpty else { return false }
        return entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
            == start.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func today(_ calendar: DayCalendar) -> DayStamp {
        calendar.stamp(for: Date(), timeZone: .current)
    }

    func streak(calendar: DayCalendar) -> StreakSummary {
        Streaks.summary(entries: writtenEntries, today: today(calendar), calendar: calendar)
    }

    func onThisDay(calendar: DayCalendar) -> [OnThisDayGroup] {
        OnThisDay.groups(entries: writtenEntries, today: today(calendar), calendar: calendar)
    }

    func entryCount(in journalID: UUID) -> Int {
        writtenEntries.filter { $0.journalID == journalID }.count
    }

    func defaultJournalID(for scope: EntryScope) -> UUID {
        if case .journal(let id) = scope, journal(id) != nil { return id }
        return journals.first?.id ?? Journal.defaultID
    }

    // MARK: Writing entries

    @discardableResult
    func beginNewEntry(
        journalID: UUID,
        templateID: UUID? = nil,
        body: String = "",
        location: EntryLocation? = nil
    ) -> UUID {
        // Forget any earlier new entry that was never typed in. The one being edited is left for its editor to
        // finish, since its latest typing may not have reached the model yet.
        let stale = entries
            .filter { isUnwritten($0) && !persistedIDs.contains($0.id) && $0.id != editingEntryID }
            .map(\.id)
        entries.removeAll { stale.contains($0.id) }
        for id in stale {
            startingBodies[id] = nil
            freshEntryIDs.remove(id)
        }
        let entry = Entry(journalID: journalID, templateID: templateID, location: location, body: body)
        entries.insert(entry, at: 0)
        editingEntryID = entry.id
        freshEntryIDs.insert(entry.id)
        // Nothing is saved until the person writes something. A template's page alone is not an entry.
        if !body.isEmpty { startingBodies[entry.id] = EditorText.toMarkdown(EditorText.fromMarkdown(body)) }
        return entry.id
    }

    /// A template was added to an entry that had nothing in it. Until the person writes more, it isn't worth a file.
    func noteTemplateApplied(to id: UUID, body: String) {
        guard let current = entry(id), current.isBlank else { return }
        startingBodies[id] = body
    }

    func update(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let dateChanged = entries[index].createdAt != entry.createdAt
        entries[index] = entry
        if dateChanged { entries.sort { $0.createdAt > $1.createdAt } }
        persist(entry)
    }

    /// Ends an editing session. An entry with nothing in it is dropped instead of saved.
    func finishEditing(_ id: UUID, announce: Bool, calendar: DayCalendar) {
        let wasEditing = editingEntryID == id
        let wasNew = freshEntryIDs.contains(id)
        if wasEditing {
            editingEntryID = nil
            freshEntryIDs.remove(id)
        }
        guard let entry = entry(id) else { return }
        if isUnwritten(entry) {
            startingBodies[id] = nil
            entries.removeAll { $0.id == id }
            if persistedIDs.remove(id) != nil, let library {
                enqueueWrite { try library.moveToTrash(entryID: id) }
            }
            return
        }
        guard wasEditing else { return }
        startingBodies[id] = nil
        persist(entry)
        if announce { announceSaved(entry, isNew: wasNew, calendar: calendar) }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func announceSaved(_ entry: Entry, isNew: Bool, calendar: DayCalendar) {
        let stamp = entry.dayStamp(using: calendar)
        let isFirstOfTheDay = writtenEntries.filter { $0.dayStamp(using: calendar) == stamp }.count == 1
        if isFirstOfTheDay && stamp == today(calendar) {
            // Editing the day's only entry again shows the message, but not the look back a second time.
            show(streak(calendar: calendar).savedMessage, lookBack: isNew ? lookBack(calendar: calendar) : nil)
        } else {
            show("Saved.")
        }
    }

    /// What you wrote on this date in the most recent earlier year, if anything.
    private func lookBack(calendar: DayCalendar) -> LookBack? {
        guard let group = onThisDay(calendar: calendar).first, let entry = group.entries.first else { return nil }
        let summary = entry.summary(maxPreview: 120)
        var title = summary.title
        if title.isEmpty && summary.preview.isEmpty {
            guard !entry.photos.isEmpty else { return nil }
            title = entry.photos.count == 1 ? "Photo" : "\(entry.photos.count) photos"
        }
        return LookBack(entryID: entry.id, label: group.label, title: title, preview: summary.preview)
    }

    private func persist(_ entry: Entry) {
        guard let library else { return }
        if isUnwritten(entry) && !persistedIDs.contains(entry.id) { return }
        persistedIDs.insert(entry.id)
        enqueueWrite { try library.save(entry) }
    }

    func moveToTrash(_ id: UUID) {
        guard let library else { return }
        entries.removeAll { $0.id == id }
        if editingEntryID == id { editingEntryID = nil }
        startingBodies[id] = nil
        freshEntryIDs.remove(id)
        // A page that was never saved has no file to move.
        guard persistedIDs.remove(id) != nil else { return }
        enqueueWrite { try library.moveToTrash(entryID: id) }
        show("Moved to Recently Deleted.")
    }

    /// Keeps an entry close, or lets it go. Shown with a ribbon bookmark.
    func toggleFavorite(_ id: UUID) {
        guard var entry = entry(id) else { return }
        entry.isFavorite.toggle()
        entry.modifiedAt = Date()
        update(entry)
    }

    /// Favorite entries, newest first.
    var favorites: [Entry] {
        writtenEntries.filter(\.isFavorite)
    }

    func move(_ id: UUID, toJournal journalID: UUID) {
        guard var entry = entry(id) else { return }
        entry.journalID = journalID
        entry.modifiedAt = Date()
        update(entry)
    }

    /// Writes happen one at a time, in order, off the main thread.
    private func enqueueWrite(_ work: @escaping @Sendable () throws -> Void) {
        writesInFlight += 1
        writeGeneration += 1
        writeQueue.async { [weak self] in
            var failed = false
            do { try work() } catch { failed = true }
            Task { @MainActor in
                guard let self else { return }
                self.writesInFlight -= 1
                self.saveProblem = failed
                if failed { self.show("Couldn't save to your journal folder. Your words are still here.") }
            }
        }
    }

    // MARK: Photos

    func addPhotos(_ images: [Data], to entryID: UUID) async -> [PhotoRef] {
        guard let library else { return [] }
        var added: [PhotoRef] = []
        for data in images {
            let ref = await IO.run { () -> PhotoRef? in
                guard let prepared = ImageTools.prepareForStorage(data) else { return nil }
                let id = UUID()
                let fileName = "\(id.uuidString).jpg"
                do {
                    try library.writePhoto(prepared.data, fileName: fileName, entryID: entryID)
                } catch {
                    return nil
                }
                return PhotoRef(id: id, fileName: fileName, width: prepared.width, height: prepared.height)
            }
            if let ref { added.append(ref) }
        }
        if added.count < images.count { show("Some photos couldn't be added.") }
        return added
    }

    /// The saved file for a photo, for sharing. Nil if it is still downloading from iCloud.
    func photoData(entryID: UUID, photo: PhotoRef) async -> Data? {
        guard let library else { return nil }
        return await IO.run { () -> Data? in
            try? library.readPhoto(entryID: entryID, fileName: photo.fileName)
        }
    }

    func removePhotoFile(_ photo: PhotoRef, from entryID: UUID) {
        guard let library else { return }
        enqueueWrite { try library.removePhoto(photo, entryID: entryID) }
    }

    /// A downsized photo, cached in memory. Returns nil while the file is still downloading from iCloud.
    func image(entryID: UUID, photo: PhotoRef, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(entryID.uuidString)/\(photo.fileName)@\(Int(maxPixel))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let library else { return nil }
        let image = await IO.run { () -> UIImage? in
            guard let data = try? library.readPhoto(entryID: entryID, fileName: photo.fileName) else { return nil }
            return ImageTools.downsample(data, maxPixel: maxPixel)
        }
        if let image {
            let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
            thumbnails.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    // MARK: Templates

    func newTemplate() -> EntryTemplate {
        let next = (templates.map(\.sortOrder).max() ?? -1) + 1
        return EntryTemplate(name: "New template", body: "", sortOrder: next)
    }

    /// The template new entries in this journal start with, if the journal has one.
    func defaultTemplate(for journalID: UUID) -> EntryTemplate? {
        guard let templateID = journal(journalID)?.defaultTemplateID else { return nil }
        return template(templateID)
    }

    /// Templates, the ones used most first.
    func templatesByUse() -> [EntryTemplate] {
        templates.sorted { a, b in
            let usedA = templateUseCounts[a.id] ?? 0
            let usedB = templateUseCounts[b.id] ?? 0
            if usedA != usedB { return usedA > usedB }
            return (a.sortOrder, a.createdAt) < (b.sortOrder, b.createdAt)
        }
    }

    func recordTemplateUse(_ id: UUID) {
        templateUseCounts[id, default: 0] += 1
        let stored = Dictionary(uniqueKeysWithValues: templateUseCounts.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(stored, forKey: AppModel.useCountsKey)
    }

    private static let useCountsKey = "templates.useCounts"

    private static func loadUseCounts() -> [UUID: Int] {
        guard let stored = UserDefaults.standard.dictionary(forKey: useCountsKey) as? [String: Int] else { return [:] }
        var counts: [UUID: Int] = [:]
        for (key, value) in stored {
            if let id = UUID(uuidString: key) { counts[id] = value }
        }
        return counts
    }

    func save(template: EntryTemplate) {
        guard let library else { return }
        var edited = template
        edited.modifiedAt = Date()
        let saved = edited
        if let index = templates.firstIndex(where: { $0.id == saved.id }) {
            templates[index] = saved
        } else {
            templates.append(saved)
        }
        templates.sort { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        enqueueWrite { try library.save(saved) }
    }

    func deleteTemplate(_ id: UUID) {
        guard let library else { return }
        templates.removeAll { $0.id == id }
        enqueueWrite { try library.deleteTemplate(id: id) }
    }

    // MARK: Journals

    func newJournal(named name: String) -> Journal {
        let next = (journals.map(\.sortOrder).max() ?? -1) + 1
        let color = JournalColors.keys[journals.count % JournalColors.keys.count]
        return Journal(id: UUID(), name: name, colorKey: color, sortOrder: next, createdAt: Date())
    }

    func save(journal: Journal) {
        guard let library else { return }
        if let index = journals.firstIndex(where: { $0.id == journal.id }) {
            journals[index] = journal
        } else {
            journals.append(journal)
        }
        journals.sort { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        enqueueWrite { try library.save(journal) }
    }

    func moveJournals(from source: IndexSet, to destination: Int) {
        var list = journals
        list.move(fromOffsets: source, toOffset: destination)
        for (position, journal) in list.enumerated() {
            var reordered = journal
            reordered.sortOrder = position
            save(journal: reordered)
        }
    }

    /// A journal can only be deleted when it has no entries, so nothing is ever orphaned.
    @discardableResult
    func deleteJournal(_ id: UUID) -> Bool {
        guard let library, journals.count > 1, entryCount(in: id) == 0 else { return false }
        journals.removeAll { $0.id == id }
        enqueueWrite { try library.deleteJournal(id: id) }
        return true
    }

    // MARK: Settings in the folder

    func setHome(_ location: EntryLocation?) {
        guard let library else { return }
        settings.home = location
        let saved = settings
        enqueueWrite { try library.save(saved) }
    }

    // MARK: Recently Deleted

    func loadTrash() async -> [TrashedEntry] {
        guard let library else { return [] }
        return await IO.run { library.trashedEntries() }
    }

    func restore(_ id: UUID) async {
        guard let library else { return }
        let restored = await IO.run { (try? library.restore(entryID: id)) != nil }
        if restored {
            await refresh()
            show("Restored.")
        } else {
            show("Couldn't restore that entry.")
        }
    }

    func deleteForever(_ id: UUID) async {
        guard let library else { return }
        await IO.run { _ = try? library.deleteForever(entryID: id) }
    }

    // MARK: Messages

    func show(_ text: String, lookBack: LookBack? = nil) {
        toastTask?.cancel()
        toast = Toast(text: text, lookBack: lookBack)
        // A look back stays long enough to read.
        let nanoseconds: UInt64 = lookBack == nil ? 3_200_000_000 : 10_000_000_000
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
