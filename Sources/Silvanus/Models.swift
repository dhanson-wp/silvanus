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
    var selection: String?
    /// False when the sidebar is hidden (View > Hide Sidebar, ⌃⌘S, or the header button).
    var sidebarVisible = true
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
}
