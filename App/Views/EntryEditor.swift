import SwiftUI
import PhotosUI

/// The writing screen. Everything you type is saved as you go, so there is no Save button to forget.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: Entry
    /// The last version handed to the model. Used to skip saves when nothing changed.
    @State private var committed: Entry
    @State private var saveTask: Task<Void, Never>?
    @State private var controller = MarkdownEditorController()
    @State private var focusMode = false
    private let initialCaret: Int?
    /// Called after Done. The flag says the entry was new, so the screen can go back to the list.
    private let onDone: (Bool) -> Void
    @State private var closing = false
    /// Decided when the page opens and kept, so the keyboard doesn't jump up when the entry is finished.
    @State private var startQuietly: Bool

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    /// File names of photos that have been in the text during this visit. One taken out of the text is kept until
    /// the entry is finished, so deleting it can still be undone.
    @State private var placedThisVisit: Set<String>
    @State private var showDate = false
    @State private var showPlace = false
    @State private var viewer: PhotoViewerItem?

    init(
        entry: Entry, initialCaret: Int? = nil, startQuietly: Bool = false,
        onDone: @escaping (Bool) -> Void = { _ in }
    ) {
        _draft = State(initialValue: entry)
        _committed = State(initialValue: entry)
        _placedThisVisit = State(initialValue: Set(entry.placedFileNames))
        _startQuietly = State(initialValue: startQuietly)
        self.initialCaret = initialCaret
        self.onDone = onDone
    }

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !focusMode {
                header
                if !stripPhotos.isEmpty || isImporting { photoStrip }
            }
            editor
        }
        .frame(maxWidth: Theme.readingWidth)
        .padding(.horizontal, 24)
        .padding(.top, focusMode ? 0 : 14)
        .frame(maxWidth: .infinity)
        // Done closes the page: it settles back and fades before the list is shown.
        .scaleEffect(closing ? 0.97 : 1, anchor: .top)
        .opacity(closing ? 0 : 1)
        .background(PaperBackground())
        .overlay(alignment: .topTrailing) {
            if focusMode { leaveFocusButton }
        }
        .animation(.easeInOut(duration: 0.3), value: focusMode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(focusMode ? .hidden : .visible, for: .navigationBar)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showDate) {
            DateSheet(date: $draft.createdAt)
        }
        .sheet(isPresented: $showPlace) {
            LocationPickerView(current: draft.location, home: model.settings.home) { place in
                draft.location = place
            }
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(item: item)
        }
        .onChange(of: draft) { scheduleSave() }
        .onChange(of: draft.body) { notePlacedPhotos() }
        .onChange(of: draft.createdAt) { draft.timeZoneID = TimeZone.current.identifier }
        .onChange(of: pickerItems) { importPicked() }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                saveTask?.cancel()
                commit()
            }
        }
        .onChange(of: showDate) { if !showDate { controller.focus() } }
        .onChange(of: showPlace) { if !showPlace { controller.focus() } }
        .onDisappear {
            saveTask?.cancel()
            // A full-screen photo covers this screen without leaving it.
            if viewer == nil {
                dropEmptyTemplateHeadings()
                removeDeletedPhotos()
            }
            commit()
            guard viewer == nil else { return }
            // If Done was tapped a moment ago, the message is still owed.
            model.finishEditing(draft.id, announce: closing, calendar: prefs.dayCalendar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showDate = true
            } label: {
                HStack(spacing: 8) {
                    Text(Fmt.fullDate(draft))
                        .font(Theme.serif(.title2, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .fontWeight(Theme.iconWeight)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date: \(Fmt.fullDate(draft)), \(Fmt.time(draft))")
            .accessibilityHint("Change the date and time")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text(Fmt.time(draft))
                    MoonLabel(date: draft.createdAt)
                }
                HStack(spacing: 16) {
                    if model.journals.count > 1 { journalMenu }
                    placeButton
                }
            }
            .font(Theme.serif(.subheadline))
            .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var journalMenu: some View {
        Menu {
            Picker("Journal", selection: $draft.journalID) {
                ForEach(model.journals) { journal in
                    Text(journal.name).tag(journal.id)
                }
            }
        } label: {
            JournalChip(journal: model.journal(draft.journalID))
        }
    }

    private var placeButton: some View {
        Button {
            showPlace = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: placeIcon)
                    .imageScale(.small)
                Text(draft.location?.name ?? "Add place")
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.location.map { "Place: \($0.name)" } ?? "Add a place")
    }

    private var placeIcon: String {
        guard let place = draft.location else { return "mappin.and.ellipse" }
        return place.isHome ? "house" : "mappin"
    }

    /// Photos that are not in the text. Entries from before photos could be placed show theirs here.
    private var stripPhotos: [PhotoRef] {
        let placed = Set(draft.placedFileNames)
        return draft.photos.filter { !placed.contains($0.fileName) && !placedThisVisit.contains($0.fileName) }
    }

    /// The photos that came from the text stay out of the strip even after they are deleted from the text.
    private func notePlacedPhotos() {
        guard MediaLine.mayContain(draft.body) else { return }
        placedThisVisit.formUnion(draft.placedFileNames)
    }

    /// A photo taken out of the text goes where removed photos go: it is kept in the entry's Removed folder.
    /// This waits until the entry is finished, so that deleting a photo can still be undone while writing.
    private func removeDeletedPhotos() {
        let placed = Set(draft.placedFileNames)
        for photo in draft.photos where placedThisVisit.contains(photo.fileName) && !placed.contains(photo.fileName) {
            // If the text still names the file anywhere, such as in a line that didn't read as a picture, the photo
            // is still wanted. Only a photo nothing mentions is removed.
            if draft.body.contains("\(MediaLine.photosFolder)/\(photo.fileName)") { continue }
            draft.photos.removeAll { $0.id == photo.id }
            model.removePhotoFile(photo, from: draft.id)
        }
    }

    private func openPhoto(_ photo: PhotoRef) {
        // Photos taken out of the text this visit are waiting to be removed, so swiping doesn't go to them.
        let placed = Set(draft.placedFileNames)
        let photos = draft.orderedPhotos.filter { placed.contains($0.fileName) || !placedThisVisit.contains($0.fileName) }
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        controller.dismissKeyboard()
        viewer = PhotoViewerItem(entryID: draft.id, photos: photos, index: index)
    }

    private var mediaContext: MediaContext {
        let entryID = draft.id
        return MediaContext(
            photos: draft.photos,
            cached: { photo, size in model.cachedImage(entryID: entryID, photo: photo, maxPixel: size) },
            load: { photo, size in await model.image(entryID: entryID, photo: photo, maxPixel: size) },
            onOpen: { photo in openPhoto(photo) },
            refreshToken: model.refreshCounter
        )
    }

    private var photoStrip: some View {
        let photos = stripPhotos
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            openPhoto(photo)
                        } label: {
                            PhotoThumb(entryID: draft.id, photo: photo, maxPixel: 320)
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count)")

                        Button {
                            removePhoto(photo)
                        } label: {
                            // A thin cross on a paper chip, with a full-size area to tap around it.
                            PaperCloseChip(diameter: 24)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .offset(x: 16, y: -16)
                        .accessibilityLabel("Remove photo \(index + 1)")
                    }
                }
                if isImporting {
                    ProgressView()
                        .frame(width: 84, height: 84)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: $draft.body,
            isFocusMode: focusMode,
            // An entry the app opened by itself waits for a tap before showing the keyboard.
            wantsFocus: !startQuietly,
            initialCaret: initialCaret,
            controller: controller,
            media: mediaContext
        )
        .overlay(alignment: .topLeading) {
            if draft.body.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Start writing…")
                        .font(Theme.serif(.title3))
                        .foregroundStyle(Theme.inkTertiary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    if !model.templates.isEmpty {
                        templatePicker
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// On an empty page, your templates are offered. Typing anything makes them go away.
    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Or begin with a template")
                .padding(.bottom, 4)
            ForEach(model.templatesByUse().prefix(sizeClass == .compact ? 3 : 5)) { template in
                Button {
                    add(template)
                } label: {
                    Label(template.name, systemImage: "doc.text")
                        .font(Theme.serif(.body))
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var leaveFocusButton: some View {
        Button {
            focusMode = false
        } label: {
            PaperIcon("arrow.down.right.and.arrow.up.left", size: .small)
                .foregroundStyle(Theme.inkTertiary)
                .padding(14)
        }
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Leave focus mode")
    }

    /// Everything the format bar does, for people on a hardware keyboard, plus templates and focus mode.
    private var formatMenu: some View {
        Menu {
            Menu {
                Button("Heading 1") { controller.apply(.heading(1)) }
                Button("Heading 2") { controller.apply(.heading(2)) }
                Button("Heading 3") { controller.apply(.heading(3)) }
                Button("Body Text") { controller.apply(.heading(0)) }
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            // Grouped so the menu never has more than ten direct children.
            Group {
                Button { controller.apply(.bold) } label: { Label("Bold", systemImage: "bold") }
                Button { controller.apply(.italic) } label: { Label("Italic", systemImage: "italic") }
                Button { controller.apply(.strike) } label: { Label("Strikethrough", systemImage: "strikethrough") }
                Button { controller.apply(.highlight) } label: { Label("Highlight", systemImage: "highlighter") }
            }
            Divider()
            Group {
                Button { controller.apply(.bullet) } label: { Label("Bulleted List", systemImage: "list.bullet") }
                Button { controller.apply(.numbered) } label: { Label("Numbered List", systemImage: "list.number") }
                Button { controller.apply(.checklist) } label: { Label("Checklist", systemImage: "checklist") }
                Button { controller.apply(.quote) } label: { Label("Quote", systemImage: "text.quote") }
                Button { controller.apply(.link) } label: { Label("Link", systemImage: "link") }
                Button { controller.apply(.divider) } label: { Label("Divider", systemImage: "minus") }
                Button { controller.apply(.section) } label: { Label("Section", systemImage: "minus.rectangle") }
            }
            Divider()
            if !model.templates.isEmpty {
                Menu {
                    ForEach(model.templatesByUse()) { template in
                        Button(template.name) { add(template) }
                    }
                } label: {
                    Label("Add Template", systemImage: "doc.badge.plus")
                }
            }
            Button {
                focusMode = true
            } label: {
                Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } label: {
            PaperIcon("textformat")
        }
        .accessibilityLabel("Format")
    }

    /// Puts a template's text into the entry at the cursor.
    private func add(_ template: EntryTemplate) {
        let wasEmpty = draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        controller.insertTemplate(template.body)
        model.recordTemplateUse(template.id)
        if draft.templateID == nil { draft.templateID = template.id }
        // A page holding only the template is not worth a file until something is written in it.
        if wasEmpty {
            model.noteTemplateApplied(to: draft.id, body: EditorText.toMarkdown(EditorText.fromMarkdown(template.body)))
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 12, matching: .images) {
                PaperIcon("photo.on.rectangle")
            }
            .accessibilityLabel("Add Photos")
            Button {
                showPlace = true
            } label: {
                PaperIcon("mappin.and.ellipse")
            }
            .accessibilityLabel("Place")
            formatMenu
            Button {
                finish()
            } label: {
                Text("Done").font(Theme.serif(.body, weight: .semibold))
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        guard draft != committed else { return }
        var toSave = draft
        toSave.modifiedAt = Date()
        // The editor never changes this, so keep what the list or reader set while it was open.
        toSave.isFavorite = model.entry(draft.id)?.isFavorite ?? draft.isFavorite
        committed = draft
        model.update(toSave)
    }

    /// Takes out template headings nothing was written under. What the person wrote is never touched.
    private func dropEmptyTemplateHeadings() {
        // A page still holding only its template is dropped as a whole, so leave it as it is.
        guard !model.isUnwritten(draft), let templateID = draft.templateID, let template = model.template(templateID) else { return }
        let cleaned = TemplateText.removingEmptyHeadings(from: draft.body, template: template.body)
        if cleaned != draft.body { draft.body = cleaned }
    }

    private func finish() {
        guard !closing else { return }
        saveTask?.cancel()
        dropEmptyTemplateHeadings()
        removeDeletedPhotos()
        commit()
        controller.dismissKeyboard()
        let wasNew = model.freshEntryIDs.contains(draft.id)
        let id = draft.id
        let calendar = prefs.dayCalendar
        guard !reduceMotion else {
            model.finishEditing(id, announce: true, calendar: calendar)
            onDone(wasNew)
            return
        }
        withAnimation(.easeIn(duration: 0.32)) { closing = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 330_000_000)
            // The person may have left the page in that moment, which already finished it.
            guard model.editingEntryID == id else { return }
            model.finishEditing(id, announce: true, calendar: calendar)
            onDone(wasNew)
        }
    }

    // MARK: Photos

    private func importPicked() {
        let items = pickerItems
        pickerItems = []
        guard !items.isEmpty else { return }
        Task { @MainActor in
            isImporting = true
            var images: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    images.append(data)
                }
            }
            let added = await model.addPhotos(images, to: draft.id)
            draft.photos.append(contentsOf: added)
            // Each photo goes into the text at the caret, on a line of its own.
            controller.insertPhotos(added)
            isImporting = false
            saveTask?.cancel()
            commit()
        }
    }

    private func removePhoto(_ photo: PhotoRef) {
        draft.photos.removeAll { $0.id == photo.id }
        model.removePhotoFile(photo, from: draft.id)
        saveTask?.cancel()
        commit()
    }
}

/// Change when an entry was written. Handy for filling in yesterday.
struct DateSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(
                    "Entry date",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
            }
            .background(PaperBackground())
            .navigationTitle("Date and Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
