import SilvanusKit
import SwiftUI

/// The canvas for the open meeting, by the view pill's mode. Summary and My notes start with
/// the meeting header (title and chips); the notes canvas and the Summary and Transcript
/// pages fill in below it as they land. Until then each shows its empty state.
struct MeetingPage: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting?

    var body: some View {
        if let meeting {
            switch model.canvasMode {
            case .summary:
                page(meeting) { emptyLine("No summary yet") }
            case .notes:
                // The notes canvas (stream B) puts the header at the top of its own scroll view.
                page(meeting) { Color.clear }
            case .transcript:
                VStack(alignment: .leading, spacing: 0) {
                    emptyLine("No transcript yet")
                        .padding(.top, Space.xl)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Pick a meeting or start one")
                .kitType(.subheading)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func page(_ meeting: Meeting, @ViewBuilder body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetingHeader(title: meeting.displayTitle, date: meeting.info.start, attendees: meeting.info.attendees,
                          folder: meeting.info.folder, folders: model.folders.map(\.name),
                          rename: { model.rename(meeting.id, to: $0) },
                          chooseFolder: { model.setFolder(meeting.id, to: $0) },
                          renameRequest: model.renameRequest, attendeesRequest: model.attendeesRequest,
                          newFolderRequest: model.newFolderRequest)
            body()
            Spacer(minLength: 0)
        }
        // A new meeting gets a fresh header (no rename left half done on the last one).
        .id(meeting.id)
    }

    /// An empty page's one line, in `label` and `textSecondary` at the text's leading edge.
    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .kitType(.label)
            .foregroundStyle(Ink.textSecondary)
            .padding(.horizontal, Metric.contentX - Metric.canvasX)
    }
}
