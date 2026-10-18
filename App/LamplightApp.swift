import SwiftUI

@main
struct LamplightApp: App {
    @StateObject private var prefs = AppPrefs()
    @State private var model: AppModel
    @State private var lock: LockManager

    @MainActor
    init() {
        ThemeAppearance.apply()
        let model = AppModel()
        model.start()
        _model = State(initialValue: model)
        _lock = State(initialValue: LockManager(startLocked: AppPrefs.lockEnabledAtLaunch))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .environmentObject(prefs)
        }
    }
}
