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
        @Environment(\.isFocused) private var isFocused
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
            let shape = Capsule()
            let travel = Metric.switchWidth - Metric.switchKnob - 2 * Metric.switchInset
            Button {
                configuration.isOn.toggle()
            } label: {
                shape
                    .fill(track)
                    .frame(width: Metric.switchWidth, height: Metric.switchHeight)
                    .overlay {
                        if ringed {
                            shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing)
                        } else if !isOn {
                            shape.strokeBorder(border, lineWidth: Metric.hairline)
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
            .buttonStyle(SwitchPressStyle(pressing: $pressing))
            .opacity(state == .disabled ? 0.4 : 1)
            .focusEffectDisabled()
            .animation(Motion.select, value: isOn)
            .onHover { inside in
                withAnimation(Motion.hover) { hovering = inside }
            }
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(isOn ? "On" : "Off")
        }
    }

    /// Reports the press to the switch and adds nothing to the look.
    private struct SwitchPressStyle: ButtonStyle {
        @Binding var pressing: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, new in pressing = new }
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
