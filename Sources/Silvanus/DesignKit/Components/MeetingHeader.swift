import SwiftUI

/// KIT.md "Meeting header": where the title and chip row sit.
extension Metric {
    /// The title's cap top below the canvas's top (y 65 in the window, under the 46 pt header).
    static let headerTitleCapTop: CGFloat = 65 - headerHeight
    /// From the title's lowest descender to the chip row's top (measured).
    static let chipRowBelowTitle: CGFloat = 15.5
    /// From the chip row's bottom to the canvas body (adapted from 21.5 to the 4 pt rhythm).
    static let bodyBelowChipRow: CGFloat = 20
}

/// The top of a meeting's page, from KIT.md "Meeting header": the title (`title`, 24 bold,
/// one line, truncates with an ellipsis), then a chip row (the date with the attendees count,
/// which opens a list of them, and the folder chip, which opens the folder menu).
///
/// It knows nothing of the editor: the canvas puts it at the top of its scroll content, and
/// it reports renames and folder changes through its closures. Its own leading inset puts the
/// text at x 221 (`Metric.contentX`) when the canvas starts at x 209.
///
/// Click the title (or Tab to it and press Space) to rename the meeting; Return keeps the
/// new title, Escape puts the old one back, and clicking away keeps it. An empty title puts
/// the old one back. Changing a request counter (`renameRequest`, `attendeesRequest`,
/// `newFolderRequest`) does what its menu item asks: Meeting > Rename Meeting…, Show
/// Attendees, and Move to Folder > New Folder….
struct MeetingHeader: View {
    let title: String
    let date: Date
    let attendees: [String]
    let folder: String?
    /// Every folder, for the folder menu.
    var folders: [String] = []
    var rename: (String) -> Void = { _ in }
    var chooseFolder: (String?) -> Void = { _ in }
    var renameRequest = 0
    var attendeesRequest = 0
    var newFolderRequest = 0

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    /// The chip row's top below the canvas's top: under the title's lowest descender.
    static var chipRowTop: CGFloat {
        let title = KitType.title
        return Metric.headerTitleCapTop + title.capHeight - title.nsFont.descender + Metric.chipRowBelowTitle
    }

    /// The whole header's height: the canvas body starts here.
    static var height: CGFloat { chipRowTop + Metric.controlHeight + Metric.bodyBelowChipRow }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
            titleView
                .capTop(Metric.headerTitleCapTop, .title)
            HStack(spacing: Metric.chipSpacing) {
                DateChip(date: Self.dateText(date), attendees: attendees, showRequest: attendeesRequest)
                    .fixedSize()
                FolderChip(folder: folder, folders: folders, newFolderRequest: newFolderRequest, choose: chooseFolder)
                    .layoutPriority(-1)
            }
            .padding(.top, Self.chipRowTop)
        }
        .padding(.horizontal, Metric.contentX - Metric.canvasX)
        .onChange(of: renameRequest) { startEditing() }
    }

    private func startEditing() {
        draft = title
        editing = true
    }

    private func cancel() {
        draft = title
        editing = false
    }

    @ViewBuilder private var titleView: some View {
        if editing {
            TextField("Title", text: $draft)
                .textFieldStyle(.plain)
                .kitType(.title)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .focused($fieldFocused)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
                .onChange(of: fieldFocused) { _, focused in
                    if !focused && editing { commit() }
                }
                .onAppear { fieldFocused = true }
                .accessibilityLabel("Meeting title")
        } else {
            Button(action: startEditing) {
                Text(title)
                    .kitType(.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(MeetingTitleStyle())
            .help(title)
            .accessibilityLabel(title)
            .accessibilityHint("Rename this meeting")
        }
    }

    private func commit() {
        editing = false
        let cleaned = draft.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // An empty title puts the old one back and saves nothing.
        if cleaned.isEmpty || cleaned == title {
            draft = title
            return
        }
        rename(cleaned)
    }

    /// "Nov 6", with the year when it isn't this year's.
    static func dateText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// The meeting title as a button that starts renaming: `Ink.text`, a text cursor on hover,
/// a 2 pt focus ring when focused, 40% when disabled.
struct MeetingTitleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : isFocused ? .focused : .rest)
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.buttonCorner)
            configuration.label
                .foregroundStyle(Ink.text)
                .opacity(state == .disabled ? 0.4 : 1)
                .overlay {
                    if state == .focused {
                        shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing)
                            .padding(-Metric.focusRing * 2)
                    }
                }
                .contentShape(Rectangle())
                .focusEffectDisabled()
                .pointerStyle(.horizontalText)
        }
    }
}
