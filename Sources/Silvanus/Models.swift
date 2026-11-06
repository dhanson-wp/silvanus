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
    /// Every meeting on disk, newest first.
    var meetings: [Meeting] = []
    /// Folders that hold no readable meeting.json.
    var unreadable: [URL] = []
    var sidebar: SidebarItem? = .all
    /// The selected meeting's id.
    var selection: String? {
        didSet { if selection != oldValue { selectionChanged?(selection) } }
    }
    /// Called after the selection changes (the notes canvas closes the old meeting's notes).
    @ObservationIgnored var selectionChanged: ((String?) -> Void)?
    /// False when the sidebar is hidden (View > Hide Sidebar, ⌃⌘S, or the header button).
    var sidebarVisible = true
    /// Called with a meeting's id just before it's trashed, so the notes canvas can save
    /// typing still in it first.
    @ObservationIgnored var beforeTrash: ((String) -> Void)?
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
}
