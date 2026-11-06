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
    init(library: MeetingLibrary) { self.library = library }

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
    /// The selected meeting's id.
    var selection: String?
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
    /// What the canvas shows for the open meeting (the view pill, ⌘1, ⌘2, ⌘3).
    var canvasMode: CanvasMode = .notes
    /// True while a meeting records. Nothing sets it until recording is wired in.
    var isRecording = false
    /// Settings reopens on the last tab. Test and snapshot runs use their own defaults.
    var settingsTab: SettingsTab = SettingsTab(rawValue: AppDefaults.shared.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { AppDefaults.shared.set(settingsTab.rawValue, forKey: "settings.tab") }
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
        withAnimation(Motion.select) { sidebarVisible.toggle() }
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
        withAnimation(Motion.select) { canvasMode = mode }
    }

    /// New Meeting (⌘N, the sidebar's new meeting button): a meeting page for notes, without
    /// recording, filed in the folder the sidebar shows. It opens on My notes.
    @discardableResult
    func newMeeting(now: Date = Date()) -> Meeting? {
        let meeting = Meeting(info: MeetingInfo(title: "", start: now, folder: folder))
        guard (try? library.save(meeting)) != nil else { return nil }
        let index = meetings.firstIndex { $0.info.start <= meeting.info.start } ?? meetings.endIndex
        meetings.insert(meeting, at: index)
        open(meeting.id)
        canvasMode = .notes
        return meeting
    }

    /// Renames a meeting on disk and in the sidebar. Spaces are tidied; an empty title shows
    /// as "Untitled meeting". The folder on disk keeps its name.
    func rename(_ id: String, to title: String) {
        update(id) { $0.info.title = MeetingTitle.clean(title) }
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

    /// Saves a change to one meeting, then puts the saved copy back in `meetings` so the
    /// sidebar refreshes. A failed save changes nothing.
    private func update(_ id: String, _ change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        var meeting = meetings[index]
        change(&meeting)
        guard meeting != meetings[index], (try? library.save(meeting)) != nil else { return }
        meetings[index] = meeting
    }
}
