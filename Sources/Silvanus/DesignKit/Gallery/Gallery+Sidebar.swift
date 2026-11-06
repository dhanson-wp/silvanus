import SwiftUI

/// The sidebar family in the kit gallery: every part in every state, each on the sidebar's
/// ground at the sidebar's width, then a small sidebar put together from them and its empty
/// states. Fictional words only.
struct SidebarGallery: View {
    private struct Column: Identifiable {
        let name: String
        let state: PartState
        var active = true
        var id: String { name }
    }

    private let columns = [
        Column(name: "rest", state: .rest),
        Column(name: "hover", state: .hover),
        Column(name: "pressed", state: .pressed),
        Column(name: "selected", state: .selected),
        Column(name: "selected, inactive", state: .selected, active: false),
        Column(name: "focused", state: .focused),
        Column(name: "disabled", state: .disabled),
    ]

    /// 120 characters: it must end in an ellipsis, never wrap or push the time down.
    static let longTitle = "Quarterly planning review with Sam Rivera, Priya Natarajan, and Jordan Lee on the launch timeline, budget, and new hires"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Sidebar")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            VStack(alignment: .leading, spacing: Space.xxl) {
                Grid(alignment: .topLeading, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(columns) { column in
                            Text(column.name)
                                .kitType(.meta)
                                .foregroundStyle(Ink.textSecondary)
                        }
                    }
                    row("Header row") {
                        SidebarHeaderRow(sidebarVisible: true, toggleSidebar: {}, search: {}, newMeeting: {}, filter: {})
                            .frame(height: Metric.headerHeight)
                    }
                    row("Meeting row") { meeting("Acme kickoff", time: "9:30 AM") }
                    row("With folder line") { meeting("Weekly sync", time: "2:00 PM", folder: "Team") }
                    row("Long title") { meeting(Self.longTitle, time: "11:15 AM", folder: "Clients and partners, the long list") }
                    row("Folder row") { folder("Clients", count: 12) }
                    row("All meetings") { folder("All meetings", icon: .allMeetings) }
                    row("Section header") {
                        Button {} label: { SidebarSectionHeader(title: "Folders", isOpen: true) }
                            .buttonStyle(SidebarRowStyle(isSelected: false))
                    }
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    sample("Sidebar") { sampleSidebar }
                    sample("No meetings") {
                        SidebarAccentRule()
                        SidebarEmptyNote(title: "No meetings yet", hint: "Click Start Recording to add one.")
                    }
                    sample("Empty folder") {
                        SidebarAccentRule()
                        SidebarEmptyNote(title: "No meetings in this folder")
                    }
                }
            }
            .padding(Space.lg)
            .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.rowCorner))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }

    /// One part across every state column.
    private func row(_ name: String, @ViewBuilder part: @escaping () -> some View) -> some View {
        GridRow {
            Text(name)
                .kitType(.rowTitle)
                .foregroundStyle(Ink.text)
                .fixedSize()
            ForEach(columns) { column in
                part()
                    .frame(width: Metric.sidebarWidth)
                    .background(Ink.sidebar)
                    .environment(\.forcedPartState, column.state)
                    .environment(\.appearsActive, column.active)
                    .disabled(column.state == .disabled)
            }
        }
    }

    private func meeting(_ title: String, time: String, folder: String? = nil, selected: Bool = false) -> some View {
        Button {} label: { SidebarMeetingRow(title: title, time: time, folder: folder) }
            .buttonStyle(SidebarRowStyle(isSelected: selected))
    }

    private func folder(_ title: String, icon: KitIcon = .folderRow, count: Int? = nil, selected: Bool = false) -> some View {
        Button {} label: { SidebarFolderRow(title: title, icon: icon, count: count) }
            .buttonStyle(SidebarRowStyle(isSelected: selected))
    }

    /// A sidebar's top as the window draws it: the header band, then the parts.
    private func sample(_ name: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(name)
                .kitType(.meta)
                .foregroundStyle(Ink.textSecondary)
            VStack(spacing: 0, content: content)
                .padding(.top, Metric.headerHeight)
                .frame(width: Metric.sidebarWidth, alignment: .top)
                .background(Ink.sidebar)
                .environment(\.appearsActive, true)
        }
    }

    @ViewBuilder private var sampleSidebar: some View {
        SidebarAccentRule()
        SidebarDayHeading("Today")
        meeting("Hiring plan", time: "10:00 AM", selected: true)
        meeting("Acme kickoff", time: "9:00 AM", folder: "Clients")
        SidebarDayHeading("Mon, Nov 2")
        meeting("Budget review", time: "3:30 PM", folder: "Team")
        SidebarDivider()
            .padding(.bottom, Space.xs)
        Button {} label: { SidebarSectionHeader(title: "Folders", isOpen: true) }
            .buttonStyle(SidebarRowStyle(isSelected: false))
        folder("All meetings", icon: .allMeetings, selected: true)
        folder("Clients", count: 1)
        folder("Team", count: 2)
    }
}
