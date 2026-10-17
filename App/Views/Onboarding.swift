import SwiftUI

/// First launch: a short welcome, where the journal lives, and the lock. Three quiet screens.
struct OnboardingView: View {
    enum Step {
        case welcome
        case storage
        case privacy
    }

    @Environment(AppModel.self) private var model
    @EnvironmentObject private var prefs: AppPrefs

    /// False when this is shown only to pick a folder again, outside of first launch.
    var finishesOnboarding: Bool

    @State private var step: Step
    @State private var showFolderPicker = false
    @State private var lockProblem: String?

    init(startAt: Step = .welcome, finishesOnboarding: Bool = true) {
        self.finishesOnboarding = finishesOnboarding
        _step = State(initialValue: startAt)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            Group {
                switch step {
                case .welcome: welcome
                case .storage: storage
                case .privacy: privacy
                }
            }
            .frame(maxWidth: 520)
            .padding(32)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                showFolderPicker = false
                model.useFolder(url)
                advanceFromStorage()
            } onCancel: {
                showFolderPicker = false
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "book.closed")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Lamplight")
                .font(Theme.serif(size: 46, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("A quiet place to write at the end of the day.")
                .font(Theme.serif(.title3))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Begin") { step = .storage }
                .buttonStyle(.primaryPaper)
        }
    }

    private var storage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Where should your journal live?")
                    .font(Theme.serif(.title, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 12) {
                    Label("iCloud Drive folder", systemImage: "icloud")
                        .font(Theme.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Syncs between your iPad and iPhone. In the Files app, pick or create a folder, like “Journal”. Everything is saved there as plain text and photos, so it's yours to keep.")
                        .font(Theme.serif(.callout))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("On your other device, choose the same folder.")
                        .font(Theme.serif(.footnote))
                        .foregroundStyle(Theme.inkTertiary)
                    Button("Choose a Folder") { showFolderPicker = true }
                        .buttonStyle(.primaryPaper)
                        .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Only on this device", systemImage: "ipad.and.iphone")
                        .font(Theme.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Stays here and doesn't sync. You can move to a folder later, and your entries come with you.")
                        .font(Theme.serif(.callout))
                        .foregroundStyle(Theme.inkSecondary)
                    Button("Keep It on This Device") {
                        model.useLocalStorage()
                        advanceFromStorage()
                    }
                    .buttonStyle(.quietPaper)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()
            }
            .padding(.vertical, 8)
        }
    }

    private var privacy: some View {
        let method = LockManager.methodName
        return VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: method == "Touch ID" ? "touchid" : "faceid")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Keep it private")
                .font(Theme.serif(.title, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Lock Lamplight with \(method). If it doesn't work, your device passcode opens it.")
                .font(Theme.serif(.title3))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            if let lockProblem {
                Text(lockProblem)
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Button("Turn On \(method)") {
                if LockManager.canAuthenticate {
                    prefs.lockEnabled = true
                    finish()
                } else {
                    lockProblem = "This device has no passcode yet. Set one in the Settings app, then turn the lock on in Lamplight's settings."
                }
            }
            .buttonStyle(.primaryPaper)
            Button("Not Now") { finish() }
                .buttonStyle(.quietPaper)
        }
    }

    // MARK: Moving on

    private func advanceFromStorage() {
        if finishesOnboarding { step = .privacy }
    }

    private func finish() {
        prefs.onboardingComplete = true
    }
}

/// Shown while the journal folder is opened. First launch on a second device can take a moment
/// while iCloud brings the entries down.
struct LoadingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Opening your journal…")
                    .font(Theme.serif(.title3))
                    .foregroundStyle(Theme.inkSecondary)
                if model.totalCount > 0 {
                    Text("\(model.loadedCount) of \(model.totalCount) entries")
                        .font(Theme.serif(.footnote))
                        .foregroundStyle(Theme.inkTertiary)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}

/// Shown when the saved folder can't be opened, for example if it was moved or deleted.
/// Nothing is lost: the entries are still wherever that folder is.
struct StorageProblemView: View {
    @Environment(AppModel.self) private var model
    let message: String

    @State private var showFolderPicker = false

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 18) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.inkTertiary)
                    .accessibilityHidden(true)
                Text("Can't open your journal")
                    .font(Theme.serif(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.serif(.callout))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Text("Your entries are still in that folder. Nothing has been deleted.")
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { model.start() }
                    .buttonStyle(.primaryPaper)
                Button("Choose the Folder Again") { showFolderPicker = true }
                    .buttonStyle(.quietPaper)
            }
            .padding(32)
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                showFolderPicker = false
                model.useFolder(url)
            } onCancel: {
                showFolderPicker = false
            }
        }
    }
}
