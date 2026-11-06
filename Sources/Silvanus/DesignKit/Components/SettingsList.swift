import SwiftUI

/// One entry in the settings list.
struct SettingsListItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let icon: KitIcon
}

/// A group in the settings list, with its label ("App", "AI").
struct SettingsListGroup<ID: Hashable>: Identifiable {
    let title: String
    let items: [SettingsListItem<ID>]

    var id: String { title }
}

/// The settings list in the sidebar's column, from KIT.md "Settings": group labels in
/// `section` (capitals, `textSecondary`) at x 16.5, and rows 36 tall with a 2 pt gap, inset
/// 4, corner 8, an icon at x 16.5 and the label at x 39.5. The chosen row is `selection`
/// with a medium label; hover, pressed, and focus are the sidebar rows' (`SidebarRowStyle`).
///
/// Adapted: there is no search field yet, so the first group starts right under the header;
/// the column keeps the window's 208 pt sidebar width, not the reference's 204.
///
/// Keyboard: Tab into the list, then the up and down arrows move the choice.
struct SettingsList<ID: Hashable>: View {
    let groups: [SettingsListGroup<ID>]
    @Binding var selection: ID

    @FocusState private var focused: Bool
    @State private var keyboardFocus = false
    @State private var clicked = false

    private var order: [ID] { groups.flatMap { $0.items.map(\.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                Text(group.title)
                    .kitType(.section)
                    .foregroundStyle(Ink.textSecondary)
                    .padding(.leading, Metric.sidebarTextX)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.sm)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.items) { item in
                    row(item)
                        .padding(.bottom, Metric.settingsListGap)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onChange(of: focused) { _, new in
            keyboardFocus = new && !clicked
            clicked = false
        }
        .onMoveCommand { direction in
            let step = direction == .up ? -1 : direction == .down ? 1 : 0
            guard step != 0, let index = order.firstIndex(of: selection) else { return }
            selection = order[min(max(index + step, 0), order.count - 1)]
        }
    }

    private func row(_ item: SettingsListItem<ID>) -> some View {
        let selected = item.id == selection
        return Button {
            if !focused { clicked = true; focused = true }
            selection = item.id
        } label: {
            SettingsListRow(title: item.title, icon: item.icon)
        }
        .buttonStyle(SidebarRowStyle(isSelected: selected, isFocused: selected && keyboardFocus && focused))
        .focusable(false)
    }
}

/// A settings list row's label: a 14 pt icon at x 16.5 and `rowTitle` at x 39.5, 36 tall.
struct SettingsListRow: View {
    let title: String
    let icon: KitIcon

    @Environment(\.sidebarRowSelected) private var selected

    var body: some View {
        HStack(spacing: 0) {
            KitIconView(icon)
                .foregroundStyle(Ink.textSecondary)
                .frame(width: Metric.folderRowLabelX - Metric.sidebarTextX, alignment: .leading)
            Text(title)
                .kitType(selected ? .rowTitleSelected : .rowTitle)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.sm)
        }
        .frame(height: Metric.settingsListRow)
        .accessibilityElement(children: .combine)
    }
}

extension Metric {
    /// KIT.md "Settings", List row: a 36 tall pill, 2 between pills (pitch 38).
    static let settingsListRow: CGFloat = 36
    static let settingsListGap: CGFloat = 2
    /// KIT.md "Settings", Pane: content starts 24 after the divider (x 229 from the window).
    static let settingsPaneInset: CGFloat = 24
}

/// The window header while Settings is open, from KIT.md "Settings": a back button
/// (`chevron.left`) centered at x 94, where the sidebar header's first button sits. It does
/// what Escape and View > Close Settings (⌘[) do.
struct SettingsHeaderRow: View {
    var back: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Metric.sidebarHeaderFirstX - Metric.iconButton / 2, height: Metric.iconButton)
            IconButton(.back, "Back", help: "Back to your meetings (Esc)", action: back)
                .gridProbe("settingsBack", area: "windowHeader", edge: nil)
        }
        .padding(.top, Metric.controlY)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
