import SwiftUI

enum SidebarItem: Hashable {
    case all
    case onThisDay
    case calendar
    case templates
    case journal(UUID)
}

/// The sidebar: where to look. On a phone it is the first screen, on an iPad it sits at the left.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    @Binding var selection: SidebarItem?
    var onSettings: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Entries", systemImage: "book.closed")
                    .tag(SidebarItem.all)
                Label("On This Day", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.onThisDay)
                Label("Calendar", systemImage: "calendar")
                    .tag(SidebarItem.calendar)
            }

            if model.journals.count > 1 {
                Section {
                    ForEach(model.journals) { journal in
                        HStack(spacing: 10) {
                            JournalDot(colorKey: journal.colorKey, size: 10)
                            Text(journal.name)
                        }
                        .tag(SidebarItem.journal(journal.id))
                    }
                } header: {
                    Text("Journals")
                        .font(Theme.serif(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Section {
                Label("Templates", systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.templates)
            }
        }
        .font(Theme.serif(.body))
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Lamplight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SidebarStreak(summary: model.streak(calendar: prefs.dayCalendar))
        }
    }
}

/// A one-line streak at the bottom of the sidebar.
private struct SidebarStreak: View {
    let summary: StreakSummary

    var body: some View {
        HStack(spacing: 10) {
            WeekDotsCompact(days: summary.lastSevenDays)
            Text(summary.current == 1 ? "1 day in a row" : "\(summary.current) days in a row")
                .font(Theme.serif(.footnote))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WeekDotsCompact: View {
    let days: [Bool]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(days.count, 7), id: \.self) { index in
                Circle()
                    .fill(days[index] ? Theme.sage : Color.clear)
                    .overlay(Circle().strokeBorder(days[index] ? Theme.sage : Theme.inkTertiary, lineWidth: 1))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Sidebar, list and reading column. An iPad shows all three side by side; a phone shows one at a time.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockManager.self) private var lock
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var sidebar: SidebarItem? = .all
    @State private var selectedEntryID: UUID?
    @State private var selectedTemplateID: UUID?
    @State private var showSettings = false
    @State private var columns = NavigationSplitViewVisibility.automatic
    /// On a phone, which screen is in front. It starts on the list, not on the list of sections.
    @State private var compactColumn = NavigationSplitViewColumn.content

    private var scope: EntryScope {
        if case .journal(let id) = sidebar { return .journal(id) }
        return .all
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            SidebarView(selection: $sidebar) { showSettings = true }
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 320)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 500)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast, onOpen: openLookBack, onDismiss: { model.toast = nil })
                    .padding(.bottom, sizeClass == .compact ? 70 : 0)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: model.toast)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // Once the journal is unlocked, open to a new entry if nothing is written yet today.
        .task(id: lock.isLocked) { openToNewEntryOnLaunch() }
    }

    // MARK: Columns

    private var contentColumn: some View {
        screen
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if sizeClass == .compact {
                    CompactBar(selection: $sidebar) { create(.standard) }
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
    }

    @ViewBuilder
    private var screen: some View {
        switch sidebar ?? .all {
        case .all, .journal:
            EntryListView(
                scope: scope,
                selection: $selectedEntryID,
                onCompose: create,
                onSeeOnThisDay: { sidebar = .onThisDay },
                onPickScope: { sidebar = $0 }
            )
        case .onThisDay:
            OnThisDayScreen(selection: $selectedEntryID, onCompose: create)
        case .calendar:
            CalendarScreen(selection: $selectedEntryID, onCompose: create)
        case .templates:
            TemplatesScreen(selection: $selectedTemplateID) { create(.template($0)) }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if sidebar == .templates {
            if let templateID = selectedTemplateID {
                TemplateEditorView(
                    templateID: templateID,
                    onStart: { create(.template($0)) },
                    onDeleted: { selectedTemplateID = nil }
                )
            } else {
                TemplatePlaceholder()
            }
        } else if let entryID = selectedEntryID {
            EntryDetailView(
                entryID: entryID,
                olderEntry: { neighbor(of: $0, step: 1) },
                newerEntry: { neighbor(of: $0, step: -1) },
                onTurn: { selectedEntryID = $0 },
                onCompose: create,
                onClose: {
                    selectedEntryID = nil
                    compactColumn = .content
                }
            )
        } else {
            DetailPlaceholder(onCompose: create)
        }
    }

    // MARK: Actions

    /// Starts an entry and opens the editor for it. A template's page becomes the entry's text.
    private func create(_ choice: NewEntryChoice) {
        let journalID: UUID
        var template: EntryTemplate?
        switch choice {
        case .standard:
            journalID = model.defaultJournalID(for: scope)
            template = model.defaultTemplate(for: journalID)
        case .blank:
            journalID = model.defaultJournalID(for: scope)
        case .template(let chosen):
            template = chosen
            // A template can name the journal it belongs in.
            if let named = chosen.defaultJournalID, model.journal(named) != nil {
                journalID = named
            } else {
                journalID = model.defaultJournalID(for: scope)
            }
        }
        // The editor opens in the detail column, so leave the Templates screen first.
        if sidebar == .templates { sidebar = .all }
        if let template { model.recordTemplateUse(template.id) }
        selectedEntryID = model.beginNewEntry(journalID: journalID, templateID: template?.id, body: template?.body ?? "")
        compactColumn = .detail
    }

    /// The entry before or after this one in the list being read. A step of 1 is older, -1 is newer.
    private func neighbor(of id: UUID, step: Int) -> UUID? {
        let list = model.entries(in: scope)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let target = index + step
        return list.indices.contains(target) ? list[target].id : nil
    }

    /// Opens the entry from an earlier year that was shown after saving.
    private func openLookBack(_ id: UUID) {
        model.toast = nil
        sidebar = .all
        selectedEntryID = id
        compactColumn = .detail
    }

    /// Opening the app begins tonight's entry, if the person turned that on and hasn't written yet today.
    /// Nothing is saved until they type, so backing out leaves no trace.
    private func openToNewEntryOnLaunch() {
        guard !lock.isLocked, !model.didOpenToNewEntry else { return }
        model.didOpenToNewEntry = true
        guard prefs.openToNewEntry, model.editingEntryID == nil, model.stillDownloading == 0 else { return }
        guard !model.streak(calendar: prefs.dayCalendar).wroteToday else { return }
        sidebar = .all
        create(.standard)
    }
}

/// The phone's bottom bar: where to look, and a button to begin writing.
private struct CompactBar: View {
    @Binding var selection: SidebarItem?
    var onNewEntry: () -> Void

    private func isSelected(_ item: SidebarItem) -> Bool {
        let current = selection ?? .all
        if item == .all, case .journal = current { return true }
        return current == item
    }

    private func tab(_ title: String, _ symbol: String, _ item: SidebarItem) -> some View {
        let selected = isSelected(item)
        return Button {
            selection = item
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                Text(title)
                    .font(Theme.serif(.caption2, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.accent : Theme.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var body: some View {
        HStack(spacing: 0) {
            tab("Journal", "book.closed", .all)
            tab("On This Day", "clock.arrow.circlepath", .onThisDay)
            Button(action: onNewEntry) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("New Entry")
            tab("Calendar", "calendar", .calendar)
            tab("Templates", "list.bullet.rectangle", .templates)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }
}
