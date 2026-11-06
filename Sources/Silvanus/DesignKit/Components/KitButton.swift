import SwiftUI

/// The bordered button, from KIT.md "Settings": 36 tall, corner 6, a 1 pt `Ink.divider`
/// border, `Ink.sidebar` fill, the `button` type, 16 of padding on each side.
///
/// | State | Fill | Border | Label |
/// | rest | sidebar | 1 pt divider | text |
/// | hover | sidebar | 1 pt textSecondary | text |
/// | pressed | sidebar at 80% | 1 pt textSecondary | text |
/// | selected | primaryControl | none | onPrimary |
/// | focused | as rest | 2 pt focus ring | text |
/// | disabled | as rest | divider at 40% | text at 40% |
///
/// `isSelected` marks the chosen one of a group (Settings > Appearance). The gallery forces a
/// state with `forcedPartState`.
struct KitButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isSelected: isSelected)
    }

    private struct Content: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : isSelected ? .selected : configuration.isPressed ? .pressed
                : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var selected: Bool { state == .selected }
        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.buttonCorner)
            configuration.label
                .kitType(.button)
                .foregroundStyle(selected ? Ink.onPrimary : Ink.text)
                .padding(.horizontal, Space.lg)
                .frame(height: Metric.settingsButtonHeight)
                .background(selected ? Ink.primaryControl : Ink.sidebar.opacity(state == .pressed ? 0.8 : 1), in: shape)
                .overlay {
                    if ringed {
                        shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing)
                    } else if !selected {
                        let line = [.hover, .pressed].contains(state) ? Ink.textSecondary : Ink.divider
                        shape.strokeBorder(line.opacity(state == .disabled ? 0.4 : 1), lineWidth: Metric.hairline)
                    }
                }
                .opacity(state == .disabled ? 0.4 : 1)
                .contentShape(shape)
                .focusEffectDisabled()
                .animation(Motion.select, value: selected)
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

extension Metric {
    /// KIT.md "Settings", Bordered button: 36 tall.
    static let settingsButtonHeight: CGFloat = 36
}
