import SwiftUI

/// Try the paper textures. The page behind this screen changes as you choose.
struct PaperPickerView: View {
    @EnvironmentObject private var prefs: AppPrefs

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)]

    private var strengthWords: String {
        switch prefs.textureStrength {
        case ..<0.05: return "None"
        case ..<0.75: return "Soft"
        case ..<1.25: return "Normal"
        default: return "Strong"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(PaperTexture.allCases) { texture in
                        Button {
                            prefs.paperTexture = texture
                        } label: {
                            Swatch(texture: texture, strength: prefs.textureStrength, selected: prefs.paperTexture == texture)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(texture.title)
                        .accessibilityAddTraits(prefs.paperTexture == texture ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Strength")
                            .font(Theme.serif(.headline, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(strengthWords)
                            .font(Theme.serif(.callout))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Slider(value: $prefs.textureStrength, in: 0...2, step: 0.25)
                        .tint(Theme.accent)
                        .accessibilityLabel("Texture strength")
                        .accessibilityValue(strengthWords)
                    Text("Textures only change how bright the page is, never its color, so they stay easy to read through your lenses.")
                        .font(Theme.serif(.footnote))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .padding(18)
                .paperCard()
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(PaperBackground())
        .navigationTitle("Paper")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Swatch: View {
    let texture: PaperTexture
    let strength: Double
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.page
            PaperGrain(texture: texture, strength: strength)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aa")
                    .font(Theme.serif(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(texture.title)
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(12)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 0.75)
        )
    }
}
