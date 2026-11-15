import SwiftUI

/// A quiet message for when there is nothing to show yet: a small ornament, a line or two, and at most a text button.
/// The loud button for a new entry is already on the screen, in the bar, so this one doesn't compete with it.
struct EmptyStateView: View {
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            PaperOrnament()
                .padding(.bottom, 8)
            Text(title)
                .font(Theme.serif(.title3))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(Theme.serif(.subheadline))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.quietPaper)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A printer's ornament: a small diamond between two hairlines. It marks a page with nothing on it yet.
struct PaperOrnament: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.line).frame(width: 34, height: 1)
            Rectangle().fill(Theme.inkTertiary).frame(width: 5, height: 5).rotationEffect(.degrees(45))
            Rectangle().fill(Theme.line).frame(width: 34, height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// The window from the app's icon. It starts dark, a light comes on inside, and the light breathes like a flame.
/// With Reduce Motion on, it is simply lit.
struct LampWindow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var width: CGFloat = 76

    @State private var lit = false
    @State private var bright = false

    private var height: CGFloat { width * 1.45 }
    private var glow: Double { lit ? (bright ? 1 : 0.8) : 0 }

    var body: some View {
        ZStack {
            WindowArch().fill(Theme.surface)
            WindowArch()
                .fill(RadialGradient(
                    colors: [Theme.lampCore, Theme.lampEdge],
                    center: UnitPoint(x: 0.5, y: 0.64),
                    startRadius: 0,
                    endRadius: width * 0.95
                ))
                .opacity(glow)
            // The bars of the window.
            Rectangle().fill(Theme.page).frame(width: 2.5)
            Rectangle().fill(Theme.page).frame(height: 2.5).offset(y: height * 0.08)
            WindowArch().stroke(Theme.line, lineWidth: 1)
        }
        .frame(width: width, height: height)
        .background {
            // The light it throws on the wall around it.
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.lampEdge.opacity(0.30), Theme.lampEdge.opacity(0)],
                    center: .center,
                    startRadius: width * 0.2,
                    endRadius: width * 1.7
                ))
                .frame(width: width * 3.4, height: width * 3.4)
                .opacity(glow)
        }
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else {
                lit = true
                bright = true
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.9)) { lit = true }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}

/// A window with a round top.
private struct WindowArch: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
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
                        .font(.system(size: 13, weight: Theme.iconWeight))
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
