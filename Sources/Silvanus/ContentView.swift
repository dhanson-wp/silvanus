import SilvanusKit
import SwiftUI

/// The main window: the kit's frame (DesignKit/Window), with the meeting list in the
/// sidebar and the selected meeting's notes in the canvas.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PaneLayout(sidebarVisible: model.sidebarVisible) {
            SidebarToggleButton(sidebarVisible: model.sidebarVisible, toggle: model.toggleSidebar)
        } sidebar: {
            MeetingList(page: model.sidebar ?? .all)
        } header: {
            // The canvas header's 46 pt band, empty until the header parts arrive. An
            // EmptyView would take no room and let the canvas slide up under the header.
            Color.clear
        } canvas: {
            NotesCanvas()
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
