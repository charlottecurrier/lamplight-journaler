import SwiftUI

// MARK: - New entries

/// What to start a new entry with.
enum NewEntryChoice {
    /// The journal's default template, or an empty page that offers your templates.
    case standard
    case blank
    case template(EntryTemplate)
}

/// The New Entry button. It opens an empty page, where your templates are offered.
struct NewEntryButton: View {
    var onChoose: (NewEntryChoice) -> Void

    var body: some View {
        Button {
            onChoose(.standard)
        } label: {
            Label("New Entry", systemImage: "square.and.pencil")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

// MARK: - Shared pieces

extension View {
    /// Adds the "New Entry" button to a screen's toolbar. On a phone the bottom bar has one instead.
    func composeToolbar(_ onChoose: @escaping (NewEntryChoice) -> Void) -> some View {
        modifier(ComposeToolbar(onChoose: onChoose))
    }

    /// The long-press menu and swipe-to-delete for an entry row.
    func entryActions(_ entry: Entry, selection: Binding<UUID?>) -> some View {
        modifier(EntryRowActions(entry: entry, selection: selection))
    }

    func entryRowStyle(selected: Bool) -> some View {
        listRowBackground(selected ? Theme.surface : Color.clear)
            .listRowSeparatorTint(Theme.line)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

private struct ComposeToolbar: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var onChoose: (NewEntryChoice) -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if sizeClass != .compact {
                ToolbarItem(placement: .primaryAction) {
                    NewEntryButton(onChoose: onChoose)
                }
            }
        }
    }
}

/// Gives an entry row its long-press menu and a swipe to delete. Deleting moves it to Recently Deleted.
struct EntryRowActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let entry: Entry
    @Binding var selection: UUID?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                EntryMenuItems(entry: entry) {
                    selection = entry.id
                    model.editingEntryID = entry.id
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    model.moveToTrash(entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    model.toggleFavorite(entry.id)
                } label: {
                    Label(
                        entry.isFavorite ? "Remove Favorite" : "Favorite",
                        systemImage: entry.isFavorite ? "bookmark.slash" : "bookmark"
                    )
                }
                .tint(Theme.accent)
            }
    }
}

/// The long-press menu for an entry in any list.
struct EntryMenuItems: View {
    @Environment(AppModel.self) private var model
    let entry: Entry
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            model.toggleFavorite(entry.id)
        } label: {
            Label(
                entry.isFavorite ? "Remove Favorite" : "Favorite",
                systemImage: entry.isFavorite ? "bookmark.slash" : "bookmark"
            )
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
        Button(role: .destructive) {
            model.moveToTrash(entry.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - One row

/// A day number, the first lines of the entry, and a thumbnail of its first photo.
struct EntryRow: View {
    let entry: Entry
    var showJournal: Bool = false
    @Environment(AppModel.self) private var model

    private var title: String {
        let text = entry.summary().title
        if !text.isEmpty { return text }
        if entry.photos.count == 1 { return "Photo" }
        if entry.photos.count > 1 { return "\(entry.photos.count) photos" }
        return "New entry"
    }

    var body: some View {
        let summary = entry.summary()
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(Fmt.dayNumber(entry))
                    .font(Theme.serif(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(Fmt.weekdayShort(entry))
                    .font(Theme.serif(.caption2, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.inkTertiary)
            }
            .frame(width: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.serif(.headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !summary.preview.isEmpty {
                    Text(summary.preview)
                        .font(Theme.serif(.subheadline))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(Fmt.time(entry))
                    if let location = entry.location {
                        Text("·")
                        Image(systemName: location.isHome ? "house" : "mappin")
                            .imageScale(.small)
                        Text(location.name).lineLimit(1)
                    }
                    if showJournal {
                        Text("·")
                        JournalChip(journal: model.journal(entry.journalID))
                    }
                }
                .font(Theme.serif(.caption))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 2)
            }

            Spacer(minLength: 8)

            if let first = entry.photos.first {
                ZStack(alignment: .bottomTrailing) {
                    PhotoThumb(entryID: entry.id, photo: first, maxPixel: 240)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 0.75)
                        )
                    if entry.photos.count > 1 {
                        Text("\(entry.photos.count)")
                            .font(Theme.serif(.caption2, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                            .padding(4)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if entry.isFavorite {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                    .offset(x: 8, y: -6)
                    .accessibilityLabel("Favorite")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The journal timeline

private struct MonthSection: Identifiable {
    let id: String
    let title: String
    let entries: [Entry]
}

struct EntryListView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    let scope: EntryScope
    @Binding var selection: UUID?
    var onCompose: (NewEntryChoice) -> Void
    var onSeeOnThisDay: () -> Void
    /// Switches to another journal, or back to all entries.
    var onPickScope: (SidebarItem) -> Void = { _ in }

    @State private var query = ""

    private var title: String {
        if case .journal(let id) = scope { return model.journalName(id) }
        return "All Entries"
    }

    private func sections(for entries: [Entry], calendar: DayCalendar) -> [MonthSection] {
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        var titles: [String: String] = [:]
        for entry in entries {
            let stamp = entry.dayStamp(using: calendar)
            let key = "\(stamp.year)-\(stamp.month)"
            if buckets[key] == nil {
                order.append(key)
                titles[key] = Fmt.monthYear(entry)
            }
            buckets[key, default: []].append(entry)
        }
        return order.map { MonthSection(id: $0, title: titles[$0] ?? "", entries: buckets[$0] ?? []) }
    }

    var body: some View {
        let calendar = prefs.dayCalendar
        let entries = model.entries(in: scope, matching: query)
        let isSearching = !query.trimmingCharacters(in: .whitespaces).isEmpty

        List(selection: $selection) {
            if !isSearching {
                Section {
                    VStack(spacing: 22) {
                        if model.stillDownloading > 0 {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Some entries are still coming down from iCloud.")
                                    .font(Theme.serif(.footnote))
                                    .foregroundStyle(Theme.inkSecondary)
                                Spacer()
                            }
                        }
                        StreakCard(summary: model.streak(calendar: calendar))
                        let groups = model.onThisDay(calendar: calendar)
                        if !groups.isEmpty {
                            OnThisDayStrip(
                                groups: groups,
                                onOpen: { selection = $0 },
                                onSeeAll: onSeeOnThisDay
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(sections(for: entries, calendar: calendar)) { section in
                Section {
                    ForEach(section.entries) { entry in
                        EntryRow(entry: entry, showJournal: scope == .all && model.journals.count > 1)
                            .tag(entry.id)
                            .entryRowStyle(selected: selection == entry.id)
                            .entryActions(entry, selection: $selection)
                    }
                } header: {
                    Text(section.title)
                        .font(Theme.serif(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle(title)
        .toolbarTitleMenu {
            if model.journals.count > 1 {
                Button("All Entries") { onPickScope(.all) }
                ForEach(model.journals) { journal in
                    Button(journal.name) { onPickScope(.journal(journal.id)) }
                }
            }
        }
        .searchable(text: $query, prompt: "Search your journal")
        .refreshable { await model.refresh() }
        .composeToolbar(onCompose)
        .overlay {
            if entries.isEmpty {
                if isSearching {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No matches",
                        message: "Nothing in this journal has those words."
                    )
                } else {
                    EmptyStateView(
                        systemImage: "book.closed",
                        title: "A blank page",
                        message: "Your entries will gather here. Write a few lines tonight.",
                        actionTitle: "Write an entry",
                        action: { onCompose(.standard) }
                    )
                    .padding(.top, 220)
                }
            }
        }
    }
}

// MARK: - On this day

struct OnThisDayScreen: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    @Binding var selection: UUID?
    var onCompose: (NewEntryChoice) -> Void

    var body: some View {
        let groups = model.onThisDay(calendar: prefs.dayCalendar)

        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry, showJournal: model.journals.count > 1)
                            .tag(entry.id)
                            .entryRowStyle(selected: selection == entry.id)
                            .entryActions(entry, selection: $selection)
                    }
                } header: {
                    Text("\(group.label) · \(String(group.year))")
                        .font(Theme.serif(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("On This Day")
        .composeToolbar(onCompose)
        .overlay {
            if groups.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "Nothing from past years",
                    message: "Entries you wrote on this date in earlier years will show up here."
                )
            }
        }
    }
}
