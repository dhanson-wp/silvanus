import SwiftUI

/// The sidebar's measured positions, from design/KIT.md "Sidebar accent rule", "Day heading",
/// "Meeting row", and "Folder row". Text is placed by its cap top (what the reference was
/// measured by), not its line box, so a change of font keeps the ink where KIT.md puts it.
extension Metric {
    /// The accent rule's center, from the window's top: y 64.5, a hairline from x 4 to 204.
    static let sidebarRuleY: CGFloat = 64.5
    /// From the rule's bottom edge to the first day heading's cap top (y 84).
    static let dayHeadingCapTop: CGFloat = 19
    /// A day heading's whole band, rule to first row: the first pill starts at y 106.
    static let dayHeadingBand: CGFloat = 41
    /// A meeting row's title cap top below its pill's top (measured 12.5 to 13).
    static let meetingTitleCapTop: CGFloat = 12.75
    /// From the title's cap top to the time's.
    static let meetingTimeBelowTitle: CGFloat = 20.5
    /// The folder line's cap top below the pill's top, and the title's below the folder line's.
    static let folderLineCapTop: CGFloat = 11
    static let folderLineToTitle: CGFloat = 20
    /// Between the folder line's 11 pt icon and its name.
    static let folderLineGap: CGFloat = 5.5
    /// A folder row's label, from the window's left edge (the settings list's second edge).
    static let folderRowLabelX: CGFloat = 39.5
    /// Trailing text and glyphs end this far before the sidebar's edge.
    static let sidebarTextTrailing: CGFloat = 15.5
}

extension KitType {
    /// The height of a capital, for placing text by its cap top.
    var capHeight: CGFloat { nsFont.capHeight }
}

extension View {
    /// Puts a line of text's cap top `y` below the top of the enclosing
    /// `ZStack(alignment: .topLeading)`. The stack needs a child that sets its full height
    /// with nothing above it (`SidebarBand`), so the stack's top stays put.
    func capTop(_ y: CGFloat, _ type: KitType) -> some View {
        let baseline = y + type.capHeight
        return alignmentGuide(.top) { $0[.firstTextBaseline] - baseline }
    }
}

/// A clear band of a fixed height that pins a `capTop` stack's top and size.
struct SidebarBand: View {
    let height: CGFloat

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

private struct SidebarRowSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a selected sidebar row, so its title turns medium.
    var sidebarRowSelected: Bool {
        get { self[SidebarRowSelectedKey.self] }
        set { self[SidebarRowSelectedKey.self] = newValue }
    }
}

/// A sidebar row's pill, from KIT.md "Meeting row" and "Folder row": x 4 to 204, corner 8,
/// rows back to back, text from x 16.5. The label sets the height (54 or 72 for a meeting,
/// 28 for a folder).
///
/// | State | Fill |
/// | rest | none |
/// | hover | selection at 50% |
/// | pressed | selection at 80% |
/// | selected | selection, title medium |
/// | selected, window inactive | selection at 60% |
/// | focused | 2 pt focus ring inside the pill |
/// | disabled | everything at 40% |
///
/// The gallery forces a state with `forcedPartState` and the inactive window with
/// `appearsActive`.
///
/// `isFocused` draws the ring. Leave it nil for a row that takes focus itself. A list that
/// takes focus as a whole (and moves its selection with the arrow keys) passes it for the
/// selected row: inside a focusable list every row would otherwise read the list's focus.
struct SidebarRowStyle: ButtonStyle {
    var isSelected: Bool
    var isFocused: Bool?

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, isSelected: isSelected, focusedByList: isFocused)
    }

    private struct RowBody: View {
        let configuration: Configuration
        let isSelected: Bool
        let focusedByList: Bool?
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var ownFocus
        @Environment(\.appearsActive) private var appearsActive
        @State private var hovering = false

        private var isFocused: Bool { focusedByList ?? ownFocus }

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : isSelected ? .selected : configuration.isPressed ? .pressed
                : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var fill: Color {
            switch state {
            case .selected: Ink.selection.opacity(appearsActive ? 1 : 0.6)
            case .pressed: Ink.selection.opacity(0.8)
            case .hover: Ink.selection.opacity(0.5)
            default: .clear
            }
        }

        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.rowCorner)
            configuration.label
                .environment(\.sidebarRowSelected, state == .selected)
                .padding(.leading, Metric.sidebarTextX - Metric.sidebarRowInset)
                .padding(.trailing, Metric.sidebarTextTrailing - Metric.sidebarRowInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: shape)
                .overlay {
                    if ringed { shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing) }
                }
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(shape)
                .focusEffectDisabled()
                .animation(Motion.select, value: state == .selected)
                .animation(Motion.select, value: appearsActive)
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
                .padding(.horizontal, Metric.sidebarRowInset)
                .accessibilityAddTraits(state == .selected ? .isSelected : [])
        }
    }
}
