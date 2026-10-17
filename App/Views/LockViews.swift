import SwiftUI

/// Covers everything while the app is locked.
struct LockView: View {
    @Environment(LockManager.self) private var lock
    @EnvironmentObject private var prefs: AppPrefs

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 22) {
                Image(systemName: "lock")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Lamplight")
                    .font(Theme.serif(size: 38, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Your journal is locked.")
                    .font(Theme.serif(.title3))
                    .foregroundStyle(Theme.inkSecondary)

                if let message = lock.failureMessage {
                    Text(message)
                        .font(Theme.serif(.footnote))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                Button("Unlock with \(LockManager.methodName)") {
                    Task { @MainActor in await lock.unlock() }
                }
                .buttonStyle(.primaryPaper)
                .padding(.top, 8)

                if lock.passcodeMissing {
                    Button("Turn Off the Lock") {
                        prefs.lockEnabled = false
                        lock.forceUnlock()
                    }
                    .buttonStyle(.quietPaper)
                }
            }
            .padding(32)
        }
    }
}

/// Hides the journal in the app switcher and whenever the app isn't in front.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            PaperBackground()
            Image(systemName: "book.closed")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityHidden(true)
    }
}
