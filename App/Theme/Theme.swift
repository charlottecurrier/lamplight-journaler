import SwiftUI
import UIKit

enum Theme {
    /// The width text is kept to on large screens. About 65 characters, easy on the eyes.
    static let readingWidth: CGFloat = 680

    // Colors
    static var page: Color { Palette.page.color }
    static var surface: Color { Palette.surface.color }
    static var raised: Color { Palette.surfaceRaised.color }
    static var line: Color { Palette.line.color }
    static var ink: Color { Palette.ink.color }
    static var inkSecondary: Color { Palette.inkSecondary.color }
    static var inkTertiary: Color { Palette.inkTertiary.color }
    static var accent: Color { Palette.accent.color }
    static var onAccent: Color { Palette.onAccent.color }
    /// The accent as it is on the light page, dark enough for white text in both looks. Swipe buttons use it.
    static var accentDeep: Color { Color(uiColor: UIColor(hex: Palette.accent.light)) }
    static var sage: Color { Palette.sage.color }
    static var danger: Color { Palette.danger.color }

    /// Journal colors are a hint only. The journal's name is always shown next to it.
    static func journalColor(_ key: String) -> Color {
        switch key {
        case "sage": return Palette.journalSage.color
        case "gold": return Palette.journalGold.color
        case "clay": return Palette.journalClay.color
        case "moss": return Palette.journalMoss.color
        case "stone": return Palette.journalStone.color
        default: return Palette.accent.color
        }
    }

    // Type. All system fonts, so Dynamic Type works everywhere.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Paper

/// Which texture is laid over the page, and how strong it is. Set once at the root and read by every page and card.
struct PaperTextureChoice: Equatable {
    var texture: PaperTexture = .cotton
    var strength: Double = 1
}

private struct PaperTextureKey: EnvironmentKey {
    static let defaultValue = PaperTextureChoice()
}

extension EnvironmentValues {
    var paperTexture: PaperTextureChoice {
        get { self[PaperTextureKey.self] }
        set { self[PaperTextureKey.self] = newValue }
    }
}

/// A texture tiled over whatever is behind it. Above a strength of 1 a second layer is added.
struct PaperGrain: View {
    @Environment(\.colorScheme) private var scheme
    var texture: PaperTexture
    var strength: Double

    var body: some View {
        if let name = texture.imageName(dark: scheme == .dark), strength > 0.01 {
            ZStack {
                Image(name)
                    .resizable(resizingMode: .tile)
                    .opacity(min(strength, 1))
                if strength > 1 {
                    Image(name)
                        .resizable(resizingMode: .tile)
                        .opacity(min(strength - 1, 1))
                }
            }
        }
    }
}

/// The page behind every screen: a warm base, a faint lamp glow in dark mode, and paper grain.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.paperTexture) private var paper

    var body: some View {
        ZStack {
            Theme.page
            if scheme == .dark {
                RadialGradient(
                    colors: [Theme.accent.opacity(0.09), Color.clear],
                    center: .top, startRadius: 0, endRadius: 560
                )
            }
            PaperGrain(texture: paper.texture, strength: paper.strength)
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(scheme == .dark ? 0.14 : 0.04)],
                center: .center, startRadius: 240, endRadius: 980
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A sheet of paper: soft fill, grain, hairline edge and a gentle shadow.
struct PaperCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.paperTexture) private var paper
    var radius: CGFloat
    var raised: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                ZStack {
                    shape.fill(raised ? Theme.raised : Theme.surface)
                    PaperGrain(texture: paper.texture, strength: paper.strength)
                        .clipShape(shape)
                }
            )
            .overlay(shape.strokeBorder(Theme.line.opacity(0.85), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.10), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func paperCard(radius: CGFloat = 16, raised: Bool = false) -> some View {
        modifier(PaperCard(radius: radius, raised: raised))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(.headline, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 28)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(Capsule().fill(Theme.accent))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(.body, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryPaper: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quietPaper: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - UIKit bars

/// Navigation bars are drawn by UIKit, so they get their colors and serif titles here.
enum ThemeAppearance {
    @MainActor
    static func apply() {
        let ink = UIColor { UIColor(hex: $0.userInterfaceStyle == .dark ? Palette.ink.dark : Palette.ink.light) }
        let page = UIColor { UIColor(hex: $0.userInterfaceStyle == .dark ? Palette.page.dark : Palette.page.light) }
        let line = UIColor { UIColor(hex: $0.userInterfaceStyle == .dark ? Palette.line.dark : Palette.line.light) }

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.backgroundColor = page.withAlphaComponent(0.88)
        standard.shadowColor = line
        standard.titleTextAttributes = [.foregroundColor: ink, .font: serif(.headline, .semibold)]
        standard.largeTitleTextAttributes = [.foregroundColor: ink, .font: serif(.largeTitle, .bold)]

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = standard.titleTextAttributes
        edge.largeTitleTextAttributes = standard.largeTitleTextAttributes

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }

    private static func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            .withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
