import SwiftUI

/// A setting's row in a Settings pane, from KIT.md "Settings": the title in `settingTitle`,
/// the description in `label` and `textSecondary` under it (then an optional one-line
/// footnote in the same style), and the control right-aligned. An optional `badge` follows
/// the title in `label` and `accentText` ("Recommended for this Mac").
/// Rows repeat every 56 pt. A control that can't be used yet passes `isEnabled: false` and a
/// `help` that says why.
struct SettingRow<Control: View>: View {
    let title: String
    var description: String?
    var footnote: String?
    var badge: String?
    @ViewBuilder var control: Control

    private var hint: String { [description, footnote].compactMap { $0 }.joined(separator: " ") }

    var body: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(title)
                        .kitType(.settingTitle)
                        .foregroundStyle(Ink.text)
                    if let badge {
                        Text(badge)
                            .kitType(.label)
                            .foregroundStyle(Ink.accentText)
                    }
                }
                if let description {
                    Text(description)
                        .kitType(.label)
                        .foregroundStyle(Ink.textSecondary)
                        // Read once, as the control's hint, not again on its own.
                        .accessibilityHidden(true)
                }
                if let footnote {
                    Text(footnote)
                        .kitType(.label)
                        .foregroundStyle(Ink.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(2)
            Spacer(minLength: Space.lg)
            control
                .accessibilityHint(hint)
        }
        .frame(minHeight: Metric.settingRowPitch)
        .accessibilityElement(children: .contain)
    }
}

extension SettingRow where Control == AnyView {
    /// A row with a switch.
    static func toggle(_ title: String, description: String? = nil, footnote: String? = nil, isOn: Binding<Bool>,
                       isEnabled: Bool = true, help: String? = nil) -> SettingRow<AnyView> {
        SettingRow<AnyView>(title: title, description: description, footnote: footnote) {
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
