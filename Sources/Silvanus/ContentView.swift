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
                            start: { model.record(request, fromSheet: true) },
                            cancel: { model.permissionsRequest = nil })
                .noInitialFocus()
                .fitsContent()
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model)
        }
    }

    private var transcribingProgress: Double? {
        if case let .transcribing(progress) = model.recorder.phase { progress } else { nil }
    }

    /// The recorder's banners: the open meeting's failed transcription (with Retry, until it
    /// works), then the latest failure or news, or a warning while recording.
    @ViewBuilder private var banner: some View {
        let recorder = model.recorder
        let open = model.selection
        VStack(spacing: Space.sm) {
            if let open, let reason = recorder.failedMeetings[open], recorder.notice?.retryMeetingID != open {
                NoticeBanner(message: "Transcription failed. \(reason)", actionTitle: "Retry",
                             action: { recorder.retry(open) })
            }
            latest
        }
        .padding(.bottom, Space.md)
    }

    @ViewBuilder private var latest: some View {
        let recorder = model.recorder
        if let notice = recorder.notice {
            NoticeBanner(message: notice.message,
                         actionTitle: notice.retryMeetingID == nil ? nil : "Retry",
                         action: recorder.retry,
                         dismiss: recorder.dismissNotice)
        } else if recorder.isRecording, let warning = recorder.warning {
            NoticeBanner(message: warning)
        }
    }

    /// A recording action, or nil (the control shows disabled) when recording is off.
    private func recordAction(_ action: @escaping () -> Void) -> (() -> Void)? {
        model.canRecord ? action : nil
    }
}
