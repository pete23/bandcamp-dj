import AppKit
import SwiftUI

@main
struct BandcampSyncApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Bandcamp Sync", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 680, minHeight: 360)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Check Again") { Task { await model.check() } }
                    .keyboardShortcut("r")
                    .disabled(model.phase != .idle)
                Button("Sync") { Task { await model.sync() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!model.canSync)
                Divider()
                Button("Show Download Folder") { NSWorkspace.shared.open(model.preferences.folder) }
                    .disabled(!FileManager.default.fileExists(atPath: model.preferences.folder.path))
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without a bundle (`swift run BandcampSyncApp`) the app would start in the background.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
