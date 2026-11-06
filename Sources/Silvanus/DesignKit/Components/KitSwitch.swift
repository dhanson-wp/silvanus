import SwiftUI

/// The switch, from KIT.md "Settings": 44 × 24, fully rounded, a 20 pt knob.
///
/// | State | Track | Border | Knob |
/// | off | sidebar | 1 pt divider | canvas |
/// | on | primaryControl | none | onPrimary |
/// | hover | as off, or on at 90% | off: textSecondary | as above |
/// | pressed | as off, or on at 80% | off: textSecondary | as above |
/// | focused | as off or on | 2 pt focus ring | as above |
/// | disabled | everything at 40% | | |
///
/// Use it as a real `Toggle`: `Toggle("Show in Dock", isOn: $on).toggleStyle(KitSwitchStyle())`
/// and give the Toggle an `.accessibilityLabel`. The gallery forces a state with
/// `forcedPartState`.
struct KitSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @State private var isFocused = false
        @State private var hovering = false
        @State private var pressing = false

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : pressing ? .pressed : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var isOn: Bool { configuration.isOn }
        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        private var track: Color {
            guard isOn else { return Ink.sidebar }
            switch state {
            case .hover: return Ink.primaryControl.opacity(0.9)
            case .pressed: return Ink.primaryControl.opacity(0.8)
            default: return Ink.primaryControl
            }
        }

        private var border: Color {
            [.hover, .pressed].contains(state) ? Ink.textSecondary : Ink.divider
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.switchHeight / 2)
            let travel = Metric.switchWidth - Metric.switchKnob - 2 * Metric.switchInset
            Button {
                configuration.isOn.toggle()
            } label: {
                switchBody(shape: shape, travel: travel)
                    // The Toggle's label is the button's accessibility label; nothing shows.
                    .background { configuration.label.frame(width: 0, height: 0).opacity(0) }
            }
            .buttonStyle(SwitchPressStyle(pressing: $pressing, focused: $isFocused))
            .opacity(state == .disabled ? 0.4 : 1)
            .focusEffectDisabled()
            .animation(Motion.select, value: isOn)
            .onHover { inside in
                withAnimation(Motion.hover) { hovering = inside }
            }
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? "On" : "Off")
        }

        private func switchBody(shape: RoundedRectangle, travel: CGFloat) -> some View {
            shape
                    .fill(track)
                    .frame(width: Metric.switchWidth, height: Metric.switchHeight)
                    .overlay {
                        if ringed {
                            shape.inset(by: Metric.focusRing / 2).stroke(Ink.focus, lineWidth: Metric.focusRing)
                        } else if !isOn {
                            shape.inset(by: Metric.hairline / 2).stroke(border, lineWidth: Metric.hairline)
                        }
                    }
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(isOn ? Ink.onPrimary : Ink.canvas)
                            .frame(width: Metric.switchKnob, height: Metric.switchKnob)
                            .padding(.leading, Metric.switchInset)
                            .offset(x: isOn ? travel : 0) // grid: ok knob travel
                    }
                    .contentShape(shape)
        }
    }

    /// Reports the press and the keyboard focus to the switch and adds nothing to the look.
    /// Focus is read here, inside the button, where SwiftUI sets it.
    private struct SwitchPressStyle: ButtonStyle {
        @Binding var pressing: Bool
        @Binding var focused: Bool

        func makeBody(configuration: Configuration) -> some View {
            Report(configuration: configuration, pressing: $pressing, focused: $focused)
        }

        private struct Report: View {
            let configuration: Configuration
            @Binding var pressing: Bool
            @Binding var focused: Bool
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .onChange(of: configuration.isPressed) { _, new in pressing = new }
                    .onChange(of: isFocused, initial: true) { _, new in focused = new }
            }
        }
    }
}

extension Metric {
    /// KIT.md "Settings", Switch: 44 × 24, knob 20, so 2 around the knob.
    static let switchWidth: CGFloat = 44
    static let switchHeight: CGFloat = 24
    static let switchKnob: CGFloat = 20
    static let switchInset: CGFloat = 2
}
