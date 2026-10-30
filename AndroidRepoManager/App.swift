import SwiftUI

@main
struct AndroidRepoManagerApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
        .commands { AppCommands() }

        Settings {
            AppSettingsView()
        }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Folder") { appState?.createNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState == nil)
            Button("Push…") { appState?.presentPushPicker() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(appState == nil)
            Button("Pull to Mac") { appState?.pullSelectionToMac() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(appState?.selection.isEmpty ?? true)
            Button("Delete") { appState?.requestDelete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState?.selection.isEmpty ?? true)
        }

        CommandGroup(after: .toolbar) {
            Button("as List") { appState?.viewMode = .list }
                .keyboardShortcut("1", modifiers: .command)
            Button("as Grid") { appState?.viewMode = .grid }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("Show Inspector") { appState?.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Show Hidden Files") { appState?.settings.showHiddenFiles.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
        }

        CommandMenu("Go") {
            Button("Back") { appState?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(appState?.canGoBack ?? false))
            Button("Forward") { appState?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(appState?.canGoForward ?? false))
            Button("Enclosing Folder") { appState?.goToParent() }
                .keyboardShortcut(.upArrow, modifiers: .command)
        }
    }
}
