import AppKit
import SilvanusKit
import SwiftUI

/// "Meeting detected" (KIT.md "Meeting detected prompt"): an in-app prompt that offers to
/// record a call that just started, in the recording controls' look: 364 wide, as tall as
/// its words, 20 inside, corner 16, opaque `Ink.barGround` with a gold `Ink.barEdge` edge
/// and the soft shadow. The app icon at 42, then the title (`promptTitle`) over the source
/// line (`barNote`, `barTextSecondary`), the question (`promptBody`), and Not now and Record
/// meeting on the trailing edge.
///
/// With an app detection can name: "Meeting detected", "Silvanus · <App> is using your
/// microphone", "Start recording this meeting?". With microphone evidence only: "Microphone
/// in use", "Start a recording?", and Start recording; it never claims a meeting it can't
/// see. No calendar line yet. It never starts recording on its own.
///
/// | State | Not now | Record meeting |
/// | rest | outlined, muted ivory edge, ivory text | gold fill, midnight text |
/// | hover / pressed | a little brighter / dimmer | a little brighter / dimmer |
/// | focused | 2 pt gold ring 3 outside | 2 pt gold ring 3 outside |
struct MeetingPrompt: View {
    var appName: String?
    var record: () -> Void
    var notNow: () -> Void

    var body: some View {
        let words = RecordingWords.prompt(appName: appName)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.md) {
                Image(nsImage: Brand.appIcon)
                    .resizable()
                    .frame(width: Metric.promptIcon, height: Metric.promptIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(words.title)
                        .kitType(.promptTitle)
                        .foregroundStyle(Ink.barText)
                        .accessibilityAddTraits(.isHeader)
                    Text(words.source)
                        .kitType(.barNote)
                        .foregroundStyle(Ink.barTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(words.question)
                .kitType(.promptBody)
                .foregroundStyle(Ink.barText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.lg)
            HStack(spacing: Space.sm) {
                Spacer(minLength: 0)
                Button(words.notNow, action: notNow)
                    .buttonStyle(PromptButtonStyle(primary: false))
                    .help("Hide this prompt; nothing is recorded")
                Button(words.record, action: record)
                    .buttonStyle(PromptButtonStyle(primary: true))
                    .help("Start recording now")
            }
            .padding(.top, Space.lg)
        }
        .padding(Metric.promptPadding)
        .frame(width: Metric.promptWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metric.promptCorner)
                .fill(Ink.barGround)
                .shadow(color: Ink.barGround.opacity(Metric.barShadowOpacity), radius: Metric.barShadowRadius,
                        y: Metric.barShadowY)
        }
        .overlay(RoundedRectangle(cornerRadius: Metric.promptCorner).strokeBorder(Ink.barEdge, lineWidth: Metric.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(words.title)
    }
}

/// The prompt's buttons: 40 tall, corner 8, 13 inside. Record meeting is gold with midnight
/// text (8.06:1); Not now is outlined in muted ivory.
struct PromptButtonStyle: ButtonStyle {
    var primary: Bool
    /// 40 in the prompt; the recording controls' note uses the bar's compact height.
    var height: CGFloat = Metric.promptButtonHeight

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, primary: primary, height: height)
    }

    private struct Content: View {
        let configuration: Configuration
        let primary: Bool
        let height: CGFloat
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.barButtonCorner)
            configuration.label
                .kitType(primary ? .promptButton : .label)
                .foregroundStyle(primary ? Ink.barGround : Ink.barText)
                .padding(.horizontal, Metric.promptButtonPadding)
                .frame(height: height)
                .background(shape.fill(primary ? Ink.barEdge : (hovering ? Ink.barRaised : Color.clear)))
                .overlay(shape.strokeBorder(primary ? Ink.barEdge : Ink.barTextSecondary, lineWidth: Metric.hairline))
                .brightness(configuration.isPressed ? -0.05 : hovering && primary ? 0.06 : 0)
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: Metric.barButtonCorner + Metric.gripGap)
                            .strokeBorder(Ink.barEdge, lineWidth: Metric.focusRing)
                            .padding(-Metric.gripGap)
                    }
                }
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
        }
    }
}

/// The prompt's window: a small always-on-top panel at the top right of the screen, shown
/// once per call while Silvanus isn't recording. It stays until Not now, Record meeting, a
/// recording starting, or the call ending (no countdown). It never takes focus from the app
/// in front and needs no notification permission. After Not now the menu bar keeps Record
/// Meeting until the call ends.
@MainActor
final class MeetingPromptPanel {
    private weak var model: AppModel?
    private var panel: NSPanel?
    /// For the checks: how many times the prompt was shown, and the name it last showed.
    private(set) var shown = 0
    private(set) var appName: String?

    init(model: AppModel) {
        self.model = model
    }

    var isShowing: Bool { panel != nil }

    /// Shows the prompt for a call. Never while recording.
    func show(appName: String?) {
        guard let model, !model.isRecording else { return }
        shown += 1
        self.appName = appName
        hide()
        makePanel(appName: appName)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func makePanel(appName: String?) {
        let view = MeetingPrompt(appName: appName,
                                 record: { [weak self] in self?.model?.recordDetectedCall() },
                                 notNow: { [weak self] in self?.hide() })
            .padding(Metric.barWindowMargin)
        let host = BarHostingView(rootView: view)
        let size = host.fittingSize
        host.setFrameSize(size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.title = RecordingWords.prompt(appName: appName).title
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.setAccessibilityLabel(p.title)
        if let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            // Top right, clear of the recording controls at the bottom center.
            p.setFrameOrigin(NSPoint(x: screen.maxX - size.width - Space.lg + Metric.barWindowMargin,
                                     y: screen.maxY - size.height - Space.lg + Metric.barWindowMargin))
        }
        p.orderFrontRegardless()
        panel = p
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(p.title). \(RecordingWords.prompt(appName: appName).question)",
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
