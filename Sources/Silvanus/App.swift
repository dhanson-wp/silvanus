import AppKit
import SwiftUI

// Silvanus
//   Silvanus                      the app
//   APP_STORE=<dir> Silvanus      use another meetings folder (tests, experiments)
//   APP_SEED=1 APP_STORE=/tmp/<dir> Silvanus   fill an empty /tmp store with fictional meetings
//   APP_SNAPSHOT=<dir> Silvanus   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   Silvanus --selftest           run the self-test on a /tmp folder and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Silvanus      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Silvanus           draw the 8 pt grid and the layout probes over the window
// Test runs read and write their own defaults (AppDefaults.swift).

@main
struct SilvanusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(root: Store.root)

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives. Meetings are folders of plain files under
/// `<root>/meetings/` (SilvanusKit's `MeetingLibrary`).
enum Store {
    /// APP_STORE when set (tests and snapshots), else ~/Silvanus, resolved at runtime.
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Silvanus")
    }

    /// True when APP_STORE points somewhere else (tests and snapshots).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    /// True when APP_STORE is set and lives under /tmp. Seeding, snapshots,
    /// and the self-test run only then, so they can never touch real meetings.
    static var isScratch: Bool {
        guard isOverridden else { return false }
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/tmp/") || path.hasPrefix("/tmp/")
    }
}
