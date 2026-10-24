import UIKit

/// Makes a Markdown file or a PDF of one entry, in a temporary folder, ready for the share sheet.
/// Nothing here changes the journal. The files are copies.
@MainActor
enum EntryExporter {
    enum Format {
        case markdown
        case pdf
    }

    enum Outcome {
        case file(URL)
        /// Some photos haven't finished coming down from iCloud, so a copy would be missing them.
        case photosNotReady
        case failed
    }

    static func export(_ entry: Entry, format: Format, model: AppModel) async -> Outcome {
        // A copy with photos missing would look complete and isn't, so wait for all of them or say so.
        guard let photos = await loadPhotos(entry, model: model) else { return .photosNotReady }
        let file: URL?
        switch format {
        case .markdown: file = await markdown(entry, photos: photos, model: model)
        case .pdf: file = await pdf(entry, photos: photos, model: model)
        }
        return file.map(Outcome.file) ?? .failed
    }

    // MARK: Pieces

    private static func details(_ entry: Entry, model: AppModel) -> String {
        var parts = [Fmt.time(entry), MoonPhase(on: entry.createdAt).name]
        if let place = entry.location?.name { parts.append(place) }
        if model.journals.count > 1 { parts.append(model.journalName(entry.journalID)) }
        return parts.joined(separator: " · ")
    }

    /// Every photo of the entry, read at the same time. Nil if any of them can't be read yet.
    private static func loadPhotos(_ entry: Entry, model: AppModel) async -> [(photo: PhotoRef, data: Data)]? {
        guard !entry.photos.isEmpty else { return [] }
        let loaded = await withTaskGroup(of: (Int, Data?).self, returning: [Int: Data].self) { group in
            for (index, photo) in entry.photos.enumerated() {
                group.addTask { @MainActor in
                    (index, await model.photoData(entryID: entry.id, photo: photo))
                }
            }
            var all: [Int: Data] = [:]
            for await (index, data) in group {
                if let data { all[index] = data }
            }
            return all
        }
        guard loaded.count == entry.photos.count else { return nil }
        return entry.photos.enumerated().map { ($0.element, loaded[$0.offset] ?? Data()) }
    }

    // MARK: Folders

    /// A fresh folder for one export. Exports from earlier than an hour ago are cleared out.
    private static func freshFolder(named name: String) throws -> (container: URL, folder: URL) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Lamplight Export", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-3600)
        for old in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? old.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? manager.removeItem(at: old) }
        }
        let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = container.appendingPathComponent(name, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return (container, folder)
    }

    // MARK: Markdown

    /// A single .md file, or a zip with the file and a photos folder when the entry has photos.
    private static func markdown(
        _ entry: Entry, photos: [(photo: PhotoRef, data: Data)], model: AppModel
    ) async -> URL? {
        let name = EntryExport.baseFileName(for: entry)
        let text = EntryExport.markdown(
            title: Fmt.fullDate(entry), details: details(entry, model: model),
            body: entry.body, photoFiles: photos.map(\.photo.fileName)
        )
        do {
            let (container, folder) = try freshFolder(named: name)
            let file = folder.appendingPathComponent(name + ".md")
            try Data(text.utf8).write(to: file)
            guard !photos.isEmpty else { return file }
            let files = photos.map { ($0.photo.fileName, $0.data) }
            return await IO.run { () -> URL? in
                do {
                    let photosFolder = folder.appendingPathComponent("photos", isDirectory: true)
                    try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
                    for (fileName, data) in files {
                        try data.write(to: photosFolder.appendingPathComponent(fileName))
                    }
                } catch {
                    return nil
                }
                return makeZip(folder, in: container, named: name)
            }
        } catch {
            return nil
        }
    }

    /// A zip of a folder, made the way iOS makes one for sharing.
    private nonisolated static func makeZip(_ folder: URL, in container: URL, named name: String) -> URL? {
        var coordinationError: NSError?
        var result: URL?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zipped in
            let destination = container.appendingPathComponent(name + ".zip")
            try? FileManager.default.removeItem(at: destination)
            if (try? FileManager.default.copyItem(at: zipped, to: destination)) != nil {
                result = destination
            }
        }
        return result
    }

    // MARK: PDF

    private static func pdf(
        _ entry: Entry, photos: [(photo: PhotoRef, data: Data)], model: AppModel
    ) async -> URL? {
        // Shrinking the photos and encoding them is slow, so it happens off the main thread.
        let datas = photos.map(\.data)
        let sources = await IO.run { () -> [String] in
            datas.compactMap { data in
                ImageTools.prepareForStorage(data, maxPixel: 1400, quality: 0.8)
                    .map { "data:image/jpeg;base64," + $0.data.base64EncodedString() }
            }
        }
        let html = EntryExport.html(
            title: Fmt.fullDate(entry), details: details(entry, model: model),
            body: entry.body, photoSources: sources
        )
        guard let data = render(html: html) else { return nil }
        do {
            let name = EntryExport.baseFileName(for: entry)
            let (_, folder) = try freshFolder(named: name)
            let file = folder.appendingPathComponent(name + ".pdf")
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }

    /// Prints the page into PDF pages: US Letter in the US, A4 elsewhere, with generous margins.
    private static func render(html: String) -> Data? {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)

        let paper = Locale.current.measurementSystem == .us
            ? CGRect(x: 0, y: 0, width: 612, height: 792)
            : CGRect(x: 0, y: 0, width: 595, height: 842)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 58, dy: 64)), forKey: "printableRect")

        let pages = renderer.numberOfPages
        guard pages > 0 else { return nil }
        return UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            for page in 0..<pages {
                context.beginPage()
                renderer.drawPage(at: page, in: context.pdfContextBounds)
            }
        }
    }
}
