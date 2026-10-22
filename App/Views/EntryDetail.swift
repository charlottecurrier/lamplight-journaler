import SwiftUI

/// Shown in the detail column when no entry is chosen.
struct DetailPlaceholder: View {
    @Environment(AppModel.self) private var model
    var onCompose: (NewEntryChoice) -> Void

    var body: some View {
        if model.templates.isEmpty {
            EmptyStateView(
                systemImage: "book",
                title: "Choose an entry",
                message: "Or begin a new one for tonight.",
                actionTitle: "New Entry",
                action: { onCompose(.blank) }
            )
            .background(PaperBackground())
        } else {
            EmptyStateView(
                systemImage: "book",
                title: "Choose an entry",
                message: "Or begin a new one for tonight.",
                extra: AnyView(StartWithTemplates(onChoose: onCompose).frame(maxWidth: 520))
            )
            .background(PaperBackground())
        }
    }
}

/// One entry, for reading. Switches to the editor when you tap Edit.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    var onCompose: (NewEntryChoice) -> Void
    var onClose: () -> Void

    @State private var viewer: PhotoViewerItem?
    @State private var confirmDelete = false

    var body: some View {
        if let entry = model.entry(entryID) {
            if model.editingEntryID == entryID {
                EntryEditorView(entry: entry, initialCaret: startingCaret(for: entry))
                    .id(entryID)
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

    /// A brand-new entry made from a template starts with the caret under its first heading.
    private func startingCaret(for entry: Entry) -> Int? {
        guard model.freshEntryIDs.contains(entry.id), entry.templateID != nil else { return nil }
        return TemplateText.initialCaret(inEditorText: EditorText.fromMarkdown(entry.body))
    }

    private func shareText(_ entry: Entry) -> String {
        Fmt.fullDate(entry) + "\n\n" + entry.body
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
                    HStack(spacing: 12) {
                        Text(Fmt.time(entry))
                        if let location = entry.location {
                            Label(location.name, systemImage: location.isHome ? "house" : "mappin")
                                .labelStyle(.titleAndIcon)
                        }
                        if model.journals.count > 1 {
                            JournalChip(journal: model.journal(entry.journalID))
                        }
                    }
                    .font(Theme.serif(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                }

                if !entry.photos.isEmpty {
                    PhotoMosaic(entry: entry) { index in
                        viewer = PhotoViewerItem(entryID: entry.id, photos: entry.photos, index: index)
                    }
                }

                MarkdownEditor(text: bodyBinding(entry), isEditable: false)
            }
            .frame(maxWidth: Theme.readingWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
        .background(PaperBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.editingEntryID = entry.id
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)

                Menu {
                    ShareLink(item: shareText(entry)) {
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
