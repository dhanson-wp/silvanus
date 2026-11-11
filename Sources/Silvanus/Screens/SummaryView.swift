import SilvanusKit
import SwiftUI

/// Summary (⌘1, the view pill): the open meeting's to-dos (`todo.md`) and summary
/// (`summary.md`), read through `MeetingLibrary` and drawn with the notes canvas's Markdown
/// styling. The meeting header is the top of the scroll content, as on My notes, under the
/// 46 pt canvas header.
///
/// With to-dos, the page is one text: a To-dos heading, the list, then the summary. Only
/// the list can be changed (tick a box, edit a line, add one); it's saved to `todo.md` as
/// typing pauses. The heading and the summary are locked, and `summary.md` is never
/// written. Without to-dos the summary is read-only (selectable, copyable, ⌘F finds), and
/// with neither, one line says so, or says the to-dos are being written.
///
/// In every layout the header ends with the Write row (`SummaryActions`): the Write Summary
/// and Write To-dos buttons, and beside them why the last try failed, if it did.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    /// The meeting header (title and chips); the page adds the Write row under it.
    let header: AnyView
    /// What the page was read for (nil while the files are being read).
    @State private var loaded: Loaded?
    /// Reaches the editor, to select a to-do just made with Meeting > New To-do.
    @State private var link = EditorLink()

    private struct Loaded {
        var id: String
        var summary: String
        /// The whole page's text when the meeting has to-dos; nil when it has none.
        var page: String?
    }

    var body: some View {
        Group {
            if let loaded, loaded.id == meeting.id {
                if let page = loaded.page {
                    let layout = TodoPage(summary: loaded.summary)
                    MarkdownEditor(text: Binding(get: { page }, set: { save($0, layout: layout) }),
                                   link: link, header: fullHeader, headerHeight: SummaryActions.headerHeight,
                                   accessibilityLabel: "Summary",
                                   locked: (layout.lockedPrefix, layout.lockedSuffix))
                } else if loaded.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        fullHeader
                        Text(emptyLine)
                            .kitType(.label)
                            .foregroundStyle(Ink.textSecondary)
                            .padding(.horizontal, Metric.contentX - Metric.canvasX)
                        Spacer(minLength: 0)
                    }
                } else {
                    MarkdownEditor(text: .constant(loaded.summary), header: fullHeader, headerHeight: SummaryActions.headerHeight,
                                   accessibilityLabel: "Summary", readOnly: true)
                }
            } else {
                Color.clear
            }
        }
        // A new meeting gets a fresh page (and a fresh header); so does a list that appears or goes.
        .id("\(meeting.id)-\(loaded?.page == nil ? "summary" : "todos")")
        .task(id: "\(meeting.id)-\(model.todoRevision)") {
            load()
            await selectNewTodo()
        }
    }

    /// The meeting header with the Write row under it, `SummaryActions.headerHeight` tall.
    private var fullHeader: AnyView {
        AnyView(VStack(spacing: 0) {
            header
            // The editor's scroll view hosts it outside this view's environment.
            SummaryActions(meetingID: meeting.id).environment(model)
        })
    }

    /// The line under the header when there's nothing to show yet. A failure is in the Write row.
    private var emptyLine: String {
        switch (model.summaryStatus[meeting.id], model.todoStatus[meeting.id]) {
        case (_, .writing): AppModel.writingTodos
        case (.writing, _): AppModel.writingSummary
        default: "No summary yet"
        }
    }

    private func load() {
        let summary = model.library.readSummary(id: meeting.id) ?? meeting.summary
        let todo = model.library.readTodo(id: meeting.id) ?? meeting.todo
        let hasTodos = !todo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        loaded = Loaded(id: meeting.id, summary: summary, page: hasTodos ? TodoPage(summary: summary).text(todo: todo) : nil)
    }

    /// Meeting > New To-do: once the editor shows the list, select the new to-do's words
    /// (the last "New to-do" before the summary) so typing replaces them.
    private func selectNewTodo() async {
        guard model.todoToSelect == meeting.id, let page = loaded?.page else { return }
        model.todoToSelect = nil
        for _ in 0..<20 where link.textView?.string != page { try? await Task.sleep(for: .milliseconds(50)) }
        guard let view = link.textView, view.string == page else { return }
        let listEnd = (page as NSString).length - TodoPage(summary: loaded?.summary ?? "").lockedSuffix
        let range = (page as NSString).range(of: AppModel.newTodoText, options: .backwards, range: NSRange(location: 0, length: listEnd))
        guard range.location != NSNotFound else { return }
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(range)
        view.scrollRangeToVisible(range)
    }

    /// The editor's text changed: keep it, and write the list part to `todo.md`.
    private func save(_ text: String, layout: TodoPage) {
        guard loaded?.id == meeting.id, let todo = layout.todo(in: text) else { return }
        loaded?.page = text
        do {
            try model.library.saveTodo(todo, for: meeting.id)
            model.todoSaved(todo, for: meeting.id)
        } catch {
            print("TODOS couldn't save \(meeting.id): \(error.localizedDescription)")
        }
    }
}

/// The Write row, the last part of Summary's header: Write Summary and Write To-dos
/// (`KitButtonStyle`), starting at the title's left edge, and beside them why the last try
/// failed ("Couldn't write the summary: …"), in `Ink.textSecondary`, a line each, with the
/// whole reason in its hover help. The buttons' rule is `AppModel.writeButton`.
struct SummaryActions: View {
    @Environment(AppModel.self) private var model
    let meetingID: String

    /// The row's height: the buttons, then the same gap to the body as under the chip row.
    static var height: CGFloat { Metric.settingsButtonHeight + Metric.bodyBelowChipRow }
    /// Summary's whole header: the meeting header, then this row.
    static var headerHeight: CGFloat { MeetingHeader.height + height }

    var body: some View {
        let failures = model.writeFailures(for: meetingID)
        HStack(spacing: Space.sm) {
            ForEach([AppModel.WriteKind.summary, .todos], id: \.self) { kind in
                let button = model.writeButton(kind, for: meetingID)
                Button(button.label) { model.pressWrite(kind, for: meetingID) }
                    .buttonStyle(KitButtonStyle())
                    .disabled(!button.isEnabled)
                    .help(button.help)
                    .accessibilityLabel(button.label == AppModel.writing ? "\(kind.title), \(button.label)" : button.label)
                    .accessibilityHint(button.hint)
                    .fixedSize()
            }
            if !failures.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(failures, id: \.self) { line in
                        Text(line)
                            .kitType(.label)
                            .foregroundStyle(Ink.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(line)
                    }
                }
                .padding(.leading, Space.xs)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Metric.settingsButtonHeight)
        .padding(.bottom, Metric.bodyBelowChipRow)
        .padding(.horizontal, Metric.contentX - Metric.canvasX)
    }
}
