import SwiftUI

/// KIT.md "Meeting header" and "Canvas header": the chips' measures.
extension Metric {
    /// Chips are 28 tall and fully rounded, with a 0.5 pt divider border.
    static let chipBorder: CGFloat = 0.5
    /// Between chips in the meeting header's chip row.
    static let chipSpacing: CGFloat = 10
    /// Date chip: padding 14 leading and 10.5 trailing; 5.5 from the calendar icon to the
    /// date, 8 from the date to the attendees icon, 4.5 from that icon to the count.
    static let dateChipLeading: CGFloat = 14
    static let dateChipTrailing: CGFloat = 10.5
    static let dateChipIconGap: CGFloat = 5.5
    static let dateChipAttendeesGap: CGFloat = 8
    static let dateChipCountGap: CGFloat = 4.5
    /// Folder chip in the meeting header: padding 10.5, 6.5 from the icon to the name.
    static let folderChipPadding: CGFloat = 10.5
    static let folderChipIconGap: CGFloat = 6.5
    /// Folder chip in the canvas header: no border, 5.5 from its 15 pt icon to the name.
    static let headerFolderIconGap: CGFloat = 5.5
}

/// A chip: a real button with KIT.md "Meeting header"'s states.
///
/// | State | Fill | Text |
/// | rest | none | textSecondary |
/// | hover | selection | text |
/// | pressed | selection at 80% | text |
/// | focused | 2 pt focus ring | text |
/// | disabled | none | textSecondary at 40% |
///
/// `.bordered` is the meeting header's chip (fully rounded, 0.5 pt divider border);
/// `.plain` is the canvas header's folder chip (no border, corner 7 like an icon button).
/// Put the padding in the label: the chips differ. The gallery forces a state with
/// `forcedPartState`.
struct ChipButtonStyle: ButtonStyle {
    enum Kind { case bordered, plain }
    var kind: Kind = .bordered

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, kind: kind)
    }

    private struct Content: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : configuration.isPressed ? .pressed
                : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var fill: Color {
            switch state {
            case .hover: Ink.selection
            case .pressed: Ink.selection.opacity(0.8)
            default: .clear
            }
        }

        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        private var shape: AnyShape {
            kind == .bordered ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Metric.iconButtonCorner))
        }

        var body: some View {
            configuration.label
                .foregroundStyle([.hover, .pressed, .focused].contains(state) ? Ink.text : Ink.textSecondary)
                .opacity(state == .disabled ? 0.4 : 1)
                .frame(height: Metric.controlHeight)
                .background(fill, in: shape)
                .overlay {
                    if ringed {
                        shape.stroke(Ink.focus, lineWidth: Metric.focusRing)
                    } else if kind == .bordered {
                        Capsule().strokeBorder(Ink.divider, lineWidth: Metric.chipBorder)
                    }
                }
                .contentShape(shape)
                .focusEffectDisabled()
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
        }
    }
}

/// The meeting header's date chip label: calendar icon, the date, then the attendees icon and
/// their count. With no attendees it shows the date alone.
struct DateChipLabel: View {
    let date: String
    let attendees: Int

    var body: some View {
        HStack(spacing: 0) {
            KitIconView(.date)
            Text(date)
                .kitType(.chip)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, Metric.dateChipIconGap)
            if attendees > 0 {
                KitIconView(.attendees)
                    .padding(.leading, Metric.dateChipAttendeesGap)
                Text(attendees.formatted())
                    .kitType(.chip)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, Metric.dateChipCountGap)
            }
        }
        .padding(.leading, Metric.dateChipLeading)
        .padding(.trailing, Metric.dateChipTrailing)
    }
}

/// A folder chip's label. `.bordered` (meeting header): 13 pt folder icon, 6.5 gap, the name,
/// padding 10.5; with no folder it reads "Add to folder". `.plain` (canvas header): 15 pt icon,
/// 5.5 gap, the name; with no folder the icon alone. The name truncates with an ellipsis.
struct FolderChipLabel: View {
    let folder: String?
    var kind: ChipButtonStyle.Kind = .bordered

    var body: some View {
        HStack(spacing: kind == .bordered ? Metric.folderChipIconGap : Metric.headerFolderIconGap) {
            KitIconView(kind == .bordered ? .folderChip : .folderHeader)
            if let text = folder ?? (kind == .bordered ? "Add to folder" : nil) {
                Text(text)
                    .kitType(.chip)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, kind == .bordered ? Metric.folderChipPadding : (Metric.iconButton - KitIcon.folderHeader.size) / 2)
    }
}

/// A folder chip that opens the folder menu: each folder (the current one checked), Remove
/// from Folder, and New Folder…, which asks for a name. `choose` gets the new folder, or nil
/// to take the meeting out of its folder.
struct FolderChip: View {
    let folder: String?
    let folders: [String]
    var kind: ChipButtonStyle.Kind = .bordered
    let choose: (String?) -> Void

    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            ForEach(folders, id: \.self) { name in
                Toggle(name, isOn: Binding(get: { folder == name }, set: { if $0 { choose(name) } }))
            }
            if !folders.isEmpty { Divider() }
            if folder != nil {
                Button("Remove from Folder") { choose(nil) }
            }
            Button("New Folder…") {
                newName = ""
                naming = true
            }
        } label: {
            FolderChipLabel(folder: folder, kind: kind)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChipButtonStyle(kind: kind))
        .help(folder == nil ? "Add this meeting to a folder" : "Move this meeting to another folder")
        .accessibilityLabel(folder.map { "Folder: \($0)" } ?? "Add to folder")
        .alert("New Folder", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { choose(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The meeting moves into the new folder.")
        }
    }
}

/// The date chip, with the attendees in a popover: a click lists who was there.
struct DateChip: View {
    let date: String
    let attendees: [String]

    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            DateChipLabel(date: date, attendees: attendees.count)
        }
        .buttonStyle(ChipButtonStyle())
        .help(attendees.isEmpty ? "No attendees" : "Show who was there")
        .accessibilityLabel(accessibilityText)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            AttendeesList(attendees: attendees)
        }
    }

    private var accessibilityText: String {
        attendees.isEmpty ? "\(date), no attendees"
            : "\(date), \(attendees.count) \(attendees.count == 1 ? "attendee" : "attendees")"
    }
}

/// The attendees popover: a heading, then one name per line.
struct AttendeesList: View {
    let attendees: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Attendees")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
                .accessibilityAddTraits(.isHeader)
            if attendees.isEmpty {
                Text("No attendees")
                    .kitType(.rowTitle)
                    .foregroundStyle(Ink.textSecondary)
            }
            ForEach(Array(attendees.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .kitType(.rowTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(Space.md)
        .frame(minWidth: Space.section * 6, alignment: .leading)
    }
}
