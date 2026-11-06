import SwiftUI

/// KIT.md "Meeting header": the chips' measures.
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
    /// Folder chip: padding 10.5, 6.5 from the icon to the name.
    static let folderChipPadding: CGFloat = 10.5
    static let folderChipIconGap: CGFloat = 6.5
}

/// A meeting header chip: a real button, 28 tall, fully rounded, with a 0.5 pt divider
/// border and KIT.md "Meeting header"'s states. Chips sit on the canvas, so hover uses
/// `controlHover` (`selection` matches the canvas).
///
/// | State | Fill | Text |
/// | rest | none | textSecondary |
/// | hover | controlHover | text |
/// | pressed | controlHover at 80% | text |
/// | focused | 2 pt focus ring | text |
/// | disabled | none | textSecondary at 40% |
///
/// Put the padding in the label: the chips differ. The gallery forces a state with
/// `forcedPartState`.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
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
            case .hover: Ink.controlHover
            case .pressed: Ink.controlHover.opacity(0.8)
            default: .clear
            }
        }

        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        var body: some View {
            let shape = Capsule()
            configuration.label
                .foregroundStyle([.hover, .pressed, .focused].contains(state) ? Ink.text : Ink.textSecondary)
                .opacity(state == .disabled ? 0.4 : 1)
                .frame(height: Metric.controlHeight)
                .background(fill, in: shape)
                .overlay {
                    if ringed {
                        shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing)
                    } else {
                        shape.strokeBorder(Ink.divider, lineWidth: Metric.chipBorder)
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

/// The date chip's label: calendar icon, the date, then the attendees icon and their count.
/// With no attendees it shows the date alone.
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

/// The folder chip's label: 13 pt folder icon, 6.5 gap, the name, padding 10.5. With no
/// folder it reads "Add to folder". The name truncates with an ellipsis.
struct FolderChipLabel: View {
    let folder: String?

    var body: some View {
        HStack(spacing: Metric.folderChipIconGap) {
            KitIconView(.folderChip)
            Text(folder ?? "Add to folder")
                .kitType(.chip)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Metric.folderChipPadding)
    }
}

/// The folder menu's items, shared by the folder chip and Meeting > Move to Folder: each
/// folder (the current one checked), None, and New Folder…. `choose` gets the folder, or nil
/// for None.
struct FolderMenuItems: View {
    let folder: String?
    let folders: [String]
    let choose: (String?) -> Void
    let newFolder: () -> Void

    var body: some View {
        ForEach(folders, id: \.self) { name in
            Toggle(name, isOn: Binding(get: { folder == name }, set: { if $0 { choose(name) } }))
        }
        Toggle("None", isOn: Binding(get: { folder == nil }, set: { if $0 { choose(nil) } }))
        Divider()
        Button("New Folder…", action: newFolder)
    }
}

/// The folder chip, the one place a meeting's folder is set on screen: it opens the folder
/// menu (`FolderMenuItems`). New Folder… asks for a name. A change to `newFolderRequest`
/// (Meeting > Move to Folder > New Folder…) asks too.
struct FolderChip: View {
    let folder: String?
    let folders: [String]
    var newFolderRequest = 0
    let choose: (String?) -> Void

    @State private var naming = false
    @State private var newName = ""

    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Menu {
            FolderMenuItems(folder: folder, folders: folders, choose: choose, newFolder: askForName)
        } label: {
            FolderChipLabel(folder: folder)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChipButtonStyle())
        .help(folder == nil ? "Add this meeting to a folder" : "Move this meeting to another folder")
        .accessibilityLabel(folder.map { "Folder: \($0)" } ?? "Add to folder")
        .onChange(of: newFolderRequest) { askForName() }
        .alert("New Folder", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") { choose(trimmed) }
                .disabled(trimmed.isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The meeting moves into the new folder.")
        }
    }

    private func askForName() {
        newName = ""
        naming = true
    }
}

/// The date chip, with the attendees in a popover: a click lists who was there. A change to
/// `showRequest` (Meeting > Show Attendees) opens it too.
struct DateChip: View {
    let date: String
    let attendees: [String]
    var showRequest = 0

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
        .onChange(of: showRequest) { showing = true }
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
