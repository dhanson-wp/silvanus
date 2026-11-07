import AppKit
import IOKit.pwr_mgt
import SilvanusKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/Silvanus-test APP_SNAPSHOT=/tmp/shots \
///     ~/Library/Developer/Silvanus/Silvanus.app/Contents/MacOS/Silvanus -ApplePersistenceIgnoreState YES
/// writes <page>-light.png and <page>-dark.png for every sidebar page, the window frame at
/// its default and minimum sizes and with the sidebar hidden (captureFrames), and
/// settings-<pane>-light.png and settings-<pane>-dark.png for every Settings pane (Settings is
/// open in the main window), then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// It also writes canvas-light.png and canvas-dark.png: the notes canvas with a seeded meeting open.
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "window" for the frames, "canvas" for the
/// notes canvas, "summary" for the Summary view, "transcript" for the Transcript view, "recording" for
/// the recording states, the recording controls, the Meeting detected prompt, and the permissions sheet, "settings" for Settings.
/// "reference-main" (only when asked for by name) writes the reference-main page for the pixel
/// compare (captureReferenceMain, tools/compare.sh).
/// The brand set (about, menu bar glyphs) is written with the pages; "brand" in APP_SNAPSHOT_PAGES limits to it.
/// With APP_KIT_GALLERY=1 it writes only the kit gallery (renderGallery), then quits.
enum Snapshot {
    /// True when this run takes snapshots (APP_SNAPSHOT).
    static var requested: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }

    static func runIfRequested(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // The editor spike takes its own snapshots (runEditorSpikeIfRequested).
        if EditorSpike.enabled { return }
        // Snapshots never run against the real meetings folder.
        guard Store.isScratch else {
            print("SNAPSHOT refused: set APP_STORE to a folder under /tmp")
            NSApp.terminate(nil)
            return
        }
        // The kit gallery replaces the pages (APP_KIT_GALLERY=1): capture it alone.
        if KitGallery.enabled {
            Task {
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? await Task.sleep(for: .seconds(1))
                renderGallery(to: dir)
                print("SNAPSHOT done \(dir)")
                NSApp.terminate(nil)
            }
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        // A selected row, so the pages show the sidebar's selection.
        if model.selection == nil { model.selection = model.meetings.first?.id }
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
            if only == nil || only?.contains("window") == true {
                await captureFrames(model: model, to: dir)
            }
            if only == nil || only?.contains("canvas") == true {
                await captureCanvas(model: model, to: dir)
            }
            if only == nil || only?.contains("summary") == true {
                await captureSummary(model: model, to: dir)
            }
            if only == nil || only?.contains("transcript") == true {
                await captureTranscript(model: model, to: dir)
            }
            if only == nil || only?.contains("recording") == true {
                await captureRecording(model: model, to: dir)
            }
            if only == nil || only?.contains("settings") == true {
                // Settings takes the main window, so each pane is the window itself.
                model.sidebar = .all
                model.openSettings()
                try? await Task.sleep(for: .seconds(0.8))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for pane in SettingsPane.allCases {
                        model.settingsPane = pane
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/settings-\(pane.rawValue)-\(mode).png")
                    }
                }
                model.closeSettings()
            }
            if only?.contains("reference-main") == true {
                await captureReferenceMain(model: model, to: dir)
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

    /// The window frame (DesignKit/Window) at the kit's sizes, for measuring the divider,
    /// traffic lights, and header against design/KIT.md "Window":
    ///   window-<mode>.png            910 × 600, the default and pixel-compare size
    ///   window-min-<mode>.png        720 × 480, the minimum: nothing in the header overlaps
    ///   window-collapsed-<mode>.png  910 × 600 with the sidebar hidden
    ///   window-long-<mode>.png       910 × 600, the open meeting with a 120-character title
    ///                                and a long folder name (Review Focus 1 and 2)
    ///   window-min-long-<mode>.png   the same at 720 × 480
    /// The long title and folder are set in memory only, never saved.
    @MainActor private static func captureFrames(model: AppModel, to dir: String) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else { return }
        let frames: [(name: String, size: CGSize, sidebar: Bool, long: Bool)] = [
            ("window", Metric.windowDefault, true, false),
            ("window-min", Metric.windowMinimum, true, false),
            ("window-collapsed", Metric.windowDefault, false, false),
            ("window-long", Metric.windowDefault, true, true),
            ("window-min-long", Metric.windowMinimum, true, true),
        ]
        model.sidebar = .all
        let original = model.meetings
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            for frame in frames {
                model.sidebarVisible = frame.sidebar
                if frame.long, let index = model.meetings.firstIndex(where: { $0.id == model.selection }) {
                    model.meetings[index].info.title = HeadersGallery.longTitle
                    model.meetings[index].info.folder = HeadersGallery.longFolder
                } else if model.meetings != original {
                    model.meetings = original
                }
                main.setContentSize(frame.size)
                try? await Task.sleep(for: .seconds(0.8))
                capture(to: "\(dir)/\(frame.name)-\(mode).png", window: main)
            }
        }
        model.meetings = original
        model.sidebarVisible = true
        main.setContentSize(Metric.windowDefault)
    }

    /// The reference-main page, for the pixel compare against the reference capture
    /// (tools/compare.sh, design/KIT.md "Compare"): reference-main-light.png and
    /// reference-main-dark.png at 910 × 600, with SeedData.referenceMain's fictional meetings
    /// laid out like the reference (seven rows under Yesterday, the sixth open on My notes,
    /// no meeting header, no Folders section). Run it with APP_COLORS=reference. The meetings
    /// are written to the scratch store; the sidebar lists only them.
    @MainActor private static func captureReferenceMain(model: AppModel, to dir: String) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }), Store.isScratch else { return }
        let meetings = SeedData.referenceMain()
        for meeting in meetings { _ = try? model.library.save(meeting) }
        let original = model.meetings
        model.closeSettings()
        model.sidebar = .all
        model.folder = nil
        model.sidebarVisible = true
        model.referenceStage = true
        model.meetings = meetings
        model.canvasMode = .notes
        model.selection = SeedData.referenceSelectedID
        main.setContentSize(Metric.windowDefault)
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/reference-main-\(mode).png", window: main)
        }
        model.selection = nil
        model.referenceStage = false
        model.meetings = original
    }

    /// The notes canvas with the first seeded meeting open: canvas-light.png and
    /// canvas-dark.png, nothing focused (markers faded). Prints where the first line sits
    /// (design/KIT.md "Notes canvas text": x 221, under the meeting header).
    @MainActor private static func captureCanvas(model: AppModel, to dir: String) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else { return }
        model.sidebar = .all
        model.sidebarVisible = true
        main.setContentSize(Metric.windowDefault)
        model.selection = model.meetings.first { $0.id == "seed-acme-kickoff" }?.id ?? model.meetings.first?.id
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/canvas-\(mode).png", window: main)
        }
        if let editor = main.contentView.flatMap(NotesTextView.find), let m = editor.firstLineMetrics() {
            print("SNAPSHOT canvas first line: x \(m.x), line top \(m.lineTop), cap top \(m.capTop), TextKit 2 \(editor.isTextKit2)")
        }
        func editors(_ v: NSView) -> [NotesTextView] { ((v as? NotesTextView).map { [$0] } ?? []) + v.subviews.flatMap(editors) }
        // Picking another meeting replaces the editor.
        model.selection = model.meetings.last?.id
        try? await Task.sleep(for: .seconds(0.8))
        let open = main.contentView.map(editors) ?? []
        let other = model.meetings.last?.notes ?? ""
        print("SNAPSHOT canvas after picking another meeting: \(open.count) editor, showing it: \(open.map(\.string) == [other])")
        model.selection = nil
    }

    /// The Summary view (⌘1) at 910 × 600:
    ///   summary-<mode>.png        the recorded seed meeting: headings, bullets, bold, "## Imported summary"
    ///   summary-empty-<mode>.png  a meeting with no summary yet
    @MainActor private static func captureSummary(model: AppModel, to dir: String) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else { return }
        model.sidebar = .all
        model.sidebarVisible = true
        main.setContentSize(Metric.windowDefault)
        let empty = model.meetings.first { $0.id != SeedData.recordedID && $0.summary.isEmpty }?.id
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            model.selection = SeedData.recordedID
            model.show(.summary)
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/summary-\(mode).png", window: main)
            model.selection = empty
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/summary-empty-\(mode).png", window: main)
        }
        model.show(.notes)
        model.selection = nil
    }

    /// The Transcript view (⌘3) at 910 × 600:
    ///   transcript-<mode>.png           the recorded seed meeting, low-confidence words underlined
    ///   transcript-selected-<mode>.png  after a click on a word: the word filled, its time in the strip
    ///   transcript-empty-<mode>.png     a meeting with no transcript yet
    @MainActor private static func captureTranscript(model: AppModel, to dir: String) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else { return }
        model.sidebar = .all
        model.sidebarVisible = true
        main.setContentSize(Metric.windowDefault)
        let empty = model.meetings.first { $0.id != SeedData.recordedID }?.id
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            // Open the meeting on My notes first, then switch, as ⌘3 does.
            model.selection = SeedData.recordedID
            model.show(.notes)
            try? await Task.sleep(for: .seconds(0.8))
            model.show(.transcript)
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/transcript-\(mode).png", window: main)
            // A click on the second block's timestamp (the end of its label row), then on a
            // word in its first line, found from the block's layout frames.
            let row = GridProbes.shared.probes["area:transcriptLabel-1"]
            let text = GridProbes.shared.probes["area:transcriptText-1"]
            if let row { click(main, at: CGPoint(x: row.x + row.width - Metric.timestampGap, y: row.y + row.height / 2)) }
            try? await Task.sleep(for: .seconds(0.4))
            // The second turn starts at 00:14 (SeedData.kickoffTranscript).
            print("SNAPSHOT transcript timestamp click: \(model.lastSeek == 14 ? "PASS" : "FAIL") (seek to \(model.lastSeek.map { "\($0)" } ?? "nothing"))")
            if let text { click(main, at: CGPoint(x: text.x + 4 * Space.xl, y: text.y + KitType.transcript.lineBox / 2)) }
            try? await Task.sleep(for: .seconds(0.6))
            // Any word after the turn's first one.
            let word = model.lastSeek ?? 0
            print("SNAPSHOT transcript word click: \(word > 14 && word < 22 ? "PASS" : "FAIL") (seek to \(word))")
            capture(to: "\(dir)/transcript-selected-\(mode).png", window: main)
            model.selection = empty
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/transcript-empty-\(mode).png", window: main)
        }
        model.show(.notes)
        model.selection = nil
    }

    /// Recording, forced on the recorder with no capture, at 910 × 600:
    ///   recording-<mode>.png     a seeded meeting recording: Stop with the red square, the live
    ///                            wave on the Transcript tab, timestamps in the notes' margin
    ///   transcribing-<mode>.png  after Stop: "Transcribing…" and its bar in the canvas header
    ///   recording-controls-<mode>.png  the recording controls (recording, mic only, paused,
    ///                            audio lost, quiet, a long call)
    ///   permissions-<mode>.png   the permissions sheet
    @MainActor private static func captureRecording(model: AppModel, to dir: String) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else { return }
        model.sidebar = .all
        model.sidebarVisible = true
        main.setContentSize(Metric.windowDefault)
        let id = model.meetings.first { $0.id == "seed-acme-kickoff" }?.id ?? model.meetings.first?.id
        guard let id else { return }
        // Times for the note's lines, a little over half a minute apart, as if typed live.
        model.selection = nil
        try? await Task.sleep(for: .seconds(0.3))
        var times = NoteTimes()
        var so = ""
        for (index, line) in (model.library.readNotes(for: id) ?? "").split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let next = so.isEmpty && index == 0 ? String(line) : so + "\n" + line
            times.update(old: so, new: next, now: Double(index) * 37 + 12)
            so = next
        }
        try? model.library.saveNoteTimes(times, for: id)
        model.selection = id
        model.show(.notes)
        let since = Date().addingTimeInterval(-754)
        let levels: [Float] = [0.08, 0.35, 0.7, 0.25, 0.5]
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            model.recorder.force(.recording(since: since), meetingID: id, levels: levels)
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/recording-\(mode).png", window: main)
            model.recorder.force(.transcribing(progress: 0.45), meetingID: id)
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/transcribing-\(mode).png", window: main)
        }
        model.recorder.force(.idle)
        renderRecordingParts(since: since, levels: levels, to: dir)
        renderMeetingPrompt(to: dir)
        model.selection = nil
    }

    /// The recording controls in their states (recording, mic only, call ended counting
    /// down, paused, audio lost, quiet, a long call), and the permissions sheet, drawn straight from the views like the
    /// brand set: recording-controls-<mode>.png and permissions-<mode>.png.
    @MainActor private static func renderRecordingParts(since: Date, levels: [Float], to dir: String) {
        let meter = LevelMeter(levels: levels)
        for mode in ["light", "dark"] {
            let appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)!
            NSApp.appearance = appearance
            let controls = VStack(alignment: .leading, spacing: Space.lg) {
                RecordingControls(status: .recording(since: since), meter: meter)
                RecordingControls(status: .recording(since: since), callAudioDown: "The call audio device stopped.",
                                  meter: meter)
                RecordingControls(status: .recording(since: since), callEndStopAt: Date().addingTimeInterval(9.5),
                                  meter: meter)
                RecordingControls(status: .paused(elapsed: 754), meter: meter)
                RecordingControls(status: .lost(elapsed: 754, reason: "Couldn't restart the microphone."), meter: meter)
                RecordingControls(status: .recording(since: since), meter: LevelMeter())
                RecordingControls(status: .recording(since: Date().addingTimeInterval(-7199)), meter: meter)
            }
            .padding(Space.xxl)
            .background(Ink.background)
            let sheet = PermissionsView(request: .startRecording, start: {}, cancel: {})
            for (name, view) in [("recording-controls", AnyView(controls)), ("permissions", AnyView(sheet))] {
                let host = NSHostingView(rootView: view)
                host.appearance = appearance
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                var rep: NSBitmapImageRep?
                appearance.performAsCurrentDrawingAppearance {
                    rep = bitmap(pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2), size: host.bounds.size) { rect in
                        NSColor.windowBackgroundColor.setFill()
                        rect.fill()
                        if let context = NSGraphicsContext.current {
                            host.displayIgnoringOpacity(host.bounds, in: context)
                        }
                    }
                }
                write(rep, to: "\(dir)/\(name)-\(mode).png")
            }
        }
    }

    /// A left click at a point in the window's content, from its top left.
    @MainActor private static func click(_ window: NSWindow, at point: CGPoint) {
        let height = window.contentView?.bounds.height ?? 0
        let location = NSPoint(x: point.x, y: height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
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
            let host = NSHostingView(rootView: BrandAboutView())
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

    /// The kit gallery at its full size, drawn straight from the view like the brand set, so
    /// nothing is cut off by the window:
    ///   kit-gallery-<set>-light.png, kit-gallery-<set>-dark.png (set: silvanus or reference)
    @MainActor private static func renderGallery(to dir: String) {
        for mode in ["light", "dark"] {
            let appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)!
            NSApp.appearance = appearance
            let host = NSHostingView(rootView: KitGallery())
            host.appearance = appearance
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            var rep: NSBitmapImageRep?
            appearance.performAsCurrentDrawingAppearance {
                rep = bitmap(pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2), size: host.bounds.size) { _ in
                    if let context = NSGraphicsContext.current {
                        host.displayIgnoringOpacity(host.bounds, in: context)
                    }
                }
            }
            write(rep, to: "\(dir)/kit-gallery-\(ColorSet.active.rawValue)-\(mode).png")
        }
    }

    /// The "Meeting detected" prompt, drawn straight from the view: prompt-<mode>.png.
    @MainActor private static func renderMeetingPrompt(to dir: String) {
        for mode in ["light", "dark"] {
            let appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)!
            NSApp.appearance = appearance
            let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: Space.lg) {
                MeetingPrompt(appName: "Callbox", record: {}, notNow: {})
                MeetingPrompt(appName: nil, record: {}, notNow: {})
            }
                .padding(Space.xxl)
                .background(Ink.background))
            host.appearance = appearance
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            var rep: NSBitmapImageRep?
            appearance.performAsCurrentDrawingAppearance {
                rep = bitmap(pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2), size: host.bounds.size) { rect in
                    NSColor.windowBackgroundColor.setFill()
                    rect.fill()
                    if let context = NSGraphicsContext.current {
                        host.displayIgnoringOpacity(host.bounds, in: context)
                    }
                }
            }
            write(rep, to: "\(dir)/prompt-\(mode).png")
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
    /// caret on the H1 (its markers shown, the others hidden), editor-plain-<mode>.png
    /// with the caret on a plain line (every marker hidden), and editor-find-<mode>.png
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
