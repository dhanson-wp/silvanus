import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/Silvanus-test APP_SNAPSHOT=/tmp/shots \
///     ~/Library/Developer/Silvanus/Silvanus.app/Contents/MacOS/Silvanus -ApplePersistenceIgnoreState YES
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // The editor spike takes its own snapshots (runEditorSpikeIfRequested).
        if EditorSpike.enabled { return }
        // Snapshots never run against the real meetings folder.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a folder in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            keepDisplayAwake()
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// A sleeping display gives screencapture nothing. Declaring user
    /// activity wakes it; the assertion keeps it on until the run quits.
    private static func keepDisplayAwake() {
        var activity: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
        var awake: IOPMAssertionID = 0
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
    }

    /// The editor spike (APP_EDITOR_SPIKE=1): editor-heading-<mode>.png with the
    /// caret on the H1 (its markers shown, the others faded), editor-plain-<mode>.png
    /// with the caret on a plain line (every marker faded), and editor-find-<mode>.png
    /// with the find bar open. Prints whether TextKit 2 stayed on, then quits.
    static func runEditorSpikeIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a folder in /tmp")
            NSApp.terminate(nil)
            return
        }
        Task {
            keepDisplayAwake()
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            guard let window = EditorSpike.window, let view = EditorSpike.textView else {
                print("SNAPSHOT no editor window")
                NSApp.terminate(nil)
                return
            }
            print("SNAPSHOT TextKit 2 after setup: \(view.isTextKit2)")
            let text = view.string as NSString
            let heading = 5
            let plain = text.range(of: "Plain closing line").location + 6
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                window.makeFirstResponder(view)
                for (name, caret) in [("heading", heading), ("plain", plain)] {
                    view.setSelectedRange(NSRange(location: caret, length: 0))
                    view.scrollRangeToVisible(view.selectedRange())
                    try? await Task.sleep(for: .seconds(0.6))
                    capture(to: "\(dir)/editor-\(name)-\(mode).png", window: window)
                }
            }
            // The find bar, searching for a name, then the TextKit 2 check.
            let item = NSMenuItem()
            let first = text.range(of: "Priya")
            let second = text.range(of: "Priya", range: NSRange(location: NSMaxRange(first), length: text.length - NSMaxRange(first)))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                view.setSelectedRange(first)
                for action in [NSTextFinder.Action.showFindInterface, .setSearchString] {
                    item.tag = Int(action.rawValue)
                    view.performTextFinderAction(item)
                }
                try? await Task.sleep(for: .seconds(0.4))
                item.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
                view.performTextFinderAction(item)
                try? await Task.sleep(for: .seconds(0.6))
                let found = view.selectedRange()
                print("SNAPSHOT find next match: \(found == second ? "PASS" : "FAIL") (selected \(found), expected \(second))")
                capture(to: "\(dir)/editor-find-\(mode).png", window: window)
            }
            print("SNAPSHOT TextKit 2 after find: \(view.isTextKit2)")
            print("SNAPSHOT done \(dir)")
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
