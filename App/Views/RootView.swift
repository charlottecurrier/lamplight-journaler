import SwiftUI

/// Decides what to show: setup, the lock, or the journal.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockManager.self) private var lock
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            content
                .disabled(lock.isLocked)
                .accessibilityHidden(lock.isLocked)

            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            } else if scenePhase != .active && prefs.lockEnabled {
                PrivacyCover()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .preferredColorScheme(prefs.appearance.colorScheme)
        .tint(Theme.accent)
        .foregroundStyle(Theme.ink)
        .onChange(of: scenePhase) {
            lock.sceneChanged(
                to: scenePhase,
                lockEnabled: prefs.lockEnabled,
                timeout: prefs.lockTimeout.seconds
            )
            if scenePhase == .active {
                Task { await model.refresh() }
            }
        }
        .onChange(of: prefs.lockEnabled) {
            if !prefs.lockEnabled { lock.forceUnlock() }
        }
        // Ask for Face ID as soon as the lock screen is in front. Cancelling doesn't ask again;
        // the Unlock button does.
        .task(id: lock.isLocked && scenePhase == .active) {
            guard lock.isLocked, scenePhase == .active else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await lock.unlock()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !prefs.onboardingComplete {
            OnboardingView()
        } else {
            switch model.phase {
            case .needsStorage:
                OnboardingView(startAt: .storage, finishesOnboarding: false)
            case .loading:
                LoadingView()
            case .ready:
                MainView()
            case .problem(let message):
                StorageProblemView(message: message)
            }
        }
    }
}
