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

    @ObservationIgnored private var backgroundedAt: Date?
    /// Set once the lock screen has asked for Face ID on its own. After a cancel, only the Unlock button asks again.
    @ObservationIgnored private var hasAutoPrompted = false

    init(startLocked: Bool) {
        isLocked = startLocked
    }

    /// "Face ID" or "Touch ID", or nil when the device has neither set up and only its passcode can open the app.
    static var biometryName: String? {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return nil
        }
    }

    /// "Face ID", "Touch ID", or "your passcode". For button and settings labels.
    static var methodName: String { biometryName ?? "your passcode" }

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
            if success { isLocked = false }
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
