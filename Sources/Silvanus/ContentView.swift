import SilvanusKit
import SwiftUI

/// The main window: the kit's frame (DesignKit/Window), with the sidebar (Screens/SidebarView),
/// the canvas header (view pill, Quick Note, Start Recording, More), and the open
/// meeting's page (Screens/MeetingPage).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        let meeting = model.selectedMeeting
        PaneLayout(sidebarVisible: model.sidebarVisible) {
            // Search and Filter join the row when their features land; until then they show disabled.
            SidebarHeaderRow(sidebarVisible: model.sidebarVisible, toggleSidebar: model.toggleSidebar,
                             newMeeting: { model.newMeeting() })
        } sidebar: {
            SidebarView(page: model.sidebar ?? .all)
        } header: {
            CanvasHeader(mode: $model.canvasMode,
                         hasMeeting: meeting != nil,
                         isRecording: model.isRecording,
                         startRecording: recordAction(model.startRecording),
                         quickNote: recordAction(model.quickNote))
        } canvas: {
            MeetingPage(meeting: meeting)
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    /// A recording action, or nil (the control shows disabled) until recording is wired in.
    private func recordAction(_ action: @escaping () -> Void) -> (() -> Void)? {
        model.canRecord ? action : nil
    }
}
