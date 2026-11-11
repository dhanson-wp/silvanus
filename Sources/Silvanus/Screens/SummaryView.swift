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
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
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
                                   link: link, header: header, headerHeight: MeetingHeader.height,
                                   accessibilityLabel: "Summary",
                                   locked: (layout.lockedPrefix, layout.lockedSuffix))
                } else if loaded.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Text(emptyLine)
                            .kitType(.label)
                            .foregroundStyle(Ink.textSecondary)
                            .padding(.horizontal, Metric.contentX - Metric.canvasX)
                        Spacer(minLength: 0)
                    }
                } else {
                    MarkdownEditor(text: .constant(loaded.summary), header: header, headerHeight: MeetingHeader.height,
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

    /// The line under the header when there's nothing to show yet.
    private var emptyLine: String {
        switch model.todoStatus[meeting.id] {
        case .writing: AppModel.writingTodos
        case let .failed(reason): AppModel.todoFailure(reason)
        case nil: "No summary yet"
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
