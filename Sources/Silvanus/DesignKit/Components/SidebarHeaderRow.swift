import SwiftUI

/// KIT.md "Sidebar header row": after the traffic lights, four 28 × 28 icon buttons (hide
/// sidebar, search, new meeting, filter) centered at x 94, 122, 150, and 178, at y 9.
///
/// It sits in `PaneLayout`'s window header, so the hide sidebar button stays put when the
/// sidebar hides; the other three go with the sidebar. A button whose action is nil isn't
/// drawn, and its slot stays empty so the others keep their places. View > Hide Sidebar
/// (⌃⌘S) does what the first button does.
struct SidebarHeaderRow: View {
    var sidebarVisible: Bool
    var toggleSidebar: () -> Void
    var search: (() -> Void)? = nil
    var newMeeting: (() -> Void)? = nil
    var filter: (() -> Void)? = nil

    private var toggleTitle: String { sidebarVisible ? "Hide Sidebar" : "Show Sidebar" }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Metric.sidebarHeaderFirstX - Metric.iconButton / 2, height: Metric.iconButton)
            button(.hideSidebar, toggleTitle, toggleSidebar)
                .gridProbe("hideSidebar", area: "windowHeader", edge: nil)
            if sidebarVisible {
                slot(.search, "Search", search)
                slot(.newNote, "New Meeting", newMeeting)
                slot(.filter, "Filter", filter)
            }
        }
        .padding(.top, Metric.controlY)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func slot(_ icon: KitIcon, _ title: String, _ action: (() -> Void)?) -> some View {
        if let action {
            button(icon, title, action)
        } else {
            // Holds the place; clear space takes no clicks, so the header under it still drags.
            Color.clear.frame(width: Metric.iconButton, height: Metric.iconButton)
        }
    }

    private func button(_ icon: KitIcon, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KitIconView(icon)
        }
        .buttonStyle(HeaderIconButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A 28 × 28 icon button in the window header, with KIT.md "Sidebar header row"'s states:
/// rest (no fill, textSecondary), hover (selection fill, text), pressed (selection at 80%),
/// focused (2 pt focus ring, corner 7), and disabled (textSecondary at 40%). The gallery
/// forces a state with `forcedPartState`.
struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : configuration.isPressed ? .pressed
                : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var fill: Color {
            switch state {
            case .hover: Ink.selection
            case .pressed: Ink.selection.opacity(0.8)
            default: .clear
            }
        }

        private var lit: Bool { [.hover, .pressed, .focused].contains(state) }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.iconButtonCorner)
            configuration.label
                .foregroundStyle(lit ? Ink.text : Ink.textSecondary)
                .opacity(state == .disabled ? 0.4 : 1)
                .frame(width: Metric.iconButton, height: Metric.iconButton)
                .background(fill, in: shape)
                .overlay {
                    if state == .focused || (isFocused && state != .disabled) {
                        shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing)
                    }
                }
                .contentShape(shape)
                .focusEffectDisabled()
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
        }
    }
}
