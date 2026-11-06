import SwiftUI

/// What the canvas shows for the open meeting: the view pill switches it, and so do
/// View > Summary, My notes, and Transcript (⌘1, ⌘2, ⌘3).
enum CanvasMode: String, CaseIterable, Identifiable {
    case summary, notes, transcript

    var id: String { rawValue }

    /// The glossary's word for the view.
    var title: String {
        switch self {
        case .summary: "Summary"
        case .notes: "My notes"
        case .transcript: "Transcript"
        }
    }

    var icon: KitIcon {
        switch self {
        case .summary: .summaryTab
        case .notes: .myNotesTab
        case .transcript: .transcriptTab
        }
    }

    /// ⌘1, ⌘2, ⌘3, in pill order.
    var shortcut: Character {
        switch self {
        case .summary: "1"
        case .notes: "2"
        case .transcript: "3"
        }
    }

    /// The tooltip: what the tab does, then its shortcut.
    var help: String {
        switch self {
        case .summary: "Show the summary (⌘1)"
        case .notes: "Show my notes (⌘2)"
        case .transcript: "Show the transcript (⌘3)"
        }
    }
}

/// KIT.md "Canvas header": the view pill's measures.
extension Metric {
    /// The track's inset around its segments.
    static let pillInset: CGFloat = 2
    static let pillSegmentHeight: CGFloat = 24
    /// An unselected tab: the icon alone, centered.
    static let pillTabWidth: CGFloat = 34
    /// A selected tab: 9 + icon + 8 + label + 9.5.
    static let pillSegmentLeading: CGFloat = 9
    static let pillIconGap: CGFloat = 8
    static let pillSegmentTrailing: CGFloat = 9.5
}

/// The view pill from KIT.md "Canvas header": a track 28 tall, fully rounded, with one tab
/// per `CanvasMode`. The selected tab widens to show its label on a raised segment that
/// slides there with `Motion.select`; the others show their icon alone.
///
/// | State | Segment | Icon | Label |
/// | selected | pillSegment | text | shown |
/// | rest | none | textTertiary | hidden |
/// | hover | pillSegment at 50% | text | hidden; tooltip names the view |
/// | pressed | pillSegment at 80% | text | hidden |
/// | focused | 2 pt focus ring around the tab | text | as selected or rest |
/// | disabled | none | textTertiary at 40% | hidden |
///
/// `disabled` lists modes that can't be shown yet (no transcript). The gallery's forced
/// state (`forcedPartState`) applies to the unselected tabs; `.focused` rings the selected one.
struct ViewPill: View {
    @Binding var mode: CanvasMode
    var disabled: Set<CanvasMode> = []

    @Namespace private var segment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CanvasMode.allCases) { tab in
                Button {
                    withAnimation(Motion.select) { mode = tab }
                } label: {
                    HStack(spacing: Metric.pillIconGap) {
                        KitIconView(tab.icon)
                        if tab == mode {
                            Text(tab.title)
                                .kitType(.tab)
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(ViewPillTabStyle(isSelected: tab == mode, segment: segment))
                .disabled(disabled.contains(tab))
                .help(tab.help)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == mode ? .isSelected : [])
            }
        }
        .padding(Metric.pillInset)
        .frame(height: Metric.controlHeight)
        .background(Ink.pillTrack, in: Capsule())
        .animation(Motion.select, value: mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }
}

/// One tab of the view pill (see `ViewPill`).
struct ViewPillTabStyle: ButtonStyle {
    var isSelected: Bool
    var segment: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isSelected: isSelected, segment: segment)
    }

    private struct Content: View {
        let configuration: Configuration
        let isSelected: Bool
        let segment: Namespace.ID
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        private var state: PartState {
            if !isEnabled { return .disabled }
            if isSelected { return forced == .focused || isFocused ? .focused : .selected }
            if let forced { return forced == .selected || forced == .focused ? .rest : forced }
            return configuration.isPressed ? .pressed : hovering ? .hover : isFocused ? .focused : .rest
        }

        private var hoverFill: Color {
            switch state {
            case .hover: Ink.pillSegment.opacity(0.5)
            case .pressed: Ink.pillSegment.opacity(0.8)
            default: .clear
            }
        }

        private var ink: Color {
            isSelected || [.hover, .pressed, .focused].contains(state) ? Ink.text : Ink.textTertiary
        }

        var body: some View {
            let shape = Capsule()
            configuration.label
                .foregroundStyle(ink)
                .opacity(state == .disabled ? 0.4 : 1)
                .padding(.leading, isSelected ? Metric.pillSegmentLeading : 0)
                .padding(.trailing, isSelected ? Metric.pillSegmentTrailing : 0)
                .frame(minWidth: Metric.pillTabWidth)
                .frame(height: Metric.pillSegmentHeight)
                .background {
                    if isSelected {
                        shape.fill(Ink.pillSegment)
                            .shadow(color: Ink.text.opacity(0.12), radius: 0.5, y: 1)
                            .matchedGeometryEffect(id: "segment", in: segment)
                    } else {
                        shape.fill(hoverFill)
                    }
                }
                .overlay {
                    if state == .focused { shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing) }
                }
                .contentShape(shape)
                .focusEffectDisabled()
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
        }
    }
}
