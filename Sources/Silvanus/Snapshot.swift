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
/// The brand set (about, menu bar glyphs) is written with the pages; "brand" in APP_SNAPSHOT_PAGES limits to it.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real meetings folder.
        guard Store.isScratch else {
            print("SNAPSHOT refused: set APP_STORE to a folder under /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
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
            if only == nil || only?.contains("brand") == true {
                renderBrand(to: dir)
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// The brand set: About in light and dark, and the menu bar glyphs (idle and
    /// recording) on a light and a dark bar. Drawn straight from the views and
    /// images, so no window or Screen Recording permission is needed.
    ///   about-light.png, about-dark.png, menubar-light.png, menubar-dark.png,
    ///   menubar-recording-light.png, menubar-recording-dark.png
    @MainActor private static func renderBrand(to dir: String) {
        for mode in ["light", "dark"] {
            let appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)!
            NSApp.appearance = appearance
            // About: the same view the About window shows, on the window background.
            let host = NSHostingView(rootView: BrandAboutView().themed())
            host.appearance = appearance
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            var about: NSBitmapImageRep?
            appearance.performAsCurrentDrawingAppearance {
                about = bitmap(pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2), size: host.bounds.size) { rect in
                    NSColor.windowBackgroundColor.setFill()
                    rect.fill()
                    if let context = NSGraphicsContext.current {
                        host.displayIgnoringOpacity(host.bounds, in: context)
                    }
                }
            }
            write(about, to: "\(dir)/about-\(mode).png")
            // Menu bar: each glyph at 18 pt, 4x, in the bar's ink color on the bar's color.
            let ink: NSColor = mode == "light" ? .black : .white
            let bar: NSColor = mode == "light" ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.16, alpha: 1)
            for (name, glyph) in [("menubar", Brand.menuBarGlyph), ("menubar-recording", Brand.menuBarRecordingGlyph)] {
                let rep = bitmap(pixelsWide: 144, pixelsHigh: 96, size: NSSize(width: 36, height: 24)) { rect in
                    bar.setFill()
                    rect.fill()
                    let tinted = NSImage(size: glyph.size, flipped: false) { r in
                        glyph.draw(in: r)
                        ink.set()
                        r.fill(using: .sourceIn)
                        return true
                    }
                    tinted.draw(in: NSRect(origin: NSPoint(x: 9, y: 3), size: Brand.menuBarSize))
                }
                write(rep, to: "\(dir)/\(name)-\(mode).png")
            }
        }
    }

    @MainActor private static func bitmap(pixelsWide: Int, pixelsHigh: Int, size: NSSize, draw: (NSRect) -> Void) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep?, to path: String) {
        guard let data = rep?.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT \(path)")
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
