import SwiftUI

/// Every token, type role, and icon of the design kit, and later every part in every state.
/// The app shows it instead of its pages when `APP_KIT_GALLERY=1` is set, and the snapshot
/// command then writes kit-gallery-<set>-light.png and -dark.png:
///   APP_KIT_GALLERY=1 tools/snap.sh
///   APP_COLORS=reference APP_KIT_GALLERY=1 SILVANUS_SHOTS=/tmp/Silvanus-shots-reference tools/snap.sh
struct KitGallery: View {
    static let enabled = ProcessInfo.processInfo.environment["APP_KIT_GALLERY"] == "1"

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            Text("Design kit, \(ColorSet.active.rawValue) colors, \(scheme == .dark ? "dark" : "light")")
                .kitType(.title)
                .foregroundStyle(Ink.text)
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    section("Palette") {
                        ForEach(Swatch.palette(.active)) { swatch(name: $0.name, pair: $0.pair) }
                    }
                    section("Ink") {
                        ForEach(InkToken.allCases, id: \.self) { swatch(name: $0.rawValue, pair: $0.pair(.active)) }
                    }
                }
                section("Type") {
                    ForEach(KitType.allCases, id: \.self) { typeRow($0) }
                }
                section("Icons") {
                    ForEach(KitIcon.allCases, id: \.self) { iconRow($0) }
                }
            }
        }
        .padding(Space.xxl)
        .background(Ink.background)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            VStack(alignment: .leading, spacing: Space.sm, content: content)
                .padding(Space.lg)
                .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.rowCorner))
                .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }

    private func swatch(name: String, pair: InkPair) -> some View {
        HStack(spacing: Space.md) {
            RoundedRectangle(cornerRadius: Metric.buttonCorner)
                .fill(Color(light: pair.light, dark: pair.dark))
                .overlay(RoundedRectangle(cornerRadius: Metric.buttonCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
                .frame(width: Metric.controlHeight, height: Metric.controlHeight)
            Text(name)
                .kitType(.rowTitle)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Space.md)
            Text(String(format: "#%06X", pair.value(dark: scheme == .dark)))
                .kitType(.monoSmall)
                .foregroundStyle(Ink.textSecondary)
        }
        .frame(width: Space.lg * 16)
    }

    private func typeRow(_ type: KitType) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("\(type.rawValue), \(type.size.formatted()) \(type.weightName)\(type.isUppercase ? ", uppercase" : "")\(type.isMonospaced ? ", SF Mono" : "") / \(type.lineHeight.formatted())")
                .kitType(.meta)
                .foregroundStyle(Ink.textSecondary)
            Text(Self.sample(type))
                .kitType(type)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
        }
        .frame(width: Space.lg * 22, alignment: .leading)
    }

    private func iconRow(_ icon: KitIcon) -> some View {
        HStack(spacing: Space.md) {
            KitIconView(icon)
                .foregroundStyle(Ink.text)
                .background(Ink.selection)
                .frame(width: Metric.controlHeight, height: Metric.controlHeight)
            VStack(alignment: .leading, spacing: 0) {
                Text(icon.rawValue)
                    .kitType(.rowTitle)
                    .foregroundStyle(Ink.text)
                Text("\(icon.size.formatted()) pt, \(icon.symbol)")
                    .kitType(.meta)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(width: Space.lg * 14, alignment: .leading)
    }

    /// Fictional words in the glossary's terms.
    private static func sample(_ type: KitType) -> String {
        switch type {
        case .title: "Acme kickoff"
        case .heading: "Decisions"
        case .subheading: "Next steps"
        case .body: "We agreed to ship the editor on Thursday."
        case .transcript: "Let's walk through the launch plan first."
        case .rowTitle, .rowTitleSelected: "Acme kickoff with Sam Rivera"
        case .settingTitle: "Start at login"
        case .button: "Start Recording"
        case .dayHeading: "Today"
        case .tab: "My notes"
        case .chip: "Folder"
        case .label: "Sam Rivera"
        case .section: "App"
        case .meta: "Thu, Nov 5"
        case .monoTime: "09:30"
        case .monoSmall: "00:00 / 00:55"
        case .dayNumber: "5"
        }
    }
}

/// The gallery as the main window's page: scrolls, and starts snapshot mode.
struct KitGalleryPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            KitGallery()
        }
        .background(Ink.background)
        .task {
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}
