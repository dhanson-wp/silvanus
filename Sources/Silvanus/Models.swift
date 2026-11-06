import Foundation

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
    /// Meeting titles, a stand-in until the real meeting type and the folder
    /// store arrive. Empty, so every page shows its empty state.
    var meetings: [String] = []
    var sidebar: SidebarItem? = .all
    var selection: String?
    /// Settings reopens on the last tab. Test and snapshot runs use their own defaults.
    var settingsTab: SettingsTab = SettingsTab(rawValue: AppDefaults.shared.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { AppDefaults.shared.set(settingsTab.rawValue, forKey: "settings.tab") }
    }
}
