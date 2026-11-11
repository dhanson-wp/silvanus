import SilvanusKit
import SwiftUI

/// To-dos (the sidebar's To-dos row, ⇧⌘T): a light task manager over every list.
/// First "My to-dos", the ones that belong to no meeting (`todo.md` in the library's
/// root). Then each meeting that still has something to do: its title (click to open its
/// Summary), then its to-dos. A meeting drops off once all its to-dos are done.
///
/// Every to-do can be ticked, reworded (click its words; Return or clicking away saves,
/// and clearing the words deletes it), or deleted from its menu. Each list ends with a New
/// to-do field. Changes go to the list's own `todo.md`, so the meeting's Summary shows the
/// same thing.
struct TodosPage: View {
    @Environment(AppModel.self) private var model

    static let ownTitle = "My to-dos"

    var body: some View {
        let groups = TodoBoard.groups(model.meetings)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("To-dos")
                    .kitType(.title)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Space.xxl)
                list(title: Text(Self.ownTitle).kitType(.settingTitle).foregroundStyle(Ink.text),
                     items: TodoBoard.items(in: model.ownTodo, meetingID: TodoBoard.own), id: TodoBoard.own)
                    .padding(.bottom, Space.xxl)
                ForEach(groups) { group in
                    list(title: meetingTitle(group), items: group.items, id: group.meetingID)
                        .padding(.bottom, Space.xxl)
                }
            }
            .padding(.horizontal, Metric.contentX - Metric.canvasX)
            .padding(.vertical, Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func list(title: some View, items: [TodoBoard.Item], id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            title
            ForEach(items) { item in
                // A row is rebuilt when its words or box change, so it never shows a stale draft.
                TodoRow(item: item).id("\(item.id)-\(item.text)-\(item.done)")
            }
            NewTodoRow(list: id)
        }
    }

    private func meetingTitle(_ group: TodoBoard.Group) -> some View {
        Button {
            model.open(group.meetingID)
            model.show(.summary)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(group.title)
                    .kitType(.settingTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                Text(group.start.formatted(date: .abbreviated, time: .omitted))
                    .kitType(.label)
                    .foregroundStyle(Ink.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open this meeting")
        .accessibilityHint("Opens the meeting's summary")
    }
}

/// One to-do: its box, and its words in a field that saves on Return or when focus leaves.
private struct TodoRow: View {
    @Environment(AppModel.self) private var model
    let item: TodoBoard.Item
    @State private var draft: String
    @FocusState private var editing: Bool

    init(item: TodoBoard.Item) {
        self.item = item
        _draft = State(initialValue: item.text)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Button {
                model.toggleTodo(item)
            } label: {
                KitIconView(item.done ? .todoDone : .todoOpen)
                    .foregroundStyle(item.done ? Ink.textSecondary : Ink.text)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            .accessibilityLabel(item.text)
            .accessibilityValue(item.done ? "Done" : "Not done")
            .accessibilityAddTraits(.isToggle)
            TextField("To-do", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .kitType(.transcript)
                .strikethrough(item.done && !editing)
                .foregroundStyle(item.done ? Ink.textSecondary : Ink.text)
                .focused($editing)
                .onSubmit { editing = false }
                .onChange(of: editing) { _, now in if !now { save() } }
                .onDisappear(perform: save)
                .accessibilityLabel("To-do's words")
        }
        .contextMenu {
            Button(item.done ? "Mark as Not Done" : "Mark as Done") { model.toggleTodo(item) }
            Button("Delete To-do") { model.deleteTodo(item) }
        }
    }

    private func save() {
        guard draft != item.text else { return }
        model.editTodo(item, text: draft)
    }
}

/// The last row of a list: type a to-do and press Return to add it.
private struct NewTodoRow: View {
    @Environment(AppModel.self) private var model
    let list: String
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            KitIconView(.todoNew)
                .foregroundStyle(Ink.textSecondary)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            TextField("New to-do", text: $draft)
                .textFieldStyle(.plain)
                .kitType(.transcript)
                .foregroundStyle(Ink.text)
                .onSubmit {
                    model.addTodo(draft, to: list)
                    draft = ""
                }
                .accessibilityLabel(list == TodoBoard.own ? "New to-do" : "New to-do for this meeting")
        }
    }
}
