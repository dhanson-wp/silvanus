import SwiftUI

/// The header family in the kit gallery: the icon button (on the canvas), the Record button
/// and Quick Note mic, the chips, and the view pill in every state, then the canvas header and
/// meeting header put together, with long titles, a long folder name, no folder, and zero
/// attendees, at the default canvas width and at the window's minimum. Fictional words only.
struct HeadersGallery: View {
    private let states: [PartState] = [.rest, .hover, .pressed, .focused, .disabled]

    /// 120 characters: it must end in an ellipsis, never wrap or push the chips down.
    static let longTitle = SidebarGallery.longTitle
    static let longFolder = "Clients and partners, the long list of everyone we work with this year"

    /// The canvas header's width in a 910 pt window, and in a 720 pt one (from x 209).
    private static let defaultWidth = Metric.windowDefault.width - Metric.canvasX
    private static let minimumWidth = Metric.windowMinimum.width - Metric.canvasX

    private static let date = Date(timeIntervalSince1970: 1_794_000_000)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Headers")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            VStack(alignment: .leading, spacing: Space.xxl) {
                Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(states, id: \.self) { state in
                            Text(state.rawValue)
                                .kitType(.meta)
                                .foregroundStyle(Ink.textSecondary)
                        }
                        Text("recording")
                            .kitType(.meta)
                            .foregroundStyle(Ink.textSecondary)
                    }
                    row("Icon button") {
                        IconButton(.newNote, "New Meeting") {}
                    }
                    row("Quick Note", recording: { QuickNoteButton(isRecording: true) {} }) {
                        QuickNoteButton {}
                    }
                    row("Start Recording", recording: { RecordButton(isRecording: true) {} }) {
                        RecordButton {}
                    }
                    row("Date chip") {
                        DateChip(date: MeetingHeader.dateText(Self.date), attendees: ["Sam Rivera", "Priya Natarajan", "Jordan Lee"])
                    }
                    row("No attendees") { DateChip(date: MeetingHeader.dateText(Self.date), attendees: []) }
                    row("Folder chip") { FolderChip(folder: "Clients", folders: ["Clients"]) { _ in } }
                    row("No folder") { FolderChip(folder: nil, folders: []) { _ in } }
                    ForEach(CanvasMode.allCases) { mode in
                        row("View pill, \(mode.title)") { ViewPill(mode: .constant(mode)) }
                    }
                    row("No transcript yet") { ViewPill(mode: .constant(.notes), disabled: [.transcript]) }
                }
                VStack(alignment: .leading, spacing: Space.lg) {
                    sample("Canvas header, 910 pt window") {
                        canvasHeader(width: Self.defaultWidth, mode: .notes)
                    }
                    sample("Canvas header, 720 pt window") {
                        canvasHeader(width: Self.minimumWidth, mode: .transcript)
                    }
                    sample("Canvas header, recording") {
                        canvasHeader(width: Self.minimumWidth, mode: .summary, recording: true)
                    }
                    sample("Canvas header, recording not available yet (as the app ships today)") {
                        CanvasHeader(mode: .constant(.notes))
                            .padding(.leading, Metric.contentX - Metric.canvasX)
                            .frame(width: Self.minimumWidth, height: Metric.headerHeight)
                    }
                    sample("Canvas header, no meeting open") {
                        CanvasHeader(mode: .constant(.notes), hasMeeting: false)
                            .padding(.leading, Metric.contentX - Metric.canvasX)
                            .frame(width: Self.minimumWidth, height: Metric.headerHeight)
                    }
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        sample("Meeting header") {
                            meetingHeader("Acme kickoff", attendees: ["Sam Rivera", "Priya Natarajan", "Jordan Lee"],
                                          folder: "Clients", width: Self.defaultWidth)
                        }
                        sample("Long title and folder, 720 pt window") {
                            meetingHeader(Self.longTitle, attendees: ["Sam Rivera"], folder: Self.longFolder,
                                          width: Self.minimumWidth)
                        }
                        sample("No attendees, no folder") {
                            meetingHeader("Weekly sync", attendees: [], folder: nil, width: Self.minimumWidth)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.lg) {
                        sample("Attendees") { AttendeesList(attendees: ["Sam Rivera", "Priya Natarajan", "Jordan Lee"]) }
                        sample("No attendees") { AttendeesList(attendees: []) }
                    }
                }
            }
            .padding(Space.lg)
            .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.rowCorner))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }

    /// One part across every state column, then (when it has one) its recording state.
    private func row(_ name: String, recording: (() -> some View)? = Optional<() -> EmptyView>.none,
                     @ViewBuilder part: @escaping () -> some View) -> some View {
        GridRow {
            Text(name)
                .kitType(.rowTitle)
                .foregroundStyle(Ink.text)
                .fixedSize()
            ForEach(states, id: \.self) { state in
                part()
                    .fixedSize()
                    .environment(\.onCanvas, true)
                    .environment(\.forcedPartState, state)
                    .disabled(state == .disabled)
            }
            if let recording {
                recording().fixedSize()
            } else {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    private func canvasHeader(width: CGFloat, mode: CanvasMode, recording: Bool = false) -> some View {
        CanvasHeader(mode: .constant(mode), isRecording: recording, startRecording: {}, quickNote: {})
            .padding(.leading, Metric.contentX - Metric.canvasX)
            .frame(width: width, height: Metric.headerHeight)
    }

    private func meetingHeader(_ title: String, attendees: [String], folder: String?, width: CGFloat) -> some View {
        MeetingHeader(title: title, date: Self.date, attendees: attendees, folder: folder,
                      folders: folder.map { [$0] } ?? [])
            .frame(width: width)
    }

    /// A part on the canvas's ground, as the window draws it.
    private func sample(_ name: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(name)
                .kitType(.meta)
                .foregroundStyle(Ink.textSecondary)
            content()
                .background(Ink.canvas)
                .overlay(Rectangle().strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }
}
