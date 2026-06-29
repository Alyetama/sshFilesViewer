import SwiftUI

@main
struct SSHFilesViewerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 600)
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") { model.beginAddConnection() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            // Replace the standard Settings… item so ⌘, opens our window scene.
            CommandGroup(replacing: .appSettings) {
                SettingsMenuButton()
            }
        }

        // A dedicated, fully-controlled Settings window (more reliable than the
        // SwiftUI `Settings` scene / showSettingsWindow: selector on recent macOS).
        Window("Settings", id: settingsWindowID) {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

/// Menu button that opens the Settings window via `openWindow`.
struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: settingsWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
