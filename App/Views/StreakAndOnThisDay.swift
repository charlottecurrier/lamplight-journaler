import SwiftUI

// MARK: - Streak

/// The streak at a glance: the count, the last seven days, and one gentle line.
struct StreakCard: View {
    let summary: StreakSummary

    private var message: String {
        if summary.wroteToday { return "You've written today." }
        if summary.needsTodayToContinue { return "Write tonight to keep it going." }
        if summary.totalEntries == 0 { return "Your first entry starts the count." }
        return "Begin again tonight."
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(summary.current)")
                    .font(Theme.serif(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(summary.current == 1 ? "day in a row" : "days in a row")
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 10) {
                WeekDots(days: summary.lastSevenDays)
                Text(message)
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.trailing)
                if summary.totalDays > 0 {
                    Text("Longest \(summary.longest) · \(summary.totalDays) days written")
                        .font(Theme.serif(.caption))
                        .foregroundStyle(Theme.inkTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(18)
        .paperCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(summary.current) \(summary.current == 1 ? "day" : "days") in a row. \(message) "
                + "Longest streak \(summary.longest). \(summary.totalDays) days written."
        )
    }
}

/// Seven dots for the last seven days. Filled means written. The last one is today.
/// Filled and empty differ in brightness, not just color.
struct WeekDots: View {
    let days: [Bool]

    private var initials: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let todayIndex = Calendar.current.component(.weekday, from: Date()) - 1
        return (0..<7).map { position in
            let offset = 6 - position
            return symbols[((todayIndex - offset) % 7 + 7) % 7]
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<min(days.count, 7), id: \.self) { index in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(days[index] ? Theme.sage : Color.clear)
                        Circle()
                            .strokeBorder(days[index] ? Theme.sage : Theme.inkTertiary, lineWidth: index == 6 ? 2 : 1)
                    }
                    .frame(width: 14, height: 14)
                    Text(initials[index])
                        .font(Theme.serif(.caption2))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - On this day

/// One earlier-year entry, shown as a card with its first photo like a print.
struct OnThisDayCard: View {
    let entry: Entry
    let yearsAgo: Int
    let year: Int

    private var tilt: Double {
        // Stable per entry. Hash values change on each launch, a UUID's bytes don't.
        Double(Int(entry.id.uuid.0) % 3 - 1) * 1.4
    }

    var body: some View {
        let summary = entry.summary(maxPreview: 110)
        let ago = yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago"
        VStack(alignment: .leading, spacing: 10) {
            if let photo = entry.photos.first {
                PhotoThumb(entryID: entry.id, photo: photo, maxPixel: 640)
                    .frame(height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(5)
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .rotationEffect(.degrees(tilt))
                    .padding(.vertical, 4)
            }
            SectionLabel("\(ago) · \(String(year))")
            Text(summary.title.isEmpty ? "Photo" : summary.title)
                .font(Theme.serif(.headline, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !summary.preview.isEmpty {
                Text(summary.preview)
                    .font(Theme.serif(.subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .topLeading)
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}

/// The row of "On this day" cards at the top of the journal.
struct OnThisDayStrip: View {
    let groups: [OnThisDayGroup]
    var onOpen: (UUID) -> Void
    var onSeeAll: () -> Void

    private struct Card: Identifiable {
        let entry: Entry
        let yearsAgo: Int
        let year: Int
        var id: UUID { entry.id }
    }

    private var cards: [Card] {
        var result: [Card] = []
        for group in groups {
            for entry in group.entries {
                result.append(Card(entry: entry, yearsAgo: group.yearsAgo, year: group.year))
            }
        }
        return Array(result.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("On this day")
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(Theme.serif(.footnote, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cards) { card in
                        Button {
                            onOpen(card.entry.id)
                        } label: {
                            OnThisDayCard(entry: card.entry, yearsAgo: card.yearsAgo, year: card.year)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
    }
}
