import AppKit
import SwiftUI

// Silvanus
//   Silvanus                      the app
//   APP_STORE=<dir> Silvanus      use another meetings folder (tests, experiments)
//   APP_SEED=1 APP_STORE=/tmp/<dir> Silvanus   fill an empty /tmp store with fictional meetings
//   APP_SNAPSHOT=<dir> Silvanus   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   Silvanus --selftest           run the self-test on a /tmp folder and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Silvanus      run with another accent from Theme.all (UI/Theme.swift)
//   APP_KIT_GALLERY=1 Silvanus    show the design kit's gallery instead of the pages (DesignKit/KitGallery.swift);
//                                 APP_COLORS=reference draws the kit in the reference colors
//   APP_GRID=1 Silvanus           draw the 8 pt grid and the layout probes over the window
//   APP_EDITOR_SPIKE=1 Silvanus   open the native editor spike (Editor/EditorSpikeWindow.swift);
//                                 APP_EDITOR_CHECK=1 and APP_EDITOR_BENCH=1 run its checks and benchmark headless
// Test runs read and write their own defaults (AppDefaults.swift).

@main
struct SilvanusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(root: Store.root)

    var body: some Scene {
        Window("Silvanus", id: "main") {
            Group {
                if KitGallery.enabled { KitGalleryPage() } else { ContentView() }
            }
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
            AboutCommand()
        }

        Window("About Silvanus", id: "about") {
            BrandAboutView()
                .themed()
                .noInitialFocus()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        // Static on purpose: no timer and no changing label (a live label here has hung the menu bar).
        MenuBarExtra {
            MenuBarMenu()
        } label: {
            Image(nsImage: Brand.menuBarGlyph)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

/// The menu bar item's menu: bring the main window forward, or quit.
struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Silvanus") {
            NSApp.activate()
            openWindow(id: "main")
        }
        Button("Quit Silvanus") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Replaces the standard About item with the About window (UI/Brand.swift).
struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Silvanus") { openWindow(id: "about") }
        }
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
