import SwiftUI

/// The label of a folder's sidebar row, from KIT.md "Folder row": a 14 pt icon at x 16.5,
/// the name in `rowTitle` at x 39.5 (medium when selected), and a trailing count in `meta`
/// ending 15.5 before the sidebar's edge. 28 tall. Put it in a Button with
/// `SidebarRowStyle`. "All meetings" uses it with its own icon and no count.
struct SidebarFolderRow: View {
    let title: String
    var icon: KitIcon = .folderRow
    var count: Int?

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
            if let count {
                Text(count, format: .number)
                    .kitType(.meta)
                    .monospacedDigit()
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(height: Metric.folderRowPitch)
        .accessibilityElement(children: .combine)
    }
}

/// The label of a collapsible sidebar section's header ("Folders"): the name in `section`
/// (capitals, textSecondary) at x 16.5 and a chevron ending 15.5 before the sidebar's edge,
/// pointing right when closed and down when open. 28 tall, like a folder row. Put it in a
/// Button with `SidebarRowStyle(isSelected: false)` that opens and closes the section.
struct SidebarSectionHeader: View {
    let title: String
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Space.sm)
            KitIconView(.disclosure)
                .foregroundStyle(Ink.textSecondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .frame(height: Metric.folderRowPitch)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }
}
