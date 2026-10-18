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

    @State private var sidebar: SidebarItem? = .all
    @State private var selectedEntryID: UUID?
    @State private var selectedTemplateID: UUID?
    @State private var showCompose = false
    @State private var composeTemplate: EntryTemplate?
    @State private var showSettings = false
    @State private var columns = NavigationSplitViewVisibility.automatic

    private var scope: EntryScope {
        if case .journal(let id) = sidebar { return .journal(id) }
        return .all
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
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
                ToastView(toast: toast)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: model.toast)
        .sheet(isPresented: $showCompose, onDismiss: { composeTemplate = nil }) {
            ComposeSheet(
                initialJournalID: model.defaultJournalID(for: scope),
                initialTemplate: composeTemplate,
                onCreate: createEntry
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: Columns

    @ViewBuilder
    private var contentColumn: some View {
        switch sidebar ?? .all {
        case .all, .journal:
            EntryListView(
                scope: scope,
                selection: $selectedEntryID,
                onCompose: { showCompose = true },
                onSeeOnThisDay: { sidebar = .onThisDay }
            )
        case .onThisDay:
            OnThisDayScreen(selection: $selectedEntryID, onCompose: { showCompose = true })
        case .calendar:
            CalendarScreen(selection: $selectedEntryID, onCompose: { showCompose = true })
        case .templates:
            TemplatesScreen(selection: $selectedTemplateID, onStart: startWith)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if sidebar == .templates {
            if let templateID = selectedTemplateID {
                TemplateEditorView(
                    templateID: templateID,
                    onStart: startWith,
                    onDeleted: { selectedTemplateID = nil }
                )
            } else {
                TemplatePlaceholder()
            }
        } else if let entryID = selectedEntryID {
            EntryDetailView(
                entryID: entryID,
                onCompose: { showCompose = true },
                onClose: { selectedEntryID = nil }
            )
        } else {
            DetailPlaceholder(onCompose: { showCompose = true })
        }
    }

    // MARK: Actions

    private func startWith(_ template: EntryTemplate) {
        composeTemplate = template
        showCompose = true
    }

    private func createEntry(journalID: UUID, templateID: UUID?, body: String) {
        // The editor opens in the detail column, so leave the Templates screen first.
        if sidebar == .templates { sidebar = .all }
        let id = model.beginNewEntry(journalID: journalID, templateID: templateID, body: body)
        selectedEntryID = id
        showCompose = false
    }
}
