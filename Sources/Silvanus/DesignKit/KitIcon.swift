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
    /// The recording controls' Pause, Resume (and Retry), and Stop: filled, as in the design.
    case barPause, barResume, barStop
    case date, attendees, back
    /// The settings list.
    case settingsGeneral, settingsAppearance, settingsAudio, settingsMicrophone, settingsAbout, settingsSummaries
    /// The sidebar: the "All meetings" row and the Folders section's collapse chevron
    /// (drawn pointing right, turned down when the section is open).
    case allMeetings, disclosure
    case todos, todoOpen, todoDone, todoNew
    case home

    var symbol: String {
        switch self {
        case .hideSidebar: "sidebar.left"
        case .search: "magnifyingglass"
        case .newNote: "square.and.pencil"
        case .filter: "line.3.horizontal.decrease"
        case .summaryTab, .settingsSummaries: "sparkle"
        case .myNotesTab: "text.alignleft"
        case .transcriptTab, .settingsAudio: "waveform"
        case .folderHeader, .folderLine, .folderRow, .folderChip: "folder"
        case .more: "ellipsis"
        case .play: "play"
        case .record: "record.circle"
        case .quickNoteMic, .settingsMicrophone: "mic"
        case .pause: "pause"
        case .stop: "stop"
        case .barPause: "pause.fill"
        case .barResume: "play.fill"
        case .barStop: "stop.fill"
        case .date: "calendar"
        case .attendees: "person.2"
        case .back: "chevron.left"
        case .settingsGeneral: "gearshape"
        case .settingsAppearance: "paintbrush"
        case .settingsAbout: "info.circle"
        case .allMeetings: "tray"
        case .disclosure: "chevron.right"
        case .todos: "checklist"
        case .todoOpen: "square"
        case .todoDone: "checkmark.square.fill"
        case .todoNew: "plus"
        case .home: "house"
        }
    }

    /// The drawn size in points, as KIT.md measures it: the ink's longer side, which is its
    /// width for every glyph in the set that's wider than tall (the reference was measured
    /// across, with `cols`).
    var size: CGFloat {
        switch self {
        case .hideSidebar, .transcriptTab, .folderHeader, .attendees: 15
        case .search, .newNote, .filter, .date, .folderChip: 13
        case .myNotesTab, .record, .pause, .stop: 12
        case .summaryTab, .folderLine, .more, .disclosure: 11
        case .play, .barPause, .barResume: 9
        case .barStop: 7
        case .folderRow, .quickNoteMic, .back, .settingsGeneral, .settingsAppearance,
             .settingsAudio, .settingsMicrophone, .settingsAbout, .settingsSummaries, .allMeetings,
             .todos, .todoOpen, .todoDone, .home: 14
        case .todoNew: 12
        }
    }

    /// The symbol point size whose ink fits `size` on its longer side. Symbols differ in
    /// shape at one point size, so each is drawn once at 14 pt (KIT.md's base) and its ink
    /// measured. (The image's own size has 2 to 4 pt of padding around the ink; sizing by it
    /// drew a folder line icon 9 wide where KIT.md measures 11.)
    var pointSize: CGFloat { Self.pointSizes[self] ?? size }

    private static let pointSizes: [KitIcon: CGFloat] = {
        let base: CGFloat = 14
        return Dictionary(uniqueKeysWithValues: allCases.map { icon in
            let longest = inkSize(icon.symbol, pointSize: base).map { max($0.width, $0.height) } ?? 0
            return (icon, longest > 0 ? base * icon.size / longest : icon.size)
        })
    }()

    /// The bounds of a symbol's ink at a point size, drawn at 4x.
    private static func inkSize(_ symbol: String, pointSize: CGFloat) -> CGSize? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let scale: CGFloat = 4
        let width = Int(ceil(image.size.width * scale)), height = Int(ceil(image.size.height * scale))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 60 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return CGSize(width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
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
