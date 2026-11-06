import SwiftUI

/// A setting's row in a Settings pane, from KIT.md "Settings": the title in `settingTitle`,
/// the description in `label` and `textSecondary` under it, and the control right-aligned.
/// Rows repeat every 56 pt. A control that can't be used yet passes `isEnabled: false` and a
/// `help` that says why.
struct SettingRow<Control: View>: View {
    let title: String
    var description: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .kitType(.settingTitle)
                    .foregroundStyle(Ink.text)
                if let description {
                    Text(description)
                        .kitType(.label)
                        .foregroundStyle(Ink.textSecondary)
                        // Read once, as the control's hint, not again on its own.
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(2)
            Spacer(minLength: Space.lg)
            control
                .accessibilityHint(description ?? "")
        }
        .frame(minHeight: Metric.settingRowPitch)
        .accessibilityElement(children: .contain)
    }
}

extension SettingRow where Control == AnyView {
    /// A row with a switch.
    static func toggle(_ title: String, description: String? = nil, isOn: Binding<Bool>,
                       isEnabled: Bool = true, help: String? = nil) -> SettingRow<AnyView> {
        SettingRow<AnyView>(title: title, description: description) {
            AnyView(
                Toggle(title, isOn: isOn)
                    .toggleStyle(KitSwitchStyle(title: title))
                    .disabled(!isEnabled)
                    .help(help ?? "")
                    .accessibilityLabel(title)
            )
        }
    }
}

extension Metric {
    /// KIT.md "Settings", Setting row: rows repeat every 56.
    static let settingRowPitch: CGFloat = 56
}
