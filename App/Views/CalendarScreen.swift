import SwiftUI

/// A month of days. Each day has its moon under it, bright on days something was written. Tap a day to see it.
struct MonthGrid: View {
    let month: Date
    let marked: Set<DayStamp>
    let today: DayStamp
    @Binding var selected: DayStamp?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var calendar: Calendar { Calendar.journal }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...]) + Array(symbols[..<start])
    }

    /// nil entries are the blank cells before the 1st.
    private var cells: [DayStamp?] {
        let parts = calendar.dateComponents([.year, .month], from: month)
        guard let year = parts.year, let monthNumber = parts.month,
              let first = calendar.date(from: parts),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        var result: [DayStamp?] = Array(repeating: nil, count: blanks)
        for day in range {
            result.append(DayStamp(year: year, month: monthNumber, day: day))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Theme.serif(.caption, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let day = cell {
                        DayCell(
                            day: day,
                            isMarked: marked.contains(day),
                            isToday: day == today,
                            isSelected: day == selected
                        ) {
                            selected = day
                        }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: DayStamp
    let isMarked: Bool
    let isToday: Bool
    let isSelected: Bool
    let action: () -> Void

    /// The moon that evening.
    private var phase: MoonPhase {
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = 21
        return MoonPhase(on: Calendar.journal.date(from: parts) ?? Date())
    }

    private var moonLit: Color {
        if isSelected { return isMarked ? Theme.onAccent : Theme.onAccent.opacity(0.5) }
        return isMarked ? Theme.sage : Theme.inkTertiary.opacity(0.6)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(Theme.serif(.body, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                MoonGlyph(
                    phase: phase,
                    lit: moonLit,
                    shade: isSelected ? Theme.onAccent.opacity(0.18) : Theme.line.opacity(isMarked ? 0.9 : 0.5),
                    outline: isMarked ? moonLit : Color.clear
                )
                .frame(width: 11, height: 11)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.accent : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Theme.accent : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.day)\(isToday ? ", today" : "")\(isMarked ? ", has an entry" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    @Binding var selection: UUID?
    var onCompose: (NewEntryChoice) -> Void

    @State private var month = Date()
    @State private var selectedDay: DayStamp?

    private func shiftMonth(_ delta: Int) {
        if let moved = Calendar.journal.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeInOut(duration: 0.2)) { month = moved }
        }
    }

    private func dayTitle(_ day: DayStamp) -> String {
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        guard let date = Calendar.journal.date(from: parts) else { return "" }
        return date.formatted(Date.FormatStyle(calendar: .journal).weekday(.wide).month(.wide).day())
    }

    var body: some View {
        let calendar = prefs.dayCalendar
        let today = model.today(calendar)
        let written = model.entries(in: .all)
        let byDay = Dictionary(grouping: written, by: { $0.dayStamp(using: calendar) })
        let shown = selectedDay ?? today

        List(selection: $selection) {
            Section {
                VStack(spacing: 20) {
                    StreakCard(summary: model.streak(calendar: calendar))

                    VStack(spacing: 12) {
                        HStack {
                            Button { shiftMonth(-1) } label: { PaperIcon("chevron.left", size: .small) }
                                .accessibilityLabel("Previous month")
                            Spacer()
                            Text(Fmt.monthYear(month))
                                .font(Theme.serif(.title3, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button { shiftMonth(1) } label: { PaperIcon("chevron.right", size: .small) }
                                .accessibilityLabel("Next month")
                        }
                        .buttonStyle(.borderless)
                        .tint(Theme.accent)

                        MonthGrid(
                            month: month,
                            marked: Set(byDay.keys),
                            today: today,
                            selected: Binding(get: { shown }, set: { selectedDay = $0 })
                        )

                        Button("Today") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                month = Date()
                                selectedDay = today
                            }
                        }
                        .buttonStyle(.quietPaper)
                    }
                    .padding(16)
                    .paperCard()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                let dayEntries = (byDay[shown] ?? []).sorted { $0.createdAt < $1.createdAt }
                if dayEntries.isEmpty {
                    Text("Nothing written this day.")
                        .font(Theme.serif(.callout))
                        .foregroundStyle(Theme.inkTertiary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(dayEntries) { entry in
                        EntryRow(entry: entry, showJournal: model.journals.count > 1)
                            .tag(entry.id)
                            .entryRowStyle(selected: selection == entry.id)
                            .entryActions(entry, selection: $selection)
                    }
                }
            } header: {
                Text(dayTitle(shown))
                    .font(Theme.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Calendar")
        .composeToolbar(onCompose)
    }
}
