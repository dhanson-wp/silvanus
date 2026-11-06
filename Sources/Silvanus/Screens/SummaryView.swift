import SilvanusKit
import SwiftUI

/// Summary (⌘1, the view pill): the open meeting's `summary.md`, read through
/// `MeetingLibrary`, drawn with the notes canvas's Markdown styling but read-only
/// (selectable, copyable, ⌘F finds). The meeting header is the top of the scroll content,
/// as on My notes, under the 46 pt canvas header. There is no save path: this page never
/// writes `summary.md`. Imported meetings show their "## Imported summary" section as is.
/// With no summary, one line says so under the header.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    let header: AnyView
    /// The text the page was read for (nil while the file is being read).
    @State private var loaded: (id: String, text: String)?

    var body: some View {
        Group {
            if let loaded, loaded.id == meeting.id {
                if loaded.text.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Text("No summary yet")
                            .kitType(.label)
                            .foregroundStyle(Ink.textSecondary)
                            .padding(.horizontal, Metric.contentX - Metric.canvasX)
                        Spacer(minLength: 0)
                    }
                } else {
                    MarkdownEditor(text: .constant(loaded.text), header: header, headerHeight: MeetingHeader.height,
                                   accessibilityLabel: "Summary", readOnly: true)
                }
            } else {
                Color.clear
            }
        }
        // A new meeting gets a fresh page (and a fresh header).
        .id(meeting.id)
        .task(id: meeting.id) {
            loaded = (meeting.id, model.library.readSummary(id: meeting.id) ?? meeting.summary)
        }
    }
}
