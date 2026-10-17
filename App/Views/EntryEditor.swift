import SwiftUI
import PhotosUI

/// The writing screen. Everything you type is saved as you go, so there is no Save button to forget.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: Entry
    /// The last version handed to the model. Used to skip saves when nothing changed.
    @State private var committed: Entry
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var showDate = false
    @State private var showPlace = false
    @State private var viewer: PhotoViewerItem?

    init(entry: Entry) {
        _draft = State(initialValue: entry)
        _committed = State(initialValue: entry)
    }

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !draft.photos.isEmpty || isImporting { photoStrip }
            editor
        }
        .frame(maxWidth: Theme.readingWidth)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
        .background(PaperBackground())
        .navigationBarTitleDisplayMode(.inline)
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
        .onChange(of: draft.createdAt) { draft.timeZoneID = TimeZone.current.identifier }
        .onChange(of: pickerItems) { importPicked() }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                saveTask?.cancel()
                commit()
            }
        }
        .task {
            // Give the screen a moment to settle, then bring up the keyboard.
            try? await Task.sleep(nanoseconds: 350_000_000)
            focused = true
        }
        .onChange(of: showDate) { if !showDate { focused = true } }
        .onChange(of: showPlace) { if !showPlace { focused = true } }
        .onDisappear {
            saveTask?.cancel()
            commit()
            // A full-screen photo covers this screen without leaving it.
            guard viewer == nil else { return }
            model.finishEditing(draft.id, announce: false, calendar: prefs.dayCalendar)
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
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date: \(Fmt.fullDate(draft)), \(Fmt.time(draft))")
            .accessibilityHint("Change the date and time")

            HStack(spacing: 16) {
                Text(Fmt.time(draft))
                if model.journals.count > 1 { journalMenu }
                placeButton
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

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(draft.photos.enumerated()), id: \.element.id) { index, photo in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            viewer = PhotoViewerItem(entryID: draft.id, photos: draft.photos, index: index)
                        } label: {
                            PhotoThumb(entryID: draft.id, photo: photo, maxPixel: 320)
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) of \(draft.photos.count)")

                        Button {
                            removePhoto(photo)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Theme.ink, Theme.surface)
                        }
                        .offset(x: 6, y: -6)
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
        TextEditor(text: $draft.body)
            .font(Theme.serif(.title3))
            .lineSpacing(7)
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .overlay(alignment: .topLeading) {
                if draft.body.isEmpty {
                    Text("Start writing…")
                        .font(Theme.serif(.title3))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Entry text")
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 12, matching: .images) {
                Label("Add Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                showPlace = true
            } label: {
                Label("Place", systemImage: "mappin.and.ellipse")
            }
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
        committed = draft
        model.update(toSave)
    }

    private func finish() {
        saveTask?.cancel()
        commit()
        focused = false
        model.finishEditing(draft.id, announce: true, calendar: prefs.dayCalendar)
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
