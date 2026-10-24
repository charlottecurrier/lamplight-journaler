import UIKit

/// Makes a Markdown file or a PDF of one entry, in a temporary folder, ready for the share sheet.
/// Nothing here changes the journal. The files are copies.
@MainActor
enum EntryExporter {
    enum Format {
        case markdown
        case pdf
    }

    static func export(_ entry: Entry, format: Format, model: AppModel) async -> URL? {
        switch format {
        case .markdown: return await markdown(entry, model: model)
        case .pdf: return await pdf(entry, model: model)
        }
    }

    // MARK: Words

    private static func details(_ entry: Entry, model: AppModel) -> String {
        var parts = [Fmt.time(entry), MoonPhase(on: entry.createdAt).name]
        if let place = entry.location?.name { parts.append(place) }
        if model.journals.count > 1 { parts.append(model.journalName(entry.journalID)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Folders

    /// A fresh folder for one export. Older exports are cleared first so they don't pile up.
    private static func freshFolder(named name: String) throws -> (container: URL, folder: URL) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Lamplight Export", isDirectory: true)
        try? manager.removeItem(at: root)
        let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = container.appendingPathComponent(name, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return (container, folder)
    }

    // MARK: Markdown

    /// A single .md file, or a zip with the file and a photos folder when the entry has photos.
    private static func markdown(_ entry: Entry, model: AppModel) async -> URL? {
        let name = EntryExport.baseFileName(for: entry)
        do {
            let (container, folder) = try freshFolder(named: name)
            var photoFiles: [String] = []
            if !entry.photos.isEmpty {
                let photosFolder = folder.appendingPathComponent("photos", isDirectory: true)
                try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
                for photo in entry.photos {
                    guard let data = await model.photoData(entryID: entry.id, photo: photo) else { continue }
                    try data.write(to: photosFolder.appendingPathComponent(photo.fileName))
                    photoFiles.append(photo.fileName)
                }
            }
            let text = EntryExport.markdown(
                title: Fmt.fullDate(entry), details: details(entry, model: model),
                body: entry.body, photoFiles: photoFiles
            )
            let file = folder.appendingPathComponent(name + ".md")
            try Data(text.utf8).write(to: file)
            guard !photoFiles.isEmpty else { return file }
            return zip(folder, in: container, named: name)
        } catch {
            return nil
        }
    }

    /// A zip of a folder, made the way iOS makes one for sharing.
    private static func zip(_ folder: URL, in container: URL, named name: String) -> URL? {
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

    private static func pdf(_ entry: Entry, model: AppModel) async -> URL? {
        var sources: [String] = []
        for photo in entry.photos {
            guard let data = await model.photoData(entryID: entry.id, photo: photo),
                  let small = ImageTools.prepareForStorage(data, maxPixel: 1400, quality: 0.8) else { continue }
            sources.append("data:image/jpeg;base64," + small.data.base64EncodedString())
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
