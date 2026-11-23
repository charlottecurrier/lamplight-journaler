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
        .commands { LamplightCommands() }
    }
}

/// The keyboard shortcuts that work from anywhere in the app. They also show when Command is held down, and in the
/// menu bar where there is one.
///
/// Each posts a notification that `MainView` acts on, so a shortcut does exactly what the button does. They live
/// here and not on the buttons, because a button's shortcut only works while that button is on screen: Command-N
/// did nothing while a page was open, since the New Entry button is hidden then. The editor's own shortcuts (bold,
/// lists, headings) are in `MarkdownUITextView`, and use different keys.
struct LamplightCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { post(.lamplightNewEntry) }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings") { post(.lamplightShowSettings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Go") {
            Button("All Entries") { go(.all) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Today") { go(.today) }
                .keyboardShortcut("2", modifiers: .command)
            Button("On This Day") { go(.onThisDay) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Favorites") { go(.favorites) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Calendar") { go(.calendar) }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
            // Not plain Command-arrows: in a page being written those move the caret to the top and the bottom.
            Button("Newer Entry") { post(.lamplightTurnPage, object: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Older Entry") { post(.lamplightTurnPage, object: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
    }

    private func post(_ name: Notification.Name, object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }

    private func go(_ item: SidebarItem) {
        post(.lamplightGo, object: item)
    }
}
