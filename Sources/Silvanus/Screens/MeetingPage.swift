import SilvanusKit
import SwiftUI

/// The canvas for the open meeting, by the view pill's mode. Summary and My notes start with
/// the meeting header (title and chips). On My notes the header is the top of the notes'
/// scroll content (NotesCanvas); Summary is SummaryView (read-only, same header); Transcript
/// is TranscriptView, without the header.
struct MeetingPage: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting?
    /// The window's open notes (ContentView keeps them across view modes and Settings).
    let documents: OpenNotes

    var body: some View {
        if let meeting {
            switch model.canvasMode {
            case .summary:
                SummaryView(meeting: meeting, header: AnyView(header(meeting)))
            case .notes:
                NotesCanvas(meeting: meeting, documents: documents,
                            header: model.referenceStage ? nil : AnyView(header(meeting)))
            case .transcript:
                MeetingTranscript(meeting: meeting)
            }
        } else {
            Text("Pick a meeting or start one")
                .kitType(.subheading)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        MeetingHeader(title: meeting.displayTitle, date: meeting.info.start, attendees: meeting.info.attendees,
                      folder: meeting.info.folder, folders: model.folders.map(\.name),
                      rename: { model.rename(meeting.id, to: $0) },
                      chooseFolder: { model.setFolder(meeting.id, to: $0) },
                      request: model.headerRequest, handled: model.headerRequestHandled)
            // The notes' scroll view hosts it outside this view's environment.
            .environment(model)
    }
}
