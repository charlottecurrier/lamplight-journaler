import SwiftUI
import LocalAuthentication
import UIKit

/// The app lock. Uses Face ID (or Touch ID), and the device passcode when biometrics fail or aren't set up.
@MainActor
@Observable
final class LockManager {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var failureMessage: String?
    /// True when the lock is on but this device has no passcode, so there is nothing to unlock with.
    private(set) var passcodeMissing = false

    /// When the app stopped being in front: sent to the background, or covered by the app switcher.
    @ObservationIgnored private var backgroundedAt: Date?
    /// Set once the lock screen has asked for Face ID on its own. After a cancel, only the Unlock button asks again.
    @ObservationIgnored private var hasAutoPrompted = false
    /// When the journal was last unlocked. The Face ID sheet going away can make the app inactive once more.
    @ObservationIgnored private var unlockedAt: Date?

    init(startLocked: Bool) {
        isLocked = startLocked
    }

    /// "Face ID", "Touch ID", or "your passcode". For button and settings labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "your passcode"
        }
    }

    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Call whenever the app moves between active, inactive and background.
    func sceneChanged(to phase: ScenePhase, lockEnabled: Bool, timeout: TimeInterval) {
        guard lockEnabled else {
            backgroundedAt = nil
            isLocked = false
            return
        }
        switch phase {
        case .inactive:
            // The app switcher only makes the app inactive. Coming back from it counts as having left, or the
            // journal could be opened from the switcher with no check. The Face ID sheet makes the app inactive
            // too, so this is skipped while the journal is locked or being unlocked, and for a moment after.
            let justUnlocked = unlockedAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false
            if !isLocked, !isAuthenticating, !justUnlocked, backgroundedAt == nil { backgroundedAt = Date() }
        case .background:
            if backgroundedAt == nil { backgroundedAt = Date() }
            hasAutoPrompted = false
        case .active:
            if let since = backgroundedAt {
                backgroundedAt = nil
                if Date().timeIntervalSince(since) >= timeout { lock() }
            }
        default:
            break
        }
    }

    /// True once, each time the lock screen comes up, so Face ID is offered automatically but never nagged.
    func takeAutoPrompt() -> Bool {
        guard isLocked, !hasAutoPrompted else { return false }
        hasAutoPrompted = true
        return true
    }

    func lock() {
        guard !isLocked else { return }
        hasAutoPrompted = false
        isLocked = true
        failureMessage = nil
        // Close the keyboard so nothing stays open behind the lock screen.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func forceUnlock() {
        isLocked = false
        failureMessage = nil
        passcodeMissing = false
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        failureMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            passcodeMissing = true
            failureMessage = "This device has no passcode, so the lock can't be checked."
            return
        }
        passcodeMissing = false
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your journal"
            )
            if success {
                isLocked = false
                unlockedAt = Date()
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                break
            default:
                failureMessage = "That didn't work. Try again."
            }
        } catch {
            failureMessage = "That didn't work. Try again."
        }
    }
}
