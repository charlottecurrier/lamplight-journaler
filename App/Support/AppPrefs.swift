import SwiftUI

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case lamp
    case paper
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lamp: return "Lamp (dark)"
        case .paper: return "Paper (light)"
        case .system: return "Match this device"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .lamp: return .dark
        case .paper: return .light
        case .system: return nil
        }
    }
}

enum LockTimeout: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .immediately: return "Right away"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        }
    }
}

/// The texture laid over the page. Each one is a faint tile that changes brightness only.
enum PaperTexture: String, CaseIterable, Identifiable {
    // Even, regular textures first. The rough ones, with flecks or patches, come last.
    case plain, cotton, linen, laid, dots, tooth, leather, wash, fibers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "Plain"
        case .fibers: return "Fibers"
        case .cotton: return "Cotton"
        case .laid: return "Laid"
        case .linen: return "Linen"
        case .leather: return "Leather"
        case .wash: return "Wash"
        case .tooth: return "Tooth"
        case .dots: return "Dot grid"
        }
    }

    /// The image in the asset catalog, or nil for a plain page.
    func imageName(dark: Bool) -> String? {
        let mode = dark ? "Dark" : "Light"
        switch self {
        case .plain: return nil
        case .fibers: return "PaperGrain" + mode
        default: return "Paper" + rawValue.capitalized + mode
        }
    }
}

/// Settings that belong to this device. Settings that should follow you to other devices
/// (like your Home place) live in the journal folder instead.
@MainActor
final class AppPrefs: ObservableObject {
    private enum Key {
        static let appearance = "prefs.appearance"
        static let lockEnabled = "prefs.lockEnabled"
        static let lockTimeout = "prefs.lockTimeout"
        static let rolloverHour = "prefs.rolloverHour"
        static let openToNewEntry = "prefs.openToNewEntry"
        static let paperTexture = "prefs.paperTexture"
        static let textureStrength = "prefs.textureStrength"
        static let onboardingComplete = "prefs.onboardingComplete"
    }

    /// Read before the app's screens exist, to decide whether to start locked.
    static var lockEnabledAtLaunch: Bool {
        UserDefaults.standard.bool(forKey: Key.lockEnabled)
    }

    private let defaults: UserDefaults

    @Published var appearance: AppearanceChoice {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var lockEnabled: Bool {
        didSet { defaults.set(lockEnabled, forKey: Key.lockEnabled) }
    }

    @Published var lockTimeout: LockTimeout {
        didSet { defaults.set(lockTimeout.rawValue, forKey: Key.lockTimeout) }
    }

    /// Hour (0-12) when a new journal day starts. 0 is midnight.
    @Published var rolloverHour: Int {
        didSet { defaults.set(rolloverHour, forKey: Key.rolloverHour) }
    }

    @Published var paperTexture: PaperTexture {
        didSet { defaults.set(paperTexture.rawValue, forKey: Key.paperTexture) }
    }

    /// 0 is none, 1 is the texture as designed, up to 2 for twice as strong.
    @Published var textureStrength: Double {
        didSet { defaults.set(textureStrength, forKey: Key.textureStrength) }
    }

    /// Opening the app starts a new entry, if nothing has been written yet today.
    @Published var openToNewEntry: Bool {
        didSet { defaults.set(openToNewEntry, forKey: Key.openToNewEntry) }
    }

    @Published var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceChoice.init(rawValue:)) ?? .lamp
        lockEnabled = defaults.bool(forKey: Key.lockEnabled)
        lockTimeout = LockTimeout(rawValue: defaults.integer(forKey: Key.lockTimeout)) ?? .immediately
        rolloverHour = defaults.integer(forKey: Key.rolloverHour)
        openToNewEntry = defaults.object(forKey: Key.openToNewEntry) as? Bool ?? true
        paperTexture = defaults.string(forKey: Key.paperTexture).flatMap(PaperTexture.init(rawValue:)) ?? .cotton
        textureStrength = defaults.object(forKey: Key.textureStrength) as? Double ?? 1.0
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
    }

    var dayCalendar: DayCalendar { DayCalendar(rolloverHour: rolloverHour) }
}
