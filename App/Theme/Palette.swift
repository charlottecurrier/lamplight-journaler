import SwiftUI
import UIKit

/// Every color in the app lives here, as one hex pair (light / dark).
///
/// Tuned for reading through amber blue-blocking lenses:
/// - Meaning never depends on hue alone. Text, buttons and states differ in brightness.
/// - No blues or purples. Amber lenses turn them dark and muddy.
/// - The dark "lamp" theme is the default, since this is written at night.
///
/// `tools/check_palette.py` reads this file, checks contrast, and draws how it looks through amber lenses.
/// Keep the `Pair(light:dark:)` lines in this exact shape so the script can find them.
struct Pair {
    let light: UInt32
    let dark: UInt32
}

enum Palette {
    // Surfaces
    static let page = Pair(light: 0xF2EADB, dark: 0x1B1511)
    static let surface = Pair(light: 0xFAF5EA, dark: 0x261E18)
    static let surfaceRaised = Pair(light: 0xFFFBF2, dark: 0x30261E)
    static let line = Pair(light: 0xD9CCB5, dark: 0x4A3D30)

    // Text
    static let ink = Pair(light: 0x2A2018, dark: 0xF1E4CC)
    static let inkSecondary = Pair(light: 0x5C4D38, dark: 0xBDAA8D)
    static let inkTertiary = Pair(light: 0x6A5A43, dark: 0xA8967C)

    // Accents
    static let accent = Pair(light: 0x923F19, dark: 0xE39A62)
    static let onAccent = Pair(light: 0xFFF6E8, dark: 0x1B1511)
    static let sage = Pair(light: 0x4F6A3F, dark: 0xA9BE92)
    static let danger = Pair(light: 0x932F20, dark: 0xF0A090)

    // Journal colors (see JournalColors.keys). "ember" uses the accent.
    static let journalSage = Pair(light: 0x4F6A3F, dark: 0xA9BE92)
    static let journalGold = Pair(light: 0x7D5F12, dark: 0xDDB95F)
    static let journalClay = Pair(light: 0x93443A, dark: 0xD08C7B)
    static let journalMoss = Pair(light: 0x56662E, dark: 0x93A66C)
    static let journalStone = Pair(light: 0x6B6358, dark: 0xB1A899)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Pair {
    /// The same color for UIKit views, following light and dark.
    var uiColor: UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? self.dark : self.light)
        }
    }

    /// A color that follows the current light or dark appearance.
    var color: Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? self.dark : self.light)
        })
    }
}
