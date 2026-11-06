import AppKit
import SilvanusKit
import SwiftUI

/// The "Meeting detected" prompt's measures (provisional): a card the recording pill's
/// height plus one row of bordered buttons.
extension Metric {
    static let meetingPromptWidth: CGFloat = 300
    /// How long the prompt stays up when nobody answers it.
    static let meetingPromptSeconds: Double = 20
}

/// "Meeting detected", with Start Recording and Dismiss: a small card that offers to record
/// a call that just started. On the canvas fill with a 1 pt divider border, like the
/// recording pill. Not modal, and it never takes focus from the call.
///
/// | State | Contents |
/// | rest | title, one line, Start Recording (filled) and Dismiss (bordered) |
/// | hover / pressed / focused | as the bordered button |
struct MeetingPrompt: View {
    var start: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Meeting detected")
                .kitType(.settingTitle)
                .foregroundStyle(Ink.text)
            Text("A call is using the microphone.")
                .kitType(.label)
                .foregroundStyle(Ink.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.sm) {
                Spacer(minLength: 0)
                Button("Dismiss", action: dismiss)
                    .buttonStyle(KitButtonStyle())
                    .help("Hide this prompt")
                Button("Start Recording", action: start)
                    .buttonStyle(KitButtonStyle(isSelected: true))
                    .help("Record this meeting")
            }
            .padding(.top, Space.xs)
        }
        .padding(Space.md)
        .frame(width: Metric.meetingPromptWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metric.canvasCorner)
                .fill(Ink.canvas)
                .shadow(radius: Space.xs, y: Space.xs / 2)
        }
        .overlay(RoundedRectangle(cornerRadius: Metric.canvasCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting detected")
    }
}

/// The prompt's window: a small always-on-top panel near the top right of the screen,
/// shown when the call detector notices a meeting start while Silvanus isn't recording. It
/// hides itself after 20 seconds, on Dismiss, or once a recording starts. It never takes
/// focus from the app in front, and needs no notification permission.
@MainActor
final class MeetingPromptPanel {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var timeout: Task<Void, Never>?
    /// For the checks: how many times the prompt was shown.
    private(set) var shown = 0
    /// How long it stays up; the self-test shortens it.
    var seconds = Metric.meetingPromptSeconds

    init(model: AppModel) {
        self.model = model
    }

    var isShowing: Bool { panel != nil }

    /// Shows the prompt, or restarts its 20 seconds if it's up. Never while recording.
    func show() {
        guard let model, !model.isRecording else { return }
        shown += 1
        if panel == nil { makePanel() }
        timeout?.cancel()
        let seconds = seconds
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        timeout?.cancel()
        timeout = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// Start Recording: records like ⇧⌘R. When access is missing, the permissions sheet
    /// opens in the main window, so bring it forward.
    func startRecording() {
        hide()
        guard let model else { return }
        model.record(.startRecording)
        if model.permissionsRequest != nil {
            NSApp.activate()
            NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }
    }

    private func makePanel() {
        let view = MeetingPrompt(start: { [weak self] in self?.startRecording() },
                                 dismiss: { [weak self] in self?.hide() })
            .padding(Space.md)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.setFrameSize(size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.setAccessibilityLabel("Meeting detected")
        if let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            // Below the recording pill's default spot (PillPlacement), right-aligned with it, so
            // the two never overlap: the prompt shows only when no recording is up, but a
            // recording can start while it's open.
            let pillBottom = PillPlacement.defaultAnchor(in: screen).y - Metric.recordingPillHeight
            p.setFrameOrigin(NSPoint(x: PillPlacement.defaultAnchor(in: screen).x + Space.md - size.width,
                                     y: pillBottom - Space.sm + Space.md - size.height))
        }
        p.orderFrontRegardless()
        panel = p
    }
}
