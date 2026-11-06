import AppKit
import SwiftUI

// Silvanus
//   Silvanus                      the app
//   APP_STORE=<dir> Silvanus      use another meetings folder (tests, experiments)
//   APP_SNAPSHOT=<dir> Silvanus   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   Silvanus --selftest           run the self-test on a /tmp folder and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Silvanus      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Silvanus           draw the 8 pt grid and the layout probes over the window
//   APP_EDITOR_SPIKE=1 Silvanus   open the native editor spike (Editor/EditorSpikeWindow.swift);
//                                 APP_EDITOR_CHECK=1 and APP_EDITOR_BENCH=1 run its checks and benchmark headless
// Test runs read and write their own defaults (AppDefaults.swift).

@main
struct SilvanusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Silvanus", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The editor's checks and benchmark run before any window opens, then quit.
        if let code = EditorSpike.runHeadlessIfRequested() { exit(code) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        EditorSpike.openIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives. Meetings are folders of plain files; the folder
/// store comes with the meeting type.
enum Store {
    /// True when APP_STORE points somewhere else (tests and snapshots).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }
}
