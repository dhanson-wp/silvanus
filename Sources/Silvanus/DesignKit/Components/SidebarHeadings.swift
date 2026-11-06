import SwiftUI

/// KIT.md "Sidebar accent rule": a hairline in `Ink.accent` (gold, fill only) from y 64.5 to
/// 65.5 from the window's top, inset 4 on both sides, under the header and above the first
/// day heading. Put it at the top of the sidebar slot, which starts under the 46 pt header.
struct SidebarAccentRule: View {
    var body: some View {
        Rectangle()
            .fill(Ink.accent)
            .frame(height: Metric.hairline)
            .padding(.horizontal, Metric.sidebarRowInset)
            .padding(.top, Metric.sidebarRuleY - Metric.headerHeight)
            .accessibilityHidden(true)
    }
}

/// KIT.md "Day heading": `dayHeading` (16 bold) in `Ink.text` at x 16.5, its cap top 19
/// below the rule (y 84.5), and the first row's pill 40.5 below the rule (y 106). Every day
/// group starts with the same 40.5 pt band.
struct SidebarDayHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarBand(height: Metric.dayHeadingBand)
            Text(title)
                .kitType(.dayHeading)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .capTop(Metric.dayHeadingCapTop, .dayHeading)
        }
        .padding(.leading, Metric.sidebarTextX)
        .padding(.trailing, Metric.sidebarTextTrailing)
        .accessibilityAddTraits(.isHeader)
    }
}

/// KIT.md "Empty states", sidebar: no day heading; one line in `rowTitle`, `textSecondary`,
/// at x 16.5 with its cap top where the day heading's would be (y 84), and an optional hint
/// in `meta` under it.
struct SidebarEmptyNote: View {
    let title: String
    var hint: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarBand(height: Metric.dayHeadingBand)
            Text(title)
                .kitType(.rowTitle)
                .foregroundStyle(Ink.textSecondary)
                .capTop(Metric.dayHeadingCapTop, .rowTitle)
            if let hint {
                Text(hint)
                    .kitType(.meta)
                    .foregroundStyle(Ink.textSecondary)
                    .capTop(Metric.dayHeadingCapTop + Metric.folderLineToTitle, .meta)
            }
        }
        .padding(.leading, Metric.sidebarTextX)
        .padding(.trailing, Metric.sidebarTextTrailing)
        .accessibilityElement(children: .combine)
    }
}

/// A hairline in `Ink.divider` across the sidebar, inset 4 like the rows: it sets the
/// Folders section off from the meeting list above it.
struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Ink.divider)
            .frame(height: Metric.hairline)
            .padding(.horizontal, Metric.sidebarRowInset)
            .accessibilityHidden(true)
    }
}
