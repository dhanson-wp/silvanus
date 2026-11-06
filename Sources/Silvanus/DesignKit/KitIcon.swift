import AppKit
import SwiftUI

/// The icon set from design/KIT.md "Icons". Views name a KitIcon, never an SF Symbol,
/// so the whole set can change here. SF Symbols, regular weight, outlined: nothing
/// switches to filled on select.
enum KitIcon: String, CaseIterable {
    case hideSidebar, search, newNote, filter
    case summaryTab, myNotesTab, transcriptTab
    /// The folder icon in its four places: the canvas header chip, a meeting row's folder
    /// line, a folder row, and the meeting header's folder chip (KIT.md "Meeting header").
    case folderHeader, folderLine, folderRow, folderChip
    case more, play, record, quickNoteMic, pause, stop
    case date, attendees, back
    /// The settings list.
    case settingsGeneral, settingsAppearance, settingsAudio, settingsMicrophone
    /// The sidebar: the "All meetings" row and the Folders section's collapse chevron
    /// (drawn pointing right, turned down when the section is open).
    case allMeetings, disclosure

    var symbol: String {
        switch self {
        case .hideSidebar: "sidebar.left"
        case .search: "magnifyingglass"
        case .newNote: "square.and.pencil"
        case .filter: "line.3.horizontal.decrease"
        case .summaryTab: "sparkle"
        case .myNotesTab: "text.alignleft"
        case .transcriptTab, .settingsAudio: "waveform"
        case .folderHeader, .folderLine, .folderRow, .folderChip: "folder"
        case .more: "ellipsis"
        case .play: "play"
        case .record: "record.circle"
        case .quickNoteMic, .settingsMicrophone: "mic"
        case .pause: "pause"
        case .stop: "stop"
        case .date: "calendar"
        case .attendees: "person.2"
        case .back: "chevron.left"
        case .settingsGeneral: "gearshape"
        case .settingsAppearance: "paintbrush"
        case .allMeetings: "tray"
        case .disclosure: "chevron.right"
        }
    }

    /// The drawn size in points, as KIT.md measures it: the glyph's longer side.
    var size: CGFloat {
        switch self {
        case .hideSidebar, .transcriptTab, .folderHeader, .attendees: 15
        case .search, .newNote, .filter, .date, .folderChip: 13
        case .myNotesTab, .record, .pause, .stop: 12
        case .summaryTab, .folderLine, .more, .disclosure: 11
        case .play: 9
        case .folderRow, .quickNoteMic, .back, .settingsGeneral, .settingsAppearance,
             .settingsAudio, .settingsMicrophone, .allMeetings: 14
        }
    }

    /// The symbol point size whose glyph fits `size` on its longer side. Symbols differ in
    /// shape at one point size, so each is measured once at 14 pt (KIT.md's base) and scaled.
    var pointSize: CGFloat { Self.pointSizes[self] ?? size }

    private static let pointSizes: [KitIcon: CGFloat] = {
        let base: CGFloat = 14
        let config = NSImage.SymbolConfiguration(pointSize: base, weight: .regular)
        return Dictionary(uniqueKeysWithValues: allCases.map { icon in
            let drawn = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)?.size ?? NSSize(width: base, height: base)
            let longest = max(drawn.width, drawn.height)
            return (icon, longest > 0 ? base * icon.size / longest : icon.size)
        })
    }()
}

/// A KitIcon at its size, in a `size` × `size` box. Color it with `.foregroundStyle`.
struct KitIconView: View {
    let icon: KitIcon

    init(_ icon: KitIcon) {
        self.icon = icon
    }

    var body: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: icon.pointSize, weight: .regular))
            .frame(width: icon.size, height: icon.size)
            .accessibilityHidden(true)
    }
}
