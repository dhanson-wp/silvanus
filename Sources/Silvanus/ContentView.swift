import SilvanusKit
import SwiftUI

/// The main window: the kit's frame (DesignKit/Window), with the sidebar (Screens/SidebarView),
/// the canvas header (view pill, Quick Note, Start Recording, More), and the open
/// meeting's page (Screens/MeetingPage). While Settings is open, its list takes the sidebar
/// column and the chosen pane the canvas (Screens/SettingsScreen).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// The open notes live as long as the window, so switching view modes or opening
    /// Settings never drops a document with typing on its way to disk.
    @State private var documents = OpenNotes()

    var body: some View {
        @Bindable var model = model
        let meeting = model.selectedMeeting
        // Settings takes the sidebar and canvas columns, and keeps the sidebar on screen.
        PaneLayout(sidebarVisible: model.sidebarVisible || model.settingsOpen) {
            if model.settingsOpen {
                SettingsHeaderRow(back: model.closeSettings)
            } else {
                // Search and Filter join the row when their features land; until then they show disabled.
                SidebarHeaderRow(sidebarVisible: model.sidebarVisible, toggleSidebar: model.toggleSidebar,
                                 newMeeting: { model.newMeeting() })
            }
        } sidebar: {
            if model.settingsOpen {
                SettingsSidebar()
            } else {
                SidebarView(page: model.sidebar ?? .all)
            }
        } header: {
            if model.settingsOpen {
                // Not an empty slot: an empty header drops the header's height.
                Color.clear
            } else {
                CanvasHeader(mode: $model.canvasMode,
                             hasMeeting: meeting != nil,
                             isRecording: model.isRecording,
                             startRecording: recordAction(model.startRecording),
                             quickNote: recordAction(model.quickNote))
            }
        } canvas: {
            if model.settingsOpen {
                SettingsScreen()
            } else {
                MeetingPage(meeting: meeting, documents: documents)
            }
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model)
        }
    }

    /// A recording action, or nil (the control shows disabled) until recording is wired in.
    private func recordAction(_ action: @escaping () -> Void) -> (() -> Void)? {
        model.canRecord ? action : nil
    }
}
