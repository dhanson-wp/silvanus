import Foundation
import SilvanusKit
import SwiftUI

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case all, starred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Meetings"
        case .starred: "Starred"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray"
        case .starred: "star"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    init(library: MeetingLibrary) {
        self.library = library
        appearance.apply()
    }

    let library: MeetingLibrary
    /// Every meeting on disk, newest first. Setting it rebuilds the sidebar's folders and days.
    var meetings: [Meeting] = [] {
        didSet {
            folders = SidebarFolders.list(meetings)
            // A folder that no longer holds a meeting is gone from the sidebar, so stop showing it.
            if let folder, !folders.contains(where: { $0.name == folder }) {
                self.folder = nil
            } else {
                regroup()
            }
        }
    }
    /// Folders that hold no readable meeting.json.
    var unreadable: [URL] = []
    var sidebar: SidebarItem? = .all
    /// The selected meeting's id. A header request waiting for the old meeting is dropped.
    var selection: String? {
        didSet {
            if selection != oldValue {
                headerRequest = nil
                selectionChanged?(selection)
            }
        }
    }
    /// Called after the selection changes (the notes canvas closes the old meeting's notes).
    @ObservationIgnored var selectionChanged: ((String?) -> Void)?
    /// Called with a meeting's id just before it's trashed, so the notes canvas can save
    /// typing still in it first.
    @ObservationIgnored var beforeTrash: ((String) -> Void)?
    /// The sidebar folder the meeting list shows; nil is All meetings.
    var folder: String? {
        didSet { if folder != oldValue { regroup() } }
    }
    /// When the sidebar last looked at the clock. The sidebar moves it at each midnight, and
    /// the days regroup only when the day changed.
    var now = Date() {
        didSet {
            if !Calendar.current.isDate(now, inSameDayAs: oldValue) { regroup() }
        }
    }
    /// The sidebar's folders, sorted, with their meeting counts. Rebuilt with `meetings`.
    private(set) var folders: [(name: String, count: Int)] = []
    /// The meetings the sidebar lists (the chosen folder's, or every one), grouped by day.
    /// Rebuilt only when the meetings, the folder, or the day change, never on a selection
    /// change, so arrow keys stay fast with hundreds of meetings.
    private(set) var visibleMeetings: [Meeting] = []
    private(set) var dayGroups: [DayGroup] = []
    /// The listed meetings' ids in sidebar order, for the arrow keys.
    private(set) var sidebarOrder: [String] = []
    /// How many times the days were rebuilt. The self-test reads it.
    @ObservationIgnored private(set) var regroupCount = 0
    /// False when the sidebar is hidden (View > Hide Sidebar, ⌃⌘S, or the header button).
    var sidebarVisible = true
    /// What the canvas shows for the open meeting (the view pill, ⌘1, ⌘2, ⌘3). Leaving My
    /// notes saves the typing first, while the editor is still on screen.
    var canvasMode: CanvasMode = .notes {
        willSet { if newValue != canvasMode, canvasMode == .notes { leavingNotes?() } }
    }
    /// True while a meeting records. Nothing sets it until recording is wired in.
    var isRecording = false
    /// False until recording is wired in: Start Recording and Quick Note show disabled.
    let canRecord = false
    /// A Meeting menu item waiting for the meeting header (Rename Meeting…, Show Attendees,
    /// Move to Folder > New Folder…). It stays until the header acts on it, so a request made
    /// from Transcript, where the header isn't on screen, lands once the header appears.
    var headerRequest: HeaderRequest?
    /// How many requests the header has carried out. The self-test reads it.
    @ObservationIgnored private(set) var handledHeaderRequests: [HeaderRequest] = []
    /// True while Settings takes the window (⌘, or the app menu's Settings…). Opening it saves
    /// the notes' typing first, while the editor is still on screen.
    var settingsOpen = false {
        willSet { if newValue, !settingsOpen { leavingNotes?() } }
    }
    /// Saves the open notes now (the notes canvas sets it). Called before My notes leaves
    /// the canvas.
    @ObservationIgnored var leavingNotes: (() -> Void)?
    /// Every meeting Move to Trash was asked for (menu or sidebar). The self-test reads it.
    @ObservationIgnored private(set) var trashRequests: [String] = []
    /// Settings reopens on the last pane. Test and snapshot runs use their own defaults.
    var settingsPane: SettingsPane = SettingsPane(rawValue: AppDefaults.shared.string(forKey: AppDefaults.settingsPaneKey) ?? "") ?? .general {
        didSet { AppDefaults.shared.set(settingsPane.rawValue, forKey: AppDefaults.settingsPaneKey) }
    }
    /// Settings > Appearance. Setting it saves it and applies it to every window.
    var appearance: AppearanceChoice = AppDefaults.appearance {
        didSet {
            AppDefaults.appearance = appearance
            appearance.apply()
        }
    }
    /// Settings > General > Show in Dock. Saved only; no behavior yet.
    var showInDock: Bool = AppDefaults.showInDock {
        didSet { AppDefaults.showInDock = showInDock }
    }
}

extension AppModel {
    /// Seeds when asked (scratch stores only), then reads the meetings from disk.
    convenience init(root: URL) {
        // Test, snapshot, and self-test runs (scratch stores) delete instead of using the real Trash.
        let library = Store.isScratch
            ? MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
            : MeetingLibrary(root: root)
        self.init(library: library)
        SeedData.seedIfRequested(library: library)
        reload()
    }

    /// Hides or shows the sidebar, sliding the canvas with the kit's selection curve.
    func toggleSidebar() {
        // Settings keeps its list on screen; the hide button is its back button then.
        guard !settingsOpen else { return }
        withAnimation(Motion.select) { sidebarVisible.toggle() }
    }

    /// Settings…, ⌘,: Settings takes the canvas column, and the sidebar column shows its list.
    /// `pane` picks the pane to show; nil keeps the last one.
    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        settingsOpen = true
    }

    /// The back button and Escape: back to the meeting.
    func closeSettings() {
        settingsOpen = false
    }

    /// Meeting > Move to Trash (⌘⌫) and the sidebar row's menu. A failure shows the
    /// system's reason, and the meeting stays.
    func trash(_ id: String) {
        trashRequests.append(id)
        do {
            try moveToTrash(id)
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Moves a meeting to the Trash, after its open notes are saved, and reloads.
    func moveToTrash(_ id: String) throws {
        beforeTrash?(id)
        try library.moveToTrash(id)
        if selection == id { selection = nil }
        reload()
    }

    /// The notes canvas saved a meeting's notes: keep the app's copy the same, so nothing
    /// that saves the meeting later writes older notes.
    func notesSaved(_ text: String, for id: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].notes = text
    }

    func reload() {
        let loaded = library.loadAll()
        meetings = loaded.meetings
        unreadable = loaded.unreadable
    }

    private func regroup() {
        regroupCount += 1
        visibleMeetings = SidebarFolders.filter(meetings, folder: folder)
        dayGroups = DayGroups.days(visibleMeetings, now: now, calendar: .current)
        sidebarOrder = dayGroups.flatMap(\.meetings).map(\.id)
    }

    /// Opens a meeting: a click on its row, or Return on the selected one. The canvas shows
    /// the selected meeting; once it has a text view it takes keyboard focus here too.
    func open(_ id: String) {
        selection = id
    }

    /// The open meeting, if any.
    var selectedMeeting: Meeting? {
        guard let selection else { return nil }
        return meetings.first { $0.id == selection }
    }

    /// Switches the canvas, sliding the view pill's segment with the kit's selection curve.
    func show(_ mode: CanvasMode) {
        settingsOpen = false
        withAnimation(Motion.select) { canvasMode = mode }
    }

    /// New Meeting (⌘N, the sidebar's new meeting button): a meeting page for notes, without
    /// recording, filed in the folder the sidebar shows. It opens on My notes.
    @discardableResult
    func newMeeting(now: Date = Date()) -> Meeting? {
        let meeting = Meeting(info: MeetingInfo(title: Meeting.untitled, start: now, folder: folder))
        // The full save is safe here: a new id gets a new folder, so there's nothing to overwrite.
        guard (try? library.save(meeting)) != nil else { return nil }
        settingsOpen = false
        let index = meetings.firstIndex { $0.info.start <= meeting.info.start } ?? meetings.endIndex
        meetings.insert(meeting, at: index)
        open(meeting.id)
        canvasMode = .notes
        return meeting
    }

    /// Renames a meeting on disk and in the sidebar. Spaces are tidied; an empty title is
    /// ignored (the old one stays, nothing is written). The folder on disk keeps its name.
    func rename(_ id: String, to title: String) {
        let cleaned = MeetingTitle.clean(title)
        guard !cleaned.isEmpty else { return }
        update(id) { $0.info.title = cleaned }
    }

    /// Meeting > Rename Meeting…: the open meeting's title turns editable. The header lives
    /// on Summary and My notes, so Transcript switches to My notes first.
    func requestRename() { request(.rename) }

    /// Meeting > Show Attendees: opens the date chip's list of attendees.
    func requestAttendees() { request(.attendees) }

    /// Meeting > Move to Folder > New Folder…: asks for a folder name.
    func requestNewFolder() { request(.newFolder) }

    /// The meeting header calls this once it has acted on `headerRequest`.
    func headerRequestHandled() {
        if let headerRequest { handledHeaderRequests.append(headerRequest) }
        headerRequest = nil
    }

    private func request(_ request: HeaderRequest) {
        headerRequest = request
        if canvasMode == .transcript { show(.notes) }
    }

    /// Files a meeting in a sidebar folder, or takes it out of one (nil).
    func setFolder(_ id: String, to name: String?) {
        let cleaned = name.map(MeetingTitle.clean).flatMap { $0.isEmpty ? nil : $0 }
        update(id) { $0.info.folder = cleaned }
    }

    /// Start Recording (⇧⌘R, the canvas header's Record button). Recording is wired in after
    /// the audio work lands; until then this does nothing.
    func startRecording() {}

    /// Quick Note (⌥⌘N, the canvas header's mic): a new meeting that records right away.
    /// Wired in with recording; until then this does nothing.
    func quickNote() {}

    /// Saves a change to one meeting's details (`meeting.json` only, never the notes or other
    /// files from this copy), then puts it back in `meetings` so the sidebar refreshes. A
    /// failed save changes nothing.
    private func update(_ id: String, _ change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        var meeting = meetings[index]
        change(&meeting)
        guard meeting.info != meetings[index].info, (try? library.saveInfo(meeting)) != nil else { return }
        meetings[index] = meeting
    }
}
