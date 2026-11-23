import SwiftUI

enum SidebarItem: Hashable {
    case today
    case all
    case onThisDay
    case favorites
    case calendar
    case templates
    case journal(UUID)
}

extension Notification.Name {
    /// Posted to start a new entry, as if New Entry had been tapped. Command-N posts it.
    static let lamplightNewEntry = Notification.Name("lamplight.newEntry")
    /// Posted to go to a section. The object is the `SidebarItem`.
    static let lamplightGo = Notification.Name("lamplight.go")
    /// Posted to open Settings.
    static let lamplightShowSettings = Notification.Name("lamplight.showSettings")
    /// Posted to turn to the next entry in the list being read. The object is 1 for older, -1 for newer.
    static let lamplightTurnPage = Notification.Name("lamplight.turnPage")
}

/// The sidebar: where to look. On a phone it is the first screen, on an iPad it sits at the left.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    @Binding var selection: SidebarItem?
    /// Called on every tap on a row, including the row that is already highlighted, which `selection` doesn't report.
    var onChoose: (SidebarItem) -> Void
    var onSettings: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Entries", systemImage: "book.closed")
                    .sidebarRow(.all, onChoose: onChoose)
                Label("Today", systemImage: "sun.horizon")
                    .sidebarRow(.today, onChoose: onChoose)
                Label("On This Day", systemImage: "clock.arrow.circlepath")
                    .sidebarRow(.onThisDay, onChoose: onChoose)
                Label("Favorites", systemImage: "bookmark")
                    .sidebarRow(.favorites, onChoose: onChoose)
                Label("Calendar", systemImage: "calendar")
                    .sidebarRow(.calendar, onChoose: onChoose)
            }

            if model.journals.count > 1 {
                Section {
                    ForEach(model.journals) { journal in
                        HStack(spacing: 10) {
                            JournalDot(colorKey: journal.colorKey, size: 10)
                            Text(journal.name)
                        }
                        .sidebarRow(.journal(journal.id), onChoose: onChoose)
                    }
                } header: {
                    Text("Journals")
                        .font(Theme.serif(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Section {
                Label("Templates", systemImage: "doc.text")
                    .sidebarRow(.templates, onChoose: onChoose)
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
                    PaperIcon("gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .safeAreaInset(edge: .bottom) {
            SidebarStreak(summary: model.streak(calendar: prefs.dayCalendar))
        }
    }
}

private extension View {
    /// A row of the sidebar. The tap gesture runs beside the list's own selection.
    func sidebarRow(_ item: SidebarItem, onChoose: @escaping (SidebarItem) -> Void) -> some View {
        simultaneousGesture(TapGesture().onEnded { onChoose(item) })
            .tag(item)
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
    /// What the columns were before a new entry took the whole screen, so they go back the way they were.
    @State private var columnsBeforeWriting = NavigationSplitViewVisibility.automatic
    /// On a phone, which screen is in front. It starts on the list, not on the list of sections.
    @State private var compactColumn = NavigationSplitViewColumn.content
    /// True while a new entry has the whole screen on an iPad, so the sidebar and list can come back after.
    @State private var writingFullWidth = false
    /// On a phone, the entry whose page is on its way to the front. See `open`.
    @State private var pageOnItsWay: UUID?

    private var scope: EntryScope {
        if case .journal(let id) = sidebar { return .journal(id) }
        return .all
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            SidebarView(selection: sidebarSelection, onChoose: show) { showSettings = true }
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
                    .padding(.bottom, sizeClass == .compact && compactColumn == .content ? 70 : 0)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: model.toast)
        // When the entry is finished, the columns come back the way they were.
        .onChange(of: model.editingEntryID) {
            if model.editingEntryID == nil, writingFullWidth {
                writingFullWidth = false
                withAnimation(.easeInOut(duration: 0.3)) { columns = columnsBeforeWriting }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // The keyboard shortcuts (`LamplightCommands`) arrive as notifications. None does anything while the
        // journal is locked or Settings is over it. The tests post the first one too: it is the same as tapping
        // New Entry, and a SwiftUI button can't be tapped from a unit test.
        .onReceive(NotificationCenter.default.publisher(for: .lamplightNewEntry)) { _ in
            if shortcutsAllowed { create(.standard) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lamplightGo)) { note in
            if shortcutsAllowed, let item = note.object as? SidebarItem { show(item) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lamplightShowSettings)) { _ in
            if !lock.isLocked { showSettings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lamplightTurnPage)) { note in
            if shortcutsAllowed, let step = note.object as? Int { turnPage(step) }
        }
        #if DEBUG
        // These two write the tests' step log, and are left out of a release build.
        .onChange(of: selectedEntryID) { old, new in
            NavTrace.note("selection \(NavTrace.short(old)) -> \(NavTrace.short(new))")
        }
        .onChange(of: compactColumn) { old, new in
            NavTrace.note("phone column \(old == .detail ? "page" : "list") -> \(new == .detail ? "page" : "list")")
        }
        #endif
        // Once the journal is unlocked, open to a new entry if nothing is written yet today.
        .task(id: lock.isLocked) { openToNewEntryOnLaunch() }
    }

    // MARK: Columns

    private var contentColumn: some View {
        screen
            .toolbar {
                // On the far side from Back. Beside it, the two read as one control.
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            PaperIcon("gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if sizeClass == .compact {
                    CompactBar(selection: sidebarSelection) { create(.standard) }
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
    }

    @ViewBuilder
    private var screen: some View {
        switch sidebar ?? .all {
        case .today:
            TodayScreen(
                selection: $selectedEntryID,
                onCompose: create,
                onSeeOnThisDay: { sidebar = .onThisDay }
            )
        case .favorites:
            FavoritesScreen(selection: $selectedEntryID, onCompose: create)
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
                TemplatePlaceholder(selection: $selectedTemplateID, onNew: newTemplate)
            }
        } else if let entryID = selectedEntryID {
            EntryDetailView(
                entryID: entryID,
                olderEntry: { neighbor(of: $0, step: 1) },
                newerEntry: { neighbor(of: $0, step: -1) },
                onTurn: { selectedEntryID = $0 },
                onCompose: create,
                onClose: {
                    NavTrace.note("close asked, selected \(NavTrace.short(selectedEntryID)), page of \(NavTrace.short(entryID))")
                    selectedEntryID = nil
                    compactColumn = .content
                }
            )
        } else if pageOnItsWay != nil {
            // The page is in front and its entry is chosen next turn. Bare paper until then, not "Choose an entry".
            Color.clear.background(PaperBackground())
        } else {
            DetailPlaceholder(onCompose: create)
        }
    }

    // MARK: Actions

    /// Picking a section from the sidebar or the phone's bar goes through `show`.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { sidebar },
            set: { item in
                if let item { show(item) } else { sidebar = nil }
            }
        )
    }

    /// Goes to a section and makes sure its list can be seen. On a phone the list comes to the front. On an iPad the
    /// sidebar steps aside, so the list and the page have the room, and the list returns if a new entry had the
    /// whole screen. Templates is the same: the sidebar closes and the list of templates is what's showing.
    private func show(_ item: SidebarItem) {
        sidebar = item
        forgetPageOnItsWay()
        compactColumn = .content
        writingFullWidth = false
        withAnimation(.easeInOut(duration: 0.3)) { columns = .doubleColumn }
    }

    /// False while the journal is locked or Settings covers it, when a shortcut shouldn't change what is behind.
    private var shortcutsAllowed: Bool { !lock.isLocked && !showSettings }

    /// Turns to the entry before or after the one being read. Does nothing while a page is being written, where
    /// the keys belong to the text, or at the end of the list.
    private func turnPage(_ step: Int) {
        guard model.editingEntryID == nil, sidebar != .templates,
              let current = selectedEntryID, let next = neighbor(of: current, step: step) else { return }
        selectedEntryID = next
    }

    private func newTemplate() {
        let template = model.newTemplate()
        model.save(template: template)
        selectedTemplateID = template.id
    }

    /// Starts an entry and opens the editor for it. A template's page becomes the entry's text.
    private func create(_ choice: NewEntryChoice) {
        begin(choice, keyboard: true)
    }

    /// Does the work of `create`. `keyboard` is false when the app opens to a new entry by itself, so the page
    /// waits for a tap. It is a separate function so `create` can be handed to screens as a plain action.
    private func begin(_ choice: NewEntryChoice, keyboard: Bool) {
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
        forgetPageOnItsWay()
        let id = model.beginNewEntry(journalID: journalID, templateID: template?.id, body: template?.body ?? "")
        NavTrace.note("begin \(NavTrace.short(id)), selected \(NavTrace.short(selectedEntryID))")
        if !keyboard { model.quietStartID = id }
        open(id)
        // On an iPad a new entry gets the whole screen: just the page, with nothing else beside it.
        if sizeClass != .compact {
            writingFullWidth = true
            if columns != .detailOnly { columnsBeforeWriting = columns }
            withAnimation(.easeInOut(duration: 0.3)) { columns = .detailOnly }
        }
    }

    /// The entry before or after this one in the list being read. A step of 1 is older, -1 is newer.
    private func neighbor(of id: UUID, step: Int) -> UUID? {
        // Turn through the list on screen, newest first. On This Day, Calendar and Templates are left out.
        let list: [Entry]
        switch sidebar ?? .all {
        case .all, .journal:
            list = model.entries(in: scope)
        case .favorites:
            list = model.favorites
        case .today:
            let calendar = prefs.dayCalendar
            let today = model.today(calendar)
            list = model.entries(in: .all).filter { $0.dayStamp(using: calendar) == today }
        case .onThisDay, .calendar, .templates:
            return nil
        }
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let target = index + step
        return list.indices.contains(target) ? list[target].id : nil
    }

    /// Brings an entry's page to the front.
    ///
    /// On a phone the page comes forward first and the entry is chosen a moment after. Doing both at once worked
    /// for the first new entry after the app started and for none after it: the editor was built, taken away at
    /// once, and the unwritten entry was dropped with it, so the page closed. `NewEntryNavigationTests` covers it.
    /// An iPad shows the page beside the list and never had the trouble, so there both still happen together.
    private func open(_ id: UUID) {
        guard sizeClass == .compact else {
            selectedEntryID = id
            compactColumn = .detail
            return
        }
        compactColumn = .detail
        pageOnItsWay = id
        Task { @MainActor in
            // A later choice, or going somewhere else in the meantime, takes its place.
            guard pageOnItsWay == id else { return }
            pageOnItsWay = nil
            selectedEntryID = id
        }
    }

    /// Gives up on a page that hasn't opened yet, because the person has gone somewhere else in the meantime. If it
    /// was for a new entry, that entry has no editor to finish it, and nothing could have been typed in it, so it
    /// is finished here, which drops it.
    private func forgetPageOnItsWay() {
        guard let waiting = pageOnItsWay else { return }
        pageOnItsWay = nil
        if waiting == model.editingEntryID {
            model.finishEditing(waiting, announce: false, calendar: prefs.dayCalendar)
        }
    }

    /// Opens the entry from an earlier year that was shown after saving.
    private func openLookBack(_ id: UUID) {
        model.toast = nil
        forgetPageOnItsWay()
        sidebar = .all
        open(id)
    }

    /// Opening the app begins tonight's entry, if the person turned that on and hasn't written yet today.
    /// Nothing is saved until they type, so backing out leaves no trace.
    private func openToNewEntryOnLaunch() {
        guard !lock.isLocked, !model.didOpenToNewEntry else { return }
        model.didOpenToNewEntry = true
        guard prefs.openToNewEntry, model.editingEntryID == nil, model.stillDownloading == 0 else { return }
        guard !model.streak(calendar: prefs.dayCalendar).wroteToday else { return }
        sidebar = .all
        // The page opens quietly: the keyboard waits until the person taps it.
        begin(.standard, keyboard: false)
    }
}

/// The phone's bottom bar: where to look, and a button to begin writing.
/// Today, Journal and Calendar are tabs. On This Day, Favorites and Templates are under More.
private struct CompactBar: View {
    @Binding var selection: SidebarItem?
    var onNewEntry: () -> Void

    private var current: SidebarItem { selection ?? .all }

    private func isSelected(_ item: SidebarItem) -> Bool {
        if item == .all, case .journal = current { return true }
        return current == item
    }

    private var moreIsSelected: Bool {
        current == .onThisDay || current == .favorites || current == .templates
    }

    private func label(_ title: String, _ symbol: String, selected: Bool) -> some View {
        VStack(spacing: 3) {
            PaperIcon(symbol, size: .large)
            Text(title)
                .font(Theme.serif(.caption2, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(selected ? Theme.accent : Theme.inkTertiary)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }

    private func tab(_ title: String, _ symbol: String, _ item: SidebarItem) -> some View {
        let selected = isSelected(item)
        return Button {
            selection = item
        } label: {
            label(title, symbol, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var more: some View {
        Menu {
            Button {
                selection = .onThisDay
            } label: {
                Label("On This Day", systemImage: "clock.arrow.circlepath")
            }
            Button {
                selection = .favorites
            } label: {
                Label("Favorites", systemImage: "bookmark")
            }
            Button {
                selection = .templates
            } label: {
                Label("Templates", systemImage: "doc.text")
            }
        } label: {
            label("More", "ellipsis", selected: moreIsSelected)
        }
        .accessibilityLabel("More")
        .accessibilityAddTraits(moreIsSelected ? .isSelected : [])
    }

    var body: some View {
        HStack(spacing: 0) {
            tab("Journal", "book.closed", .all)
            tab("Today", "sun.horizon", .today)
            Button(action: onNewEntry) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("New Entry")
            tab("Calendar", "calendar", .calendar)
            more
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }
}
