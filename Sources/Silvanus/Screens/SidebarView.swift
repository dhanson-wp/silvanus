import SilvanusKit
import SwiftUI

/// The sidebar under the window header: the accent rule, the meetings grouped by day
/// ("Today", "Yesterday", the weekday, then the date), and the Folders section at the
/// bottom. Choosing a folder shows only its meetings; All meetings shows every one.
///
/// Keyboard: with the meeting list focused (click a row, or Tab to it), the up and down
/// arrows move the selection and Return opens it. The same arrows step through the folders.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    let page: SidebarItem

    @AppStorage("sidebar.foldersOpen", store: AppDefaults.shared) private var foldersOpen = true
    @FocusState private var focus: Region?
    /// True while a region has focus from the keyboard (Tab), not a click: only then does the
    /// selected row draw its focus ring, as a Mac list shows a ring for keyboard focus only.
    @State private var keyboardFocus = false
    @State private var clicked = false

    private enum Region { case meetings, folders }

    /// Folder rows shown before the section scrolls.
    private static let visibleFolderRows = 6

    /// Nothing is starred yet: starring arrives with the meeting type.
    private var groups: [DayGroup] {
        page == .starred ? [] : model.dayGroups
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarAccentRule()
            // Moves the model's clock at each midnight, so "Today" turns into "Yesterday" on
            // time. The model regroups; the view only reads its cached days.
            TimelineView(MidnightSchedule()) { context in
                meetingList(groups)
                    .onChange(of: context.date, initial: true) { _, date in model.now = date }
            }
            if !model.folders.isEmpty, !model.referenceStage {
                foldersSection
            }
        }
        .onChange(of: focus) { _, new in
            keyboardFocus = new != nil && !clicked
            clicked = false
        }
    }

    /// A click moves focus to its region without a ring.
    private func focusByClick(_ region: Region) {
        guard focus != region else { return }
        clicked = true
        focus = region
    }

    private func ring(_ region: Region, selected: Bool) -> Bool {
        selected && keyboardFocus && focus == region
    }

    // MARK: - Meetings

    private func meetingList(_ groups: [DayGroup]) -> some View {
        let order = page == .starred ? [] : model.sidebarOrder
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.day) { group in
                        SidebarDayHeading(group.title)
                        ForEach(group.meetings) { meeting in
                            meetingRow(meeting).id(meeting.id)
                        }
                    }
                    if groups.isEmpty {
                        if model.folder != nil {
                            SidebarEmptyNote(title: "No meetings in this folder")
                        } else {
                            SidebarEmptyNote(title: "No meetings yet", hint: "Click Start Recording to add one.")
                        }
                    }
                }
            }
            .focusable()
            .focused($focus, equals: .meetings)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                guard let step = Self.step(direction),
                      let next = SidebarSelection.step(order, from: model.selection, by: step) else { return }
                model.selection = next
                withAnimation(Motion.select) { proxy.scrollTo(next) }
            }
            .onKeyPress(.return) {
                guard let id = model.selection, order.contains(id) else { return .ignored }
                model.open(id)
                return .handled
            }
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        let selected = meeting.id == model.selection
        return Button {
            focusByClick(.meetings)
            model.open(meeting.id)
        } label: {
            SidebarMeetingRow(title: meeting.displayTitle,
                              time: meeting.info.start.formatted(date: .omitted, time: .shortened),
                              folder: model.folder == nil ? meeting.info.folder : nil)
        }
        .buttonStyle(SidebarRowStyle(isSelected: selected, isFocused: ring(.meetings, selected: selected)))
        // The list takes focus as one; Tab doesn't stop on every row.
        .focusable(false)
        .contextMenu {
            Button("Move to Trash") { model.trash(meeting.id) }
                .disabled(!model.canTrash(meeting.id))
                .help(model.trashHelp(meeting.id))
        }
    }

    // MARK: - Folders

    private var foldersSection: some View {
        let folders = model.folders
        // All meetings, then each folder; nil is All meetings.
        let order: [String?] = [nil] + folders.map(\.name)
        return VStack(spacing: 0) {
            SidebarDivider()
                .padding(.bottom, Space.xs)
            Button {
                withAnimation(Motion.select) { foldersOpen.toggle() }
            } label: {
                SidebarSectionHeader(title: "Folders", isOpen: foldersOpen)
            }
            .buttonStyle(SidebarRowStyle(isSelected: false))
            .help(foldersOpen ? "Hide folders" : "Show folders")
            if foldersOpen {
                ScrollView {
                    VStack(spacing: 0) {
                        folderButton(nil, title: "All meetings", icon: .allMeetings, count: nil)
                        ForEach(folders, id: \.name) { folder in
                            folderButton(folder.name, title: folder.name, icon: .folderRow, count: folder.count)
                        }
                    }
                }
                .frame(height: CGFloat(min(order.count, Self.visibleFolderRows)) * Metric.folderRowPitch)
                .focusable()
                .focused($focus, equals: .folders)
                .focusEffectDisabled()
                .onMoveCommand { direction in
                    guard let step = Self.step(direction), let index = order.firstIndex(of: model.folder) else { return }
                    model.folder = order[min(max(index + step, 0), order.count - 1)]
                }
            }
        }
        .padding(.bottom, Space.sm)
    }

    private func folderButton(_ name: String?, title: String, icon: KitIcon, count: Int?) -> some View {
        let selected = model.folder == name
        return Button {
            focusByClick(.folders)
            model.folder = name
        } label: {
            SidebarFolderRow(title: title, icon: icon, count: count)
        }
        .buttonStyle(SidebarRowStyle(isSelected: selected, isFocused: ring(.folders, selected: selected)))
        .focusable(false)
    }

    private static func step(_ direction: MoveCommandDirection) -> Int? {
        switch direction {
        case .up: -1
        case .down: 1
        default: nil
        }
    }
}

/// Fires at the start of every day, from the first entry on.
private struct MidnightSchedule: TimelineSchedule {
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        let calendar = Calendar.current
        return AnySequence(sequence(first: startDate) { date in
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        })
    }
}
