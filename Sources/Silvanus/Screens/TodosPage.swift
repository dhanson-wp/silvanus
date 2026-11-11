import SilvanusKit
import SwiftUI

/// To-dos (the sidebar's To-dos row, ⇧⌘T): every meeting's open to-dos in one place.
/// Each meeting that still has something to do is a group: its title (click to open its
/// Summary), then its to-dos. Ticking one here writes that meeting's `todo.md`. A meeting
/// drops off the page once all its to-dos are done.
struct TodosPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = TodoBoard.groups(model.meetings)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("To-dos")
                    .kitType(.title)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Space.xxl)
                ForEach(groups) { group in
                    self.group(group)
                        .padding(.bottom, Space.xxl)
                }
            }
            .padding(.horizontal, Metric.contentX - Metric.canvasX)
            .padding(.vertical, Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No to-dos", systemImage: KitIcon.todos.symbol,
                                       description: Text("To-dos from your calls show up here."))
            }
        }
    }

    private func group(_ group: TodoBoard.Group) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
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
            ForEach(group.items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: TodoBoard.Item) -> some View {
        Button {
            model.toggleTodo(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                KitIconView(item.done ? .todoDone : .todoOpen)
                    .foregroundStyle(item.done ? Ink.textSecondary : Ink.text)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text(item.text)
                    .kitType(.transcript)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Ink.textSecondary : Ink.text)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.text)
        .accessibilityValue(item.done ? "Done" : "Not done")
        .accessibilityAddTraits(.isToggle)
    }
}
