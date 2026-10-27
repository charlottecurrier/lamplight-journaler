import SwiftUI

/// Shown in the detail column when no entry is chosen.
struct DetailPlaceholder: View {
    var onCompose: (NewEntryChoice) -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "book",
            title: "Choose an entry",
            message: "Or begin a new one for tonight.",
            actionTitle: "New Entry",
            action: { onCompose(.standard) }
        )
        .background(PaperBackground())
    }
}

/// One entry, for reading. Switches to the editor when you tap Edit.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    /// The entry before and after this one in the list, for turning the page. Nil at either end.
    var olderEntry: (UUID) -> UUID?
    var newerEntry: (UUID) -> UUID?
    var onTurn: (UUID) -> Void
    var onCompose: (NewEntryChoice) -> Void
    var onClose: () -> Void

    @State private var viewer: PhotoViewerItem?
    @State private var confirmDelete = false
    /// Where the person tapped to start editing, until they finish.
    @State private var tappedCaret: Int?
    /// How far the page is slid sideways while turning.
    @State private var pageOffset: CGFloat = 0
    /// True while a page is turning, so a second swipe can't fight it.
    @State private var turning = false
    /// A file being prepared for sharing, and the file once it is ready.
    @State private var exporting = false
    @State private var shareItem: ShareItem?

    var body: some View {
        Group {
            if let entry = model.entry(entryID) {
                if model.editingEntryID == entryID {
                    EntryEditorView(
                        entry: entry,
                        initialCaret: tappedCaret ?? startingCaret(for: entry),
                        startQuietly: model.quietStartID == entryID,
                        onDone: { wasNew in
                            // A new entry goes back to the list when it is finished.
                            if wasNew { onClose() }
                        }
                    )
                    .id(entryID)
                    .onDisappear { tappedCaret = nil }
                } else {
                    reader(entry)
                        .id(entryID)
                }
            } else {
                // The entry is gone (an empty new entry, or deleted elsewhere). Leave this screen.
                DetailPlaceholder(onCompose: onCompose)
                    .onAppear { onClose() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.editingEntryID == entryID)
        .disabled(exporting)
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url) { shareItem = nil }
                .presentationDetents([.medium, .large])
        }
        .overlay {
            if exporting {
                ProgressView("Preparing")
                    .font(Theme.serif(.callout))
                    .padding(20)
                    .paperCard(radius: 18, raised: true)
            }
        }
    }

    // MARK: Turning the page

    private func isPageSwipe(_ value: DragGesture.Value) -> Bool {
        // Not from the left edge, which goes back on a phone. Mostly sideways, so scrolling still works.
        value.startLocation.x > 30 && abs(value.translation.width) > abs(value.translation.height) * 2.5
    }

    private func settlePage() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pageOffset = 0 }
    }

    /// Swipe right for the entry before this one, left for the one after, like turning pages of a book.
    private func pageTurn(for entry: Entry) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                guard !turning, isPageSwipe(value) else { return }
                pageOffset = value.translation.width * 0.4
            }
            .onEnded { value in
                guard !turning else { return }
                guard isPageSwipe(value) else {
                    settlePage()
                    return
                }
                let toOlder = value.translation.width > 0
                let target = toOlder ? olderEntry(entry.id) : newerEntry(entry.id)
                let farEnough = abs(value.translation.width) > 90 || abs(value.predictedEndTranslation.width) > 240
                guard farEnough, let target else {
                    settlePage()
                    return
                }
                turn(to: target, toOlder: toOlder)
            }
    }

    private func turn(to id: UUID, toOlder: Bool) {
        let distance: CGFloat = toOlder ? 140 : -140
        turning = true
        withAnimation(.easeIn(duration: 0.14)) { pageOffset = distance }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            onTurn(id)
            // The next page comes in from the other side.
            pageOffset = -distance
            try? await Task.sleep(nanoseconds: 40_000_000)
            withAnimation(.easeOut(duration: 0.26)) { pageOffset = 0 }
            try? await Task.sleep(nanoseconds: 270_000_000)
            turning = false
        }
    }

    /// A brand-new entry made from a template starts with the caret under its first heading.
    private func startingCaret(for entry: Entry) -> Int? {
        guard model.freshEntryIDs.contains(entry.id), entry.templateID != nil else { return nil }
        return TemplateText.initialCaret(inEditorText: EditorText.fromMarkdown(entry.body))
    }

    /// The words only: a photo in the text is a line of Markdown that means nothing to the person it is sent to.
    private func shareText(_ entry: Entry) -> String {
        Fmt.fullDate(entry) + "\n\n" + MediaLine.stripped(entry.body)
    }

    /// Opens a photo full screen. Swiping goes on through the entry's other photos, in reading order.
    private func openPhoto(_ photo: PhotoRef, in entry: Entry) {
        let photos = entry.orderedPhotos
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        viewer = PhotoViewerItem(entryID: entry.id, photos: photos, index: index)
    }

    private func mediaContext(for entry: Entry) -> MediaContext {
        let entryID = entry.id
        return MediaContext(
            photos: entry.photos,
            cached: { photo, size in model.cachedImage(entryID: entryID, photo: photo, maxPixel: size) },
            load: { photo, size in await model.image(entryID: entryID, photo: photo, maxPixel: size) },
            onOpen: { photo in
                if let current = model.entry(entryID) { openPhoto(photo, in: current) }
            },
            refreshToken: model.refreshCounter
        )
    }

    /// Makes a Markdown file or PDF of the entry, then offers it to the share sheet.
    private func share(_ entry: Entry, as format: EntryExporter.Format) {
        guard !exporting else { return }
        exporting = true
        Task { @MainActor in
            let outcome = await EntryExporter.export(entry, format: format, model: model)
            exporting = false
            // If the person moved on to another entry or started editing, a sheet now would be confusing.
            guard entryID == entry.id, model.editingEntryID != entry.id else { return }
            switch outcome {
            case .file(let url):
                shareItem = ShareItem(url: url)
            case .photosNotReady:
                model.show("Some photos are still coming down from iCloud. Try again in a moment.")
            case .failed:
                model.show("Couldn't prepare that to share.")
            }
        }
    }

    /// Ticking a checklist item while reading changes the entry.
    private func bodyBinding(_ entry: Entry) -> Binding<String> {
        Binding(
            get: { model.entry(entry.id)?.body ?? entry.body },
            set: { newBody in
                guard var current = model.entry(entry.id), current.body != newBody else { return }
                current.body = newBody
                current.modifiedAt = Date()
                model.update(current)
            }
        )
    }

    private func reader(_ entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Fmt.fullDate(entry))
                        .font(Theme.serif(.title, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 14) {
                            Text(Fmt.time(entry))
                            MoonLabel(date: entry.createdAt)
                        }
                        if entry.location != nil || model.journals.count > 1 {
                            HStack(spacing: 12) {
                                if let location = entry.location {
                                    Label(location.name, systemImage: location.isHome ? "house" : "mappin")
                                        .labelStyle(.titleAndIcon)
                                }
                                if model.journals.count > 1 {
                                    JournalChip(journal: model.journal(entry.journalID))
                                }
                            }
                        }
                    }
                    .font(Theme.serif(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                }

                let unplaced = entry.unplacedPhotos
                if !unplaced.isEmpty {
                    PhotoMosaic(entryID: entry.id, photos: unplaced) { index in
                        openPhoto(unplaced[index], in: entry)
                    }
                }

                MarkdownEditor(
                    text: bodyBinding(entry),
                    isEditable: false,
                    onTapToEdit: { caret in
                        tappedCaret = caret
                        model.editingEntryID = entry.id
                    },
                    media: mediaContext(for: entry)
                )
            }
            .frame(maxWidth: Theme.readingWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
            .offset(x: pageOffset)
            .opacity(1 - min(Double(abs(pageOffset)) / 300, 0.6))
        }
        .simultaneousGesture(pageTurn(for: entry))
        // Swiping isn't possible with VoiceOver, so the same turns are offered as actions.
        .accessibilityAction(named: "Older entry") {
            if let id = olderEntry(entry.id) { onTurn(id) }
        }
        .accessibilityAction(named: "Newer entry") {
            if let id = newerEntry(entry.id) { onTurn(id) }
        }
        .background(PaperBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.toggleFavorite(entry.id)
                } label: {
                    Label(
                        entry.isFavorite ? "Remove Favorite" : "Favorite",
                        systemImage: entry.isFavorite ? "bookmark.fill" : "bookmark"
                    )
                }

                Button {
                    tappedCaret = nil
                    model.editingEntryID = entry.id
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)

                Menu {
                    Menu {
                        ShareLink(item: shareText(entry)) {
                            Label("Text", systemImage: "text.alignleft")
                        }
                        Button {
                            share(entry, as: .markdown)
                        } label: {
                            Label("Markdown File", systemImage: "doc.plaintext")
                        }
                        Button {
                            share(entry, as: .pdf)
                        } label: {
                            Label("PDF", systemImage: "doc.richtext")
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if model.journals.count > 1 {
                        Menu {
                            ForEach(model.journals) { journal in
                                Button(journal.name) { model.move(entry.id, toJournal: journal.id) }
                            }
                        } label: {
                            Label("Move to Journal", systemImage: "book.closed")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.moveToTrash(entry.id)
                onClose()
            }
        } message: {
            Text("It moves to Recently Deleted, where you can restore it for 30 days.")
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(item: item)
        }
    }
}
