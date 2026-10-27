import SwiftUI

/// Decides what to show: setup, the lock, or the journal.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockManager.self) private var lock
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lamp comes on when the journal opens: the page eases up out of the dark and a warm light passes over it.
    @State private var lampOn = false
    @State private var glow = 0.0

    var body: some View {
        ZStack {
            content
                .overlay { dimming }
                .overlay { lampLight }
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
        .environment(\.paperTexture, PaperTextureChoice(texture: prefs.paperTexture, strength: prefs.textureStrength))
        .tint(Theme.accent)
        .foregroundStyle(Theme.ink)
        .onChange(of: scenePhase) {
            lock.sceneChanged(
                to: scenePhase,
                lockEnabled: prefs.lockEnabled,
                timeout: prefs.lockTimeout.seconds
            )
            if scenePhase == .active {
                Task { @MainActor in await model.refresh() }
            } else {
                // Anything still waiting to be written goes out before the app can be closed.
                model.flushPendingWrites()
            }
        }
        .onChange(of: prefs.lockEnabled) {
            if !prefs.lockEnabled { lock.forceUnlock() }
        }
        // Each time the journal locks, the lamp goes out, ready to come on again at the next unlock.
        .onChange(of: lock.isLocked) {
            if lock.isLocked {
                lampOn = false
                glow = 0
            }
        }
        .task(id: lock.isLocked) {
            if !lock.isLocked { await lightLamp() }
        }
        // Ask for Face ID as soon as the lock screen is in front. Cancelling doesn't ask again;
        // the Unlock button does.
        .task(id: lock.isLocked && scenePhase == .active) {
            guard scenePhase == .active, lock.takeAutoPrompt() else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await lock.unlock()
        }
    }

    /// The page color laid over everything while the lamp is out. It fades away as the lamp comes on.
    private var dimming: some View {
        Theme.page
            .opacity(lampOn || reduceMotion ? 0 : 0.92)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeOut(duration: 1.3), value: lampOn)
            .accessibilityHidden(true)
    }

    private var lampLight: some View {
        RadialGradient(
            colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0)],
            center: .top,
            startRadius: 0,
            endRadius: 560
        )
        .opacity(glow)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private func lightLamp() async {
        guard !reduceMotion else {
            lampOn = true
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        lampOn = true
        withAnimation(.easeOut(duration: 0.7)) { glow = 1 }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 1.8)) { glow = 0 }
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
