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
    /// The floating recording pill's window, made once the window is up.
    @State private var pill: RecordingPanel?

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
                             // The Stop look and the wave belong to the meeting being recorded.
                             isRecording: model.isRecording,
                             meter: model.recorder.meetingID == meeting?.id ? model.recorder.meter : nil,
                             transcribing: transcribingProgress,
                             startRecording: recordAction(model.startRecording),
                             quickNote: recordAction(model.quickNote))
            }
        } canvas: {
            if model.settingsOpen {
                SettingsScreen()
            } else {
                MeetingPage(meeting: meeting, documents: documents)
                    .overlay(alignment: .bottom) { banner }
            }
        }
        .sheet(item: $model.permissionsRequest) { request in
            PermissionsView(request: request,
                            start: { model.record(request) },
                            cancel: { model.permissionsRequest = nil })
                .noInitialFocus()
                .fitsContent()
        }
        .task {
            if pill == nil { pill = RecordingPanel(recorder: model.recorder, model: model) }
            // Checks and snapshots drive the recorder themselves.
            if !SelfTest.requested && !Snapshot.requested {
                model.recorder.recoverInterrupted(library: model.library)
            }
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model)
        }
    }

    private var transcribingProgress: Double? {
        if case let .transcribing(progress) = model.recorder.phase { progress } else { nil }
    }

    /// The recorder's banner: a failure with Retry, a warning while recording, or news.
    @ViewBuilder private var banner: some View {
        let recorder = model.recorder
        if let notice = recorder.notice {
            NoticeBanner(message: notice.message,
                         actionTitle: notice.retryMeetingID == nil ? nil : "Retry",
                         action: recorder.retry,
                         dismiss: recorder.dismissNotice)
                .padding(.bottom, Space.md)
        } else if recorder.isRecording, let warning = recorder.warning {
            NoticeBanner(message: warning)
                .padding(.bottom, Space.md)
        }
    }

    /// A recording action, or nil (the control shows disabled) when recording is off.
    private func recordAction(_ action: @escaping () -> Void) -> (() -> Void)? {
        model.canRecord ? action : nil
    }
}
