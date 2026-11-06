import SwiftUI

/// KIT.md "Sidebar header row": after the traffic lights, four 28 × 28 icon buttons (hide
/// sidebar, search, new meeting, filter) centered at x 94, 122, 150, and 178, at y 9.
///
/// It sits in `PaneLayout`'s window header, so the hide sidebar button stays put when the
/// sidebar hides; the other three go with the sidebar. A button whose action is nil is drawn
/// disabled (its feature hasn't landed). View > Hide Sidebar (⌃⌘S) does what the first
/// button does, and File > New Meeting (⌘N) what the third does.
struct SidebarHeaderRow: View {
    var sidebarVisible: Bool
    var toggleSidebar: () -> Void
    var search: (() -> Void)? = nil
    var newMeeting: (() -> Void)? = nil
    var filter: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Metric.sidebarHeaderFirstX - Metric.iconButton / 2, height: Metric.iconButton)
            IconButton(.hideSidebar, sidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                       help: sidebarVisible ? "Hide the sidebar (⌃⌘S)" : "Show the sidebar (⌃⌘S)",
                       action: toggleSidebar)
                .gridProbe("hideSidebar", area: "windowHeader", edge: nil)
            if sidebarVisible {
                IconButton(.search, "Search", help: "Search your meetings", action: search)
                    .gridProbe("search", area: "windowHeader", edge: nil)
                IconButton(.newNote, "New Meeting", help: "Start a meeting page for notes, without recording (⌘N)",
                           action: newMeeting)
                    .gridProbe("newMeeting", area: "windowHeader", edge: nil)
                IconButton(.filter, "Filter", help: "Filter your meetings", action: filter)
                    .gridProbe("filter", area: "windowHeader", edge: nil)
            }
        }
        .padding(.top, Metric.controlY)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
