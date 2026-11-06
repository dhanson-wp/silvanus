import SwiftUI

/// The label of a meeting's sidebar row, from KIT.md "Meeting row": an optional folder line
/// (11 pt folder icon, then the name in `meta`), the title in `rowTitle` on one line with an
/// ellipsis, and the time in `monoTime`. Put it in a Button with `SidebarRowStyle`, which
/// draws the pill and its states; the title turns medium when the row is selected.
///
/// Without a folder line the row is 54 tall: title cap top at +12.75, time 20.5 below it.
/// With one it's 72: folder line cap top at +11, title 20 below it, time 20.5 below that.
struct SidebarMeetingRow: View {
    let title: String
    let time: String
    var folder: String?

    @Environment(\.sidebarRowSelected) private var selected

    private var titleCapTop: CGFloat {
        folder == nil ? Metric.meetingTitleCapTop : Metric.folderLineCapTop + Metric.folderLineToTitle
    }

    var body: some View {
        // The folder icon centers on the folder name's capitals.
        let iconCenter = Metric.folderLineCapTop + KitType.meta.capHeight / 2
        return ZStack(alignment: .topLeading) {
            SidebarBand(height: folder == nil ? Metric.meetingRowPitch : Metric.meetingRowPitchFolder)
            if let folder {
                KitIconView(.folderLine)
                    .foregroundStyle(Ink.textSecondary)
                    .alignmentGuide(.top) { $0.height / 2 - iconCenter }
                Text(folder)
                    .kitType(.meta)
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, KitIcon.folderLine.size + Metric.folderLineGap)
                    .capTop(Metric.folderLineCapTop, .meta)
            }
            Text(title)
                .kitType(selected ? .rowTitleSelected : .rowTitle)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .capTop(titleCapTop, .rowTitle)
            Text(time)
                .kitType(.monoTime)
                .foregroundStyle(Ink.textSecondary)
                .lineLimit(1)
                .capTop(titleCapTop + Metric.meetingTimeBelowTitle, .monoTime)
        }
        // One label in reading order; the folder icon is already hidden (KitIconView).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, folder, time].compactMap { $0 }.joined(separator: ", "))
    }
}
