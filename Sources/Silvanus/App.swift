import AppKit
import SilvanusKit
import SwiftUI

// Silvanus
//   Silvanus                      the app
//   APP_STORE=<dir> Silvanus      use another meetings folder (tests, experiments)
//   APP_SEED=1 APP_STORE=/tmp/<dir> Silvanus   fill an empty /tmp store with fictional meetings
//   APP_IMPORT_GRANOLA=<dir> APP_STORE=/tmp/<dir> Silvanus   import the Granola archive, print the counts, quit
//   APP_SNAPSHOT=<dir> Silvanus   save a PNG of every sidebar page and Settings pane in light and dark mode, then quit
//   Silvanus --selftest           run the self-test on a /tmp folder and quit with 0 or 1 (tools/selftest.sh)
//   APP_KIT_GALLERY=1 Silvanus    show the design kit's gallery instead of the pages (DesignKit/KitGallery.swift);
//                                 APP_COLORS=reference draws the kit in the reference colors
//   APP_GRID=1 Silvanus           draw the 8 pt grid and the layout probes over the window
//   APP_EDITOR_SPIKE=1 Silvanus   open the native editor spike (Editor/EditorSpikeWindow.swift);
//                                 APP_EDITOR_CHECK=1 and APP_EDITOR_BENCH=1 run its checks and benchmark headless
//   APP_TRANSCRIPT_BENCH=1 APP_STORE=/tmp/<dir> Silvanus   time a 20,000-word transcript opening and scrolling, quit
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
                .noInitialFocus()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .windowChrome()
        }
        // The kit draws the chrome (DesignKit/Window). Size with defaultSize, not a fixed
        // frame: with a hidden title bar a fixed frame grows by the title bar's height.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(Metric.windowDefault)
        .commands {
            SidebarCommand(model: model)
            MeetingCommands(model: model)
            AboutCommand()
            SettingsCommand(model: model)
            // Edit > Find (⌘F), Find and Replace (⌥⌘F), and the rest, for the notes canvas.
            TextEditingCommands()
        }

        Window("About Silvanus", id: "about") {
            BrandAboutView()
                .noInitialFocus()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        // A static image that changes only when recording starts or stops: never a timer or
        // other per-second content (a live label here has hung the menu bar; docs/FIXLOG.md).
        // `isRecording` is stored apart from the recorder's progress for this reason.
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Image(nsImage: model.recorder.isRecording ? Brand.menuBarRecordingGlyph : Brand.menuBarGlyph)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// The menu bar item's menu. While recording: "Recording since 10:30" (static text, never
/// a running timer), Stop, and Open Silvanus. Otherwise Start Recording and Quick Note.
/// Then Quit.
struct MenuBarMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let recorder = model.recorder
        if recorder.isRecording, let since = recorder.since {
            Text(RecordingRules.since(since))
            Button("Stop", action: recorder.stop)
        } else {
            Button("Start Recording") { showWindow(); model.record(.startRecording) }
            Button("Quick Note") { showWindow(); model.record(.quickNote) }
        }
        Divider()
        Button("Open Silvanus", action: showWindow)
        Button("Quit Silvanus") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showWindow() {
        NSApp.activate()
        openWindow(id: "main")
    }
}

/// View > Hide Sidebar and Show Sidebar (⌃⌘S), for the kit's own sidebar.
struct SidebarCommand: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar", action: model.toggleSidebar)
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(model.settingsOpen)
        }
    }
}

/// File > New Meeting (⌘N), Start Recording (⇧⌘R), and Quick Note (⌥⌘N); Meeting > Rename
/// Meeting… (⌃⌘R), Show Attendees (⌃⌘A), Move to Folder, Move to Trash (⌘⌫), Search, and Filter;
/// View > Summary, My notes, and Transcript (⌘1, ⌘2, ⌘3), which switch the canvas like the
/// view pill. Meeting items are disabled with no meeting open; Quick Note while a meeting
/// records; Search and Filter until they land.
struct MeetingCommands: Commands {
    let model: AppModel

    var body: some Commands {
        let meeting = model.selectedMeeting
        // Settings covers the meeting, so its commands wait (New Meeting and the view modes
        // close Settings first instead).
        let noMeeting = meeting == nil || model.settingsOpen
        CommandGroup(replacing: .newItem) {
            Button("New Meeting") { model.newMeeting() }
                .keyboardShortcut("n")
            Button(model.isRecording ? "Stop" : "Start Recording", action: model.startRecording)
                .keyboardShortcut("r", modifiers: [.shift, .command])
            Button("Quick Note", action: model.quickNote)
                .keyboardShortcut("n", modifiers: [.option, .command])
                .disabled(model.isRecording)
        }
        CommandMenu("Meeting") {
            Button("Rename Meeting…", action: model.requestRename)
                .keyboardShortcut("r", modifiers: [.control, .command])
                .disabled(noMeeting)
            Button("Show Attendees", action: model.requestAttendees)
                .keyboardShortcut("a", modifiers: [.control, .command])
                .disabled(noMeeting)
            Menu("Move to Folder") {
                if let meeting {
                    FolderMenuItems(folder: meeting.info.folder, folders: model.folders.map(\.name),
                                    choose: { model.setFolder(meeting.id, to: $0) },
                                    newFolder: model.requestNewFolder)
                }
            }
            .disabled(noMeeting)
            Divider()
            // ⌘⌫ while typing (the notes, a title being renamed) deletes to the line's start, as
            // in any Mac text field. The notes editor keeps it (NotesTextView); this catches the rest.
            // Off while the open meeting records or transcribes; its tooltip says why.
            Button("Move to Trash") {
                MoveToTrash.perform(model: model, event: NSApp.currentEvent,
                                    responder: NSApp.keyWindow?.firstResponder)
            }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(noMeeting || !(meeting.map { model.canTrash($0.id) } ?? true))
                .help(model.trashHelp(meeting?.id))
            Divider()
            // Placeholders until search and filtering land. No shortcuts yet: ⌘F and ⌥⌘F
            // belong to Edit > Find and Find and Replace in the notes canvas.
            Button("Search") {}
                .disabled(true)
            Button("Filter") {}
                .disabled(true)
        }
        CommandGroup(before: .sidebar) {
            ForEach(CanvasMode.allCases) { mode in
                Button(mode.title) { model.show(mode) }
                    .keyboardShortcut(KeyEquivalent(mode.shortcut))
                    .disabled(meeting == nil)
            }
            Divider()
        }
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

/// Silvanus > Settings… (⌘,) opens Settings inside the main window; View > Close Settings
/// (⌘[) and Escape go back to the meeting.
struct SettingsCommand: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.openSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .sidebar) {
            Button("Close Settings", action: model.closeSettings)
                .keyboardShortcut("[")
                .disabled(!model.settingsOpen)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The Granola import, the editor's checks, the benchmark, and headless transcription
        // run before any window opens, then quit.
        if let code = ImportCommand.runIfRequested() { exit(code) }
        if let code = EditorSpike.runHeadlessIfRequested() { exit(code) }
        if let code = TranscriptBench.runHeadlessIfRequested() { exit(code) }
        if let code = TranscribeCommand.runIfRequested() { exit(code) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        EditorSpike.openIfRequested()
    }

    /// ⌘Q while a meeting records asks first: "A meeting is recording. Stop and quit?"
    /// Stop and Quit closes the recording's files (the next launch transcribes it).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Recorder.current?.terminateReply(confirm: QuitPrompt.ask) ?? .terminateNow
    }

    /// Closing the window quits, except while a meeting records: the menu bar item and the
    /// recording pill keep it going, and Stop is still there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(Recorder.current?.isRecording ?? false)
    }

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

/// Meeting > Move to Trash. Its ⌘⌫ shortcut is also every Mac text view's "delete to the
/// line's start": when the keystroke itself (⌘⌫, key code 51) chose the item while text is
/// being edited (the notes, a title being renamed), it deletes instead. Choosing the item
/// with the mouse or the keyboard's menu navigation always trashes.
@MainActor
enum MoveToTrash {
    static func perform(model: AppModel, event: NSEvent?, responder: NSResponder?) {
        if isDeleteShortcut(event), let field = responder as? NSTextView, field.isEditable {
            field.deleteToBeginningOfLine(nil)
        } else if let id = model.selection {
            model.trash(id)
        }
    }

    /// True for a ⌘⌫ key press (no other modifiers).
    static func isDeleteShortcut(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return event.keyCode == 51 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
    }
}

/// The question ⌘Q asks while a meeting records.
@MainActor
enum QuitPrompt {
    static let question = "A meeting is recording. Stop and quit?"

    /// True for Stop and Quit.
    static func ask() -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = "The recording is saved, and it's transcribed the next time Silvanus opens."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
