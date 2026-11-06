import SwiftUI

/// The Settings panes, in the order the list shows them. Snapshot mode walks through every case.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, about, transcription

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .transcription: "Transcription"
        case .about: "About"
        }
    }

    var icon: KitIcon {
        switch self {
        case .general: .settingsGeneral
        case .appearance: .settingsAppearance
        case .transcription: .settingsAudio
        case .about: .settingsAbout
        }
    }

    /// The list's groups (KIT.md "Settings"): app panes, then the ones about speech.
    static let groups: [SettingsListGroup<SettingsPane>] = [
        SettingsListGroup(title: "App", items: [SettingsPane.general, .appearance, .about].map { item($0) }),
        SettingsListGroup(title: "AI", items: [SettingsPane.transcription].map { item($0) }),
    ]

    private static func item(_ pane: SettingsPane) -> SettingsListItem<SettingsPane> {
        SettingsListItem(id: pane, title: pane.title, icon: pane.icon)
    }

    /// Stop when the call ends: what it does, and a footnote on what it needs.
    static let stopWhenCallEndsDescription = "When the call app stops using audio, stop recording after a short countdown."
    static let stopWhenCallEndsFootnote = "Needs the Mac's per-app audio list; without it, waits for the call app to quit."

    /// The speech model, shown read-only until there is more than one.
    static let modelName = "Parakeet TDT v2, on this Mac"
}

/// The settings list, in the sidebar's column while Settings is open.
struct SettingsSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsList(groups: SettingsPane.groups, selection: $model.settingsPane)
    }
}

/// The chosen pane, in the canvas column while Settings is open, from KIT.md "Settings":
/// the pane on `Ink.canvas`, its content 24 after the divider, the page title in `title`
/// with its baseline at y 55, and the setting rows under it. Escape goes back to the meeting.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    /// The title's baseline, below the canvas's top edge (window y 55 less the 46 pt header).
    private static let titleBaseline: CGFloat = 55 - Metric.headerHeight
    /// The first row, from the canvas's top edge.
    private static let contentTop: CGFloat = Space.xxl * 2

    var body: some View {
        // The title hangs above the pane's top edge (its baseline is 9 below it), so it is an
        // overlay: a ZStack child would grow the stack upward and push everything down.
        pane(model.settingsPane)
            .padding(.horizontal, Metric.settingsPaneInset)
            .padding(.top, Self.contentTop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                Text(model.settingsPane.title)
                    .kitType(.title)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .alignmentGuide(.top) { [baseline = Self.titleBaseline] in $0[.firstTextBaseline] - baseline }
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Metric.settingsPaneInset)
            }
        .background {
            // Escape goes back. In the background so it works with nothing focused.
            Button("Back to Meeting") { model.closeSettings() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .id(model.settingsPane)
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            switch pane {
            case .general:
                SettingRow.toggle("Show in Dock", description: "Keep Silvanus in the Dock while it's open.",
                                  isOn: $model.showInDock)
                SettingRow.toggle("Prompt when a meeting starts",
                                  description: "When a call app starts using the microphone, offer to start recording.",
                                  isOn: $model.promptOnMeeting)
                SettingRow.toggle("Stop when the call ends",
                                  description: SettingsPane.stopWhenCallEndsDescription,
                                  footnote: SettingsPane.stopWhenCallEndsFootnote,
                                  isOn: $model.stopWhenCallEnds)
                SettingRow.toggle("Open at login", description: "Start Silvanus when you log in.",
                                  isOn: .constant(false), isEnabled: false, help: "Coming soon")
            case .appearance:
                SettingRow(title: "Theme", description: "Follow your Mac, or always use light or dark.") {
                    HStack(spacing: Space.sm) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Button(choice.title) { model.appearance = choice }
                                .buttonStyle(KitButtonStyle(isSelected: model.appearance == choice))
                                .accessibilityLabel("\(choice.title) theme")
                        }
                    }
                }
            case .transcription:
                SettingRow(title: "Model", description: "Turns audio into the transcript. Nothing leaves your Mac.") {
                    Text(SettingsPane.modelName)
                        .kitType(.rowTitle)
                        .foregroundStyle(Ink.textSecondary)
                        .textSelection(.enabled)
                }
            case .about:
                BrandAboutContent()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.section)
            }
        }
    }
}
