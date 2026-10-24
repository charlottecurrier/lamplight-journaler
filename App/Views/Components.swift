import SwiftUI

/// A quiet message for when there is nothing to show yet.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.serif(.title3, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.serif(.callout))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primaryPaper)
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small caps label above a block of content.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .serif, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.inkTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct JournalDot: View {
    let colorKey: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.journalColor(colorKey))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A journal's name with its color dot. The name always appears, since color alone is easy to miss.
struct JournalChip: View {
    let journal: Journal?

    var body: some View {
        HStack(spacing: 6) {
            JournalDot(colorKey: journal?.colorKey ?? "ember")
            Text(journal?.name ?? "Journal")
                .font(Theme.serif(.footnote, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// The short message shown after saving. Fades in and out near the bottom of the screen.
/// When there is an entry from this date in an earlier year, it shows a few lines of it too.
struct ToastView: View {
    let toast: Toast
    var onOpen: (UUID) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    var body: some View {
        Group {
            if let lookBack = toast.lookBack {
                card(lookBack)
            } else {
                Text(toast.text)
                    .font(Theme.serif(.callout, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .paperCard(radius: 22, raised: true)
            }
        }
        .padding(.bottom, 28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func card(_ lookBack: LookBack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(toast.text)
                    .font(Theme.serif(.callout, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Rectangle().fill(Theme.line).frame(height: 0.5)
            Button {
                onOpen(lookBack.entryID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("\(lookBack.label) today")
                    Text(lookBack.title)
                        .font(Theme.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if !lookBack.preview.isEmpty {
                        Text(lookBack.preview)
                            .font(Theme.serif(.subheadline))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens that entry")
        }
        .padding(18)
        .frame(maxWidth: 460)
        .paperCard(radius: 22, raised: true)
        .padding(.horizontal, 20)
    }
}

/// Small helper so a Done/Cancel toolbar reads the same everywhere.
struct ToolbarTextButton: View {
    let title: String
    var weight: Font.Weight = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.serif(.body, weight: weight))
        }
    }
}
