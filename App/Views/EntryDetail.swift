import SwiftUI

/// An entry's text with headings styled and simple inline Markdown (bold, italic, links) shown.
struct MarkdownBodyView: View {
    let text: String

    private func inline(_ string: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return Theme.serif(.title2, weight: .bold)
        case 2: return Theme.serif(.title3, weight: .semibold)
        default: return Theme.serif(.headline, weight: .semibold)
        }
    }

    var body: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let value):
                    Text(inline(value))
                        .font(headingFont(level))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                case .paragraph(let value):
                    Text(inline(value))
                        .font(Theme.serif(.title3))
                        .lineSpacing(7)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// Shown in the detail column when no entry is chosen.
struct DetailPlaceholder: View {
    var onCompose: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "book",
            title: "Choose an entry",
            message: "Or begin a new one for tonight.",
            actionTitle: "New Entry",
            action: onCompose
        )
        .background(PaperBackground())
    }
}

/// One entry, for reading. Switches to the editor when you tap Edit.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    var onCompose: () -> Void
    var onClose: () -> Void

    @State private var viewer: PhotoViewerItem?
    @State private var confirmDelete = false

    var body: some View {
        if let entry = model.entry(entryID) {
            if model.editingEntryID == entryID {
                EntryEditorView(entry: entry)
                    .id(entryID)
            } else {
                reader(entry)
            }
        } else {
            DetailPlaceholder(onCompose: onCompose)
        }
    }

    private func shareText(_ entry: Entry) -> String {
        Fmt.fullDate(entry) + "\n\n" + entry.body
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

                MarkdownBodyView(text: entry.body)
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
