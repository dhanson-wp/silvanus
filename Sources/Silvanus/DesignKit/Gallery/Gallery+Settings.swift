import SwiftUI

/// The Settings parts in the kit gallery: the switch, the bordered button, a setting row, and
/// the settings list, in every state, light and dark. Fictional words only.
struct SettingsGallery: View {
    private let states: [PartState] = [.rest, .hover, .pressed, .focused, .disabled]

    @State private var pane = SettingsPane.appearance

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Settings")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            VStack(alignment: .leading, spacing: Space.xxl) {
                Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(states, id: \.self) { state in
                            Text(state.rawValue)
                                .kitType(.meta)
                                .foregroundStyle(Ink.textSecondary)
                        }
                    }
                    switchRow("Switch, off", isOn: false)
                    switchRow("Switch, on", isOn: true)
                    GridRow {
                        label("Bordered button")
                        ForEach(states, id: \.self) { state in
                            Button("Start Recording") {}
                                .buttonStyle(KitButtonStyle())
                                .environment(\.forcedPartState, state)
                                .disabled(state == .disabled)
                        }
                    }
                    GridRow {
                        label("Bordered button, selected")
                        Button("Dark") {}
                            .buttonStyle(KitButtonStyle(isSelected: true))
                            .environment(\.forcedPartState, .selected)
                    }
                }
                HStack(alignment: .top, spacing: Space.xxl) {
                    VStack(alignment: .leading, spacing: 0) {
                        caption("Settings list, with the chosen row")
                        SettingsList(groups: SettingsPane.groups, selection: $pane)
                            .frame(width: Metric.sidebarWidth, height: Space.lg * 18)
                            .background(Ink.sidebar)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        caption("Setting rows")
                        VStack(alignment: .leading, spacing: 0) {
                            SettingRow.toggle("Show in Dock", description: "Keep Silvanus in the Dock while it's open.",
                                              isOn: .constant(true))
                            SettingRow.toggle("Open at login", description: "Start Silvanus when you log in.",
                                              isOn: .constant(false), isEnabled: false, help: "Coming soon")
                            SettingRow(title: "Theme", description: "Follow your Mac, or always use light or dark.") {
                                HStack(spacing: Space.sm) {
                                    ForEach(AppearanceChoice.allCases) { choice in
                                        Button(choice.title) {}
                                            .buttonStyle(KitButtonStyle(isSelected: choice == .system))
                                    }
                                }
                            }
                            SettingRow(title: "Model", description: "Turns audio into the transcript. Nothing leaves your Mac.") {
                                Text(SettingsPane.modelName)
                                    .kitType(.rowTitle)
                                    .foregroundStyle(Ink.textSecondary)
                            }
                        }
                        .padding(.horizontal, Metric.settingsPaneInset)
                        .frame(width: Space.lg * 40)
                        .background(Ink.canvas)
                    }
                }
            }
            .padding(Space.lg)
            .background(Ink.background)
        }
    }

    private func switchRow(_ title: String, isOn: Bool) -> some View {
        GridRow {
            label(title)
            ForEach(states, id: \.self) { state in
                Toggle(title, isOn: .constant(isOn))
                    .toggleStyle(KitSwitchStyle())
                    .environment(\.forcedPartState, state)
                    .disabled(state == .disabled)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .kitType(.label)
            .foregroundStyle(Ink.textSecondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .kitType(.meta)
            .foregroundStyle(Ink.textSecondary)
            .padding(.bottom, Space.sm)
    }
}
