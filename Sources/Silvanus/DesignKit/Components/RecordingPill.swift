import SilvanusKit
import SwiftUI

/// KIT.md "Floating recording pill": its measures.
extension Metric {
    static let recordingPillHeight: CGFloat = 34
    /// At rest the capsule hugs its contents but is never narrower than this.
    static let recordingPillMinWidth: CGFloat = 84
    /// Inside the capsule's ends at rest; the hover buttons sit `recordingPillButtonInset` in.
    static let recordingPillInset: CGFloat = 12
    static let recordingPillButtonInset: CGFloat = 3
    /// Between the wave, the time, and the buttons.
    static let recordingPillGap: CGFloat = 6
    /// Pause and Stop: round, 28 across.
    static let recordingPillButton: CGFloat = 28
    /// The warning or failure dot, ringed, half over the capsule's top trailing corner.
    static let recordingPillDot: CGFloat = 8
    /// The live wave: bars 2 wide, 2 apart, from 3 to 12 tall.
    static let waveBar: CGFloat = 2
    static let waveMin: CGFloat = 3
    static let waveMax: CGFloat = 12
    /// The Transcribing… bar in the canvas header.
    static let progressWidth: CGFloat = 64
    static let progressHeight: CGFloat = 4
}

/// The recording's loudness for the live waves: the last few levels, 0 to 1, sampled 10
/// times a second by the recorder (never per audio buffer). Only the waves read it, so
/// a new level redraws them and nothing else.
@Observable
final class LevelMeter {
    static let bars = 5
    private(set) var levels: [Float] = Array(repeating: 0, count: LevelMeter.bars)

    init(levels: [Float]? = nil) {
        if let levels { self.levels = Array(levels.suffix(Self.bars)) }
    }

    func push(_ level: Float) {
        levels = Array((levels + [min(1, max(0, level))]).suffix(Self.bars))
    }

    func reset() { levels = Array(repeating: 0, count: Self.bars) }
}

/// A small live wave: one bar per level in the meter, rounded, in the current foreground
/// style. Quiet bars keep a 3 pt stub so the wave reads as live.
struct LiveWave: View {
    let meter: LevelMeter

    /// Five bars and their gaps.
    static let width = CGFloat(LevelMeter.bars) * Metric.waveBar + CGFloat(LevelMeter.bars - 1) * Metric.waveBar

    var body: some View {
        HStack(alignment: .center, spacing: Metric.waveBar) {
            ForEach(Array(meter.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .frame(width: Metric.waveBar, height: Self.height(level))
            }
        }
        .frame(height: Metric.waveMax)
        .animation(Motion.hover, value: meter.levels)
        .accessibilityHidden(true)
    }

    /// Speech peaks sit low on a linear scale, so the square root lifts them.
    static func height(_ level: Float) -> CGFloat {
        let lifted = CGFloat(min(1, sqrt(max(0, level)) * 1.4))
        return Metric.waveMin + (Metric.waveMax - Metric.waveMin) * lifted
    }
}

/// The phases of a drag on the pill's body, reported to the panel that moves it.
enum PillDrag { case began, moved, ended }

/// The floating recording pill (KIT.md "Floating recording pill"): a capsule 34 tall and
/// about 84 wide on `Ink.pillGround` (dark in both themes) with a 5-bar live wave in
/// `Ink.recording` and the elapsed time in `monoTime`. Hovering grows it, with `Motion.pill`,
/// to show Pause (disabled until Phase 2) and Stop. Clicking the body opens the meeting; a
/// drag on the body moves the pill. A warning or a failure shows as a dot on the top
/// trailing corner, with its text as the tooltip.
///
/// | State | Contents |
/// | recording | wave, time; hover adds Pause (disabled) and Stop |
/// | warning | the same, with an amber dot; the warning is the tooltip |
/// | stopping | spinner for the wave, "Stopping" for the time, Stop disabled |
/// | failed | red dot, "Stopped", no time; hover shows Close; the reason is the tooltip |
/// | hover on a button | a 15% ivory fill |
/// | focused | 2 pt focus ring on the focused button |
///
/// VoiceOver reads one element, "Recording, 12 minutes", with Stop (or Close) as an action.
struct RecordingPill: View {
    enum Status: Equatable {
        case recording(since: Date)
        case stopping
        case failed(String)
    }

    var status: Status
    /// The meeting's title, for the tooltip and VoiceOver.
    var title: String
    /// A recording warning ("Recording your microphone only…"), shown as the dot.
    var warning: String?
    var meter: LevelMeter
    /// The gallery forces the hover state; nil follows the pointer.
    var forcedHover: Bool?
    /// The body brings Silvanus forward on the meeting.
    var open: (() -> Void)?
    var stop: (() -> Void)?
    /// Closes a failed pill.
    var dismiss: (() -> Void)?
    /// The panel moves the window while the body is dragged.
    var drag: ((PillDrag) -> Void)?
    /// The panel resizes its window to fit the expanded capsule.
    var hoverChanged: ((Bool) -> Void)?

    @State private var hovering = false
    @State private var dragging = false

    init(status: Status, title: String = "", warning: String? = nil, meter: LevelMeter, forcedHover: Bool? = nil,
         open: (() -> Void)? = nil, stop: (() -> Void)? = nil, dismiss: (() -> Void)? = nil,
         drag: ((PillDrag) -> Void)? = nil, hoverChanged: ((Bool) -> Void)? = nil) {
        self.status = status
        self.title = title
        self.warning = warning
        self.meter = meter
        self.forcedHover = forcedHover
        self.open = open
        self.stop = stop
        self.dismiss = dismiss
        self.drag = drag
        self.hoverChanged = hoverChanged
    }

    var body: some View {
        // The one-second tick lives here, inside the panel's pill, never in the menu bar.
        if case let .recording(since) = status {
            TimelineView(.periodic(from: since, by: 1)) { context in
                capsule(elapsed: context.date.timeIntervalSince(since))
            }
        } else {
            capsule(elapsed: nil)
        }
    }

    private var expanded: Bool { forcedHover ?? hovering }
    private var isFailed: Bool { if case .failed = status { true } else { false } }
    private var canStop: Bool { if case .recording = status { true } else { false } }

    /// What the dot stands for: the failure's reason, else the recording warning.
    private var notice: String? {
        if case let .failed(reason) = status { return reason }
        return warning
    }

    private func capsule(elapsed: TimeInterval?) -> some View {
        HStack(spacing: Metric.recordingPillGap) {
            leading
            if let elapsed {
                Text(Clock.text(elapsed))
                    .kitType(.monoTime)
                    .foregroundStyle(Ink.onPillGround)
                    .fixedSize()
            } else if isFailed || status == .stopping {
                Text(isFailed ? "Stopped" : "Stopping")
                    .kitType(.label)
                    .foregroundStyle(Ink.onPillGround)
                    .fixedSize()
            }
            if expanded {
                controls
                    .transition(.opacity)
            }
        }
        .padding(.leading, Metric.recordingPillInset)
        .padding(.trailing, expanded ? Metric.recordingPillButtonInset : Metric.recordingPillInset)
        .frame(minWidth: Metric.recordingPillMinWidth, minHeight: Metric.recordingPillHeight,
               maxHeight: Metric.recordingPillHeight)
        .background {
            Capsule()
                .fill(Ink.pillGround)
                // The system's shadow color: dark in both themes.
                .shadow(radius: Space.xs, y: Space.xs / 2)
                // A hairline in the pill's own ink, so the dark capsule still shows over a dark window.
                .overlay(CapsuleRing(width: Metric.hairline).fill(Ink.onPillGround.opacity(0.18), style: FillStyle(eoFill: true)))
        }
        .overlay(alignment: .topTrailing) { dot }
        .contentShape(Capsule())
        .onTapGesture { open?() }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { _ in
                    if !dragging { dragging = true; drag?(.began) }
                    drag?(.moved)
                }
                .onEnded { _ in
                    dragging = false
                    drag?(.ended)
                }
        )
        .onHover { inside in
            guard forcedHover == nil else { return }
            hovering = inside
            hoverChanged?(inside)
        }
        .animation(Motion.pill, value: expanded)
        .help(notice ?? (title.isEmpty ? "Open Silvanus" : "Open \(title)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(elapsed))
        .accessibilityValue(notice ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { open?() }
        .accessibilityAction(named: Text(isFailed ? "Close" : "Stop")) { isFailed ? dismiss?() : (canStop ? stop?() : ()) }
    }

    @ViewBuilder private var leading: some View {
        if status == .stopping {
            ProgressView()
                .controlSize(.mini)
                .tint(Ink.onPillGround)
                .frame(width: LiveWave.width, height: Metric.waveMax)
        } else {
            // A failed pill shows the wave flat: nothing is being heard.
            LiveWave(meter: isFailed ? LevelMeter() : meter)
                .foregroundStyle(Ink.recording)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            if isFailed {
                PillButton(icon: .close, title: "Close", help: "Close this message", action: dismiss)
            } else {
                PillButton(icon: .pause, title: "Pause", help: "Pause is coming soon", action: nil)
                PillButton(icon: .stop, title: "Stop", help: "Stop recording; transcription starts (⇧⌘R)",
                           action: canStop ? stop : nil)
            }
        }
    }

    @ViewBuilder private var dot: some View {
        if notice != nil {
            Circle()
                .fill(isFailed ? Ink.recording : Ink.warning)
                .frame(width: Metric.recordingPillDot, height: Metric.recordingPillDot)
                .overlay(Circle().strokeBorder(Ink.onPillGround, lineWidth: 1.5))
                .padding(Metric.recordingPillDot / 2)
                // Centered on the capsule's rim at 45°, 5 in from the corner.
                .offset(x: 3, y: -3)
                .allowsHitTesting(false)
        }
    }

    private func label(_ elapsed: TimeInterval?) -> String {
        switch status {
        case .recording: "Recording, \(Clock.spokenMinutes(elapsed ?? 0))"
        case .stopping: "Stopping the recording"
        case .failed: "Recording stopped"
        }
    }
}

/// A capsule's outline as a filled ring. A stroked capsule drew short stubs at its two
/// ends in the snapshot renderer; a fill has no seam to do that.
private struct CapsuleRing: Shape {
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Capsule().path(in: rect)
        path.addPath(Capsule().path(in: rect.insetBy(dx: width, dy: width)))
        return path
    }
}

/// A round 28 pt button on the dark pill: ivory icon, a 15% ivory fill on hover, 40% when
/// disabled (a nil action).
private struct PillButton: View {
    let icon: KitIcon
    let title: String
    let help: String
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            KitIconView(icon)
                .frame(width: Metric.recordingPillButton, height: Metric.recordingPillButton)
                .contentShape(Circle())
        }
        .buttonStyle(PillButtonStyle())
        .disabled(action == nil)
        .help(help)
        .accessibilityLabel(title)
    }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Ink.onPillGround.opacity(isEnabled ? 1 : 0.4))
                .background(Circle().fill(Ink.onPillGround.opacity(isEnabled && (hovering || configuration.isPressed) ? 0.15 : 0)))
                .overlay { if isFocused { Circle().strokeBorder(Ink.onPillGround, lineWidth: 2) } }
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
        }
    }
}

/// "Transcribing…" with a determinate bar, in the canvas header while the after-call pass
/// runs. The bar's track is the divider; its fill the accent (fill only). `compact` drops the
/// label (the tooltip keeps it) where the header is short of room.
struct TranscribingIndicator: View {
    var progress: Double
    var compact = false

    var body: some View {
        HStack(spacing: Space.sm) {
            if !compact {
                Text("Transcribing…")
                    .kitType(.label)
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Capsule()
                .fill(Ink.divider)
                .frame(width: Metric.progressWidth, height: Metric.progressHeight)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Ink.accent)
                        .frame(width: Metric.progressWidth * min(1, max(0, progress)), height: Metric.progressHeight)
                }
                .animation(Motion.select, value: progress)
        }
        .frame(height: Metric.controlHeight)
        .contentShape(Rectangle())
        .help("Transcribing…")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
    }
}

/// A one-line notice over the bottom of the canvas: what happened, and an optional action
/// (Retry) and close. Not modal: the meeting stays usable under it.
struct NoticeBanner: View {
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.md) {
            Text(message)
                .kitType(.label)
                .foregroundStyle(Ink.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .kitType(.button)
            }
            if let dismiss {
                Button("Close", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.textSecondary)
                    .help("Close this message")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.buttonCorner))
        .overlay(RoundedRectangle(cornerRadius: Metric.buttonCorner).stroke(Ink.divider, lineWidth: Metric.hairline))
        .padding(.horizontal, Space.md)
        .accessibilityElement(children: .contain)
    }
}
