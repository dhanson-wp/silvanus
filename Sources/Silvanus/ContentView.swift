import SilvanusKit
import SwiftUI

/// The main window: the kit's frame (DesignKit/Window), with the meeting list in the
/// sidebar and an empty canvas until the sidebar and canvas parts arrive.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PaneLayout(sidebarVisible: model.sidebarVisible) {
            SidebarToggleButton(sidebarVisible: model.sidebarVisible, toggle: model.toggleSidebar)
        } sidebar: {
            MeetingList(page: model.sidebar ?? .all)
        } header: {
            EmptyView()
        } canvas: {
            Color.clear
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}

/// The sidebar's meeting list, in simple rows until the kit's sidebar parts replace it.
struct MeetingList: View {
    @Environment(AppModel.self) private var model
    let page: SidebarItem

    /// Nothing is starred yet: starring arrives with the meeting type.
    private var visible: [Meeting] {
        page == .starred ? [] : model.meetings
    }

    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selection) { meeting in
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                Text(meeting.info.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(meeting.id)
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No Meetings",
                    systemImage: page.symbol,
                    description: Text("Meetings you record show up here.")
                )
            }
        }
    }
}
