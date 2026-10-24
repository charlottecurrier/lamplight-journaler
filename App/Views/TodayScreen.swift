import SwiftUI

/// The home page: tonight at a glance. A way to start writing, what you wrote today,
/// and what you wrote on this date in earlier years.
struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    @Binding var selection: UUID?
    var onCompose: (NewEntryChoice) -> Void
    var onSeeOnThisDay: () -> Void

    private var dateTitle: String {
        Date().formatted(Date.FormatStyle(calendar: .journal).weekday(.wide).month(.wide).day())
    }

    var body: some View {
        let calendar = prefs.dayCalendar
        let today = model.today(calendar)
        let entries = model.entries(in: .all)
            .filter { $0.dayStamp(using: calendar) == today }
            .sorted { $0.createdAt < $1.createdAt }
        let groups = model.onThisDay(calendar: calendar)

        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    StreakCard(summary: model.streak(calendar: calendar))
                    startWriting
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry, showJournal: model.journals.count > 1)
                            .tag(entry.id)
                            .entryRowStyle(selected: selection == entry.id)
                            .entryActions(entry, selection: $selection)
                    }
                } header: {
                    Text("Written today")
                        .font(Theme.serif(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .textCase(nil)
                }
            }

            if !groups.isEmpty {
                Section {
                    OnThisDayStrip(groups: groups, onOpen: { selection = $0 }, onSeeAll: onSeeOnThisDay)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .composeToolbar(onCompose)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateTitle)
                .font(Theme.serif(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            MoonLabel(date: Date())
                .font(Theme.serif(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// A New Entry button, and your templates to begin with one of them.
    private var startWriting: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Start writing")
            Button {
                onCompose(.standard)
            } label: {
                Label("New Entry", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryPaper)

            let templates = model.templatesByUse()
            if !templates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(templates.prefix(8)) { template in
                            Button {
                                onCompose(.template(template))
                            } label: {
                                Label(template.name, systemImage: "doc.text")
                                    .font(Theme.serif(.subheadline, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(Theme.surface))
                                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
