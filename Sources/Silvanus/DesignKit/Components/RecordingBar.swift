import AppKit
import SilvanusKit
import SwiftUI

/// KIT.md "Recording controls": the approved compact bar's measures.
extension Metric {
    static let barWidth: CGFloat = 264
    static let barHeight: CGFloat = 48
    static let barCorner: CGFloat = 13
    /// Inside the bar's edge, and between its parts.
    static let barInset: CGFloat = 5
    static let barGap: CGFloat = 6
    /// The grip: six dots and the scribe in one 34 × 36 drag target.
    static let gripWidth: CGFloat = 34
    static let gripHeight: CGFloat = 36
    static let gripCorner: CGFloat = 8
    static let gripDot: CGFloat = 2
    /// The dots' columns and rows, center to center.
    static let gripDotPitchX: CGFloat = 4
    static let gripDotPitchY: CGFloat = 5
    static let gripGap: CGFloat = 3
    static let barScribe: CGFloat = 18
    static let barStateDot: CGFloat = 5
    static let barStateGap: CGFloat = 5
    /// The five level bars: 3 wide, 2 apart, 3 to 18 tall, in a 26 × 24 box.
    static let levelBoxWidth: CGFloat = 26
    static let levelBoxHeight: CGFloat = 24
    static let levelBar: CGFloat = 3
    static let levelGap: CGFloat = 2
    static let levelMin: CGFloat = 3
    static let levelMax: CGFloat = 18
    /// Pause/Resume and Stop: 36 × 36 targets, corner 8.
    static let barButton: CGFloat = 36
    static let barButtonCorner: CGFloat = 8
    /// The note above the bar while paused or with audio lost: 9 above it.
    static let barNoteGap: CGFloat = 9
    static let barNoteCorner: CGFloat = 10
    static let barNotePaddingX: CGFloat = 14
    static let barNotePaddingY: CGFloat = 10
    /// The soft offset shadow under the bar and the prompt; the panel leaves room for it.
    static let barShadowRadius: CGFloat = 12
    static let barShadowY: CGFloat = 4
    static let barShadowOpacity: Double = 0.31
    static let barWindowMargin: CGFloat = 16
    /// The Meeting detected prompt.
    static let promptWidth: CGFloat = 364
    static let promptPadding: CGFloat = 20
    static let promptCorner: CGFloat = 16
    static let promptIcon: CGFloat = 42
    static let promptButtonHeight: CGFloat = 40
    static let promptButtonPadding: CGFloat = 13
}

/// What moves the recording controls' window: the panel, from the grip.
@MainActor
protocol BarMover: AnyObject {
    func dragBegan(at point: NSPoint)
    func dragMoved(to point: NSPoint)
    func dragEnded()
    /// Arrow keys on the focused grip: 8 points, 24 with Shift.
    func nudge(dx: CGFloat, dy: CGFloat)
    /// Home on the focused grip, and Reset Recording Controls Position.
    func resetPosition()
}

/// How a bar button is drawn in the gallery; nil in life (the pointer and focus decide).
enum BarButtonLook: Equatable {
    case rest, hover, pressed, focused
}

/// The recording controls (KIT.md "Recording controls"): Derek's approved compact bar, 264
/// × 48 on opaque `Ink.barGround` with a 1 pt `Ink.barEdge` gold edge, corner 13, and a
/// soft shadow. From leading to trailing: the grip (six dots and the scribe, the only drag
/// region), the state ("Recording", "Paused", "Audio lost", or "Mic only") with its dot over
/// the captured time, five gold level bars, Pause/Resume (Retry while audio is lost), and
/// Stop. While paused or with audio lost, a note sits 9 above it.
///
/// | State | State line | Time | Bars | First button |
/// | recording | gold dot, Recording | counts up, "elapsed" | follow the audio | Pause |
/// | mic only | gold dot, Mic only | counts up, "elapsed" | follow the audio | Pause |
/// | paused | muted square, Paused | held, "paused" | flat | Resume |
/// | audio lost | gold dot, Audio lost | held, "stopped" | flat | Retry |
/// | quiet | as recording | counts up | flat, muted | Pause |
/// | hover / pressed | a raised fill (Pause) or a brighter ivory (Stop); pressed dims a little |
/// | focused | a 2 pt gold ring 3 outside the button |
///
/// VoiceOver: the group is "Silvanus recording controls"; the state reads as one element
/// ("Recording, 12 minutes"), the level bars are hidden, and each button has a label and a
/// tooltip. The time and the bars are never announced as they change; state changes are
/// (RecordingPanel).
struct RecordingControls: View {
    enum Status: Equatable {
        case recording(since: Date)
        case paused(elapsed: TimeInterval)
        case lost(elapsed: TimeInterval, reason: String)
    }

    var status: Status
    /// Why call audio is down, while the microphone records on its own.
    var callAudioDown: String?
    /// A recording warning, for the state's tooltip.
    var warning: String?
    var meter: LevelMeter
    var togglePause: () -> Void = {}
    var retry: () -> Void = {}
    var stop: () -> Void = {}
    /// The panel, which the grip moves. Nil in the gallery.
    weak var mover: BarMover?
    /// The gallery forces a look on each button and Reduce Motion.
    var pauseLook: BarButtonLook?
    var stopLook: BarButtonLook?
    var reduceMotion: Bool?

    var body: some View {
        VStack(spacing: Metric.barNoteGap) {
            if let note {
                BarNote(text: note)
            }
            bar
        }
        .fixedSize()
    }

    /// The note above the bar: paused, or audio lost.
    var note: String? {
        switch status {
        case .recording: nil
        case .paused: RecordingWords.pausedNote
        case .lost: RecordingWords.lostNote(track: Recorder.micTrack)
        }
    }

    private var bar: some View {
        HStack(spacing: Metric.barGap) {
            GripHandle(mover: mover)
            readout
            BarLevels(meter: meter, live: isCapturing, reduceMotion: reduceMotion)
            pauseButton
            Button(action: stop) {
                KitIconView(.barStop)
            }
            .buttonStyle(BarButtonStyle(solid: true, look: stopLook))
            .help("Stop recording")
            .accessibilityLabel("Stop recording")
        }
        .padding(Metric.barInset)
        .frame(width: Metric.barWidth, height: Metric.barHeight)
        .background {
            RoundedRectangle(cornerRadius: Metric.barCorner)
                .fill(Ink.barGround)
                .shadow(color: Ink.barGround.opacity(Metric.barShadowOpacity), radius: Metric.barShadowRadius,
                        y: Metric.barShadowY)
        }
        .overlay(RoundedRectangle(cornerRadius: Metric.barCorner).strokeBorder(Ink.barEdge, lineWidth: Metric.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Silvanus recording controls")
    }

    private var isCapturing: Bool { if case .recording = status { true } else { false } }
    private var isPaused: Bool { if case .paused = status { true } else { false } }
    private var isLost: Bool { if case .lost = status { true } else { false } }

    private var pauseButton: some View {
        let (icon, title, action): (KitIcon, String, () -> Void) = switch status {
        case .recording: (.barPause, "Pause recording", togglePause)
        case .paused: (.barResume, "Resume recording", togglePause)
        case .lost: (.barResume, "Retry audio capture", retry)
        }
        return Button(action: action) {
            KitIconView(icon)
        }
        .buttonStyle(BarButtonStyle(solid: false, look: pauseLook))
        .help(title)
        .accessibilityLabel(title)
    }

    // The one-second tick lives here, inside the panel, never in the menu bar.
    @ViewBuilder private var readout: some View {
        switch status {
        case let .recording(since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                readoutLines(elapsed: context.date.timeIntervalSince(since))
            }
        case let .paused(elapsed), let .lost(elapsed, _):
            readoutLines(elapsed: elapsed)
        }
    }

    private var stateWord: String {
        switch status {
        case .recording: callAudioDown == nil ? RecordingWords.recording : RecordingWords.micOnly
        case .paused: RecordingWords.paused
        case .lost: RecordingWords.audioLost
        }
    }

    private var stateHelp: String {
        switch status {
        case .recording:
            [callAudioDown.map { "\(Recorder.micOnly) \($0)" }, warning].compactMap { $0 }.joined(separator: " ")
        case .paused: RecordingWords.pausedNote
        case let .lost(_, reason): reason
        }
    }

    private func readoutLines(elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metric.barStateGap) {
                stateDot
                Text(stateWord)
                    .kitType(.barState)
                    .foregroundStyle(Ink.barText)
            }
            Text("\(Clock.text(elapsed)) \(RecordingWords.timeSuffix(paused: isPaused, interrupted: isLost))")
                .kitType(.barTime)
                .foregroundStyle(Ink.barTextSecondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(stateHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stateWord)
        // To the minute, so a focused VoiceOver cursor isn't read a new value every second.
        .accessibilityValue(Clock.spokenMinutes(elapsed) + (stateHelp.isEmpty ? "" : ". \(stateHelp)"))
    }

    @ViewBuilder private var stateDot: some View {
        if isPaused {
            RoundedRectangle(cornerRadius: Metric.hairline)
                .fill(Ink.barTextSecondary)
                .frame(width: Metric.barStateDot, height: Metric.barStateDot)
        } else {
            Circle()
                .fill(Ink.barEdge)
                .frame(width: Metric.barStateDot, height: Metric.barStateDot)
        }
    }
}

/// The note above the bar: "Audio isn't being saved." while paused; what stopped while
/// audio is lost. Midnight with a muted ivory edge, the bar's width.
struct BarNote: View {
    var text: String

    var body: some View {
        Text(text)
            .kitType(.barNote)
            .foregroundStyle(Ink.barText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Metric.barWidth - 2 * Metric.barNotePaddingX, alignment: .leading)
            .padding(.horizontal, Metric.barNotePaddingX)
            .padding(.vertical, Metric.barNotePaddingY)
            .background {
                RoundedRectangle(cornerRadius: Metric.barNoteCorner)
                    .fill(Ink.barGround)
                    .shadow(color: Ink.barGround.opacity(Metric.barShadowOpacity / 2), radius: Metric.barShadowRadius / 2,
                            y: Metric.barShadowY / 2)
            }
            .overlay(RoundedRectangle(cornerRadius: Metric.barNoteCorner)
                .strokeBorder(Ink.barTextSecondary, lineWidth: Metric.hairline))
    }
}

/// The five level bars: the meter's last five smoothed levels, gold while there's sound,
/// flat and muted when it's quiet, paused, or audio is lost. Reduce Motion shows a steady
/// shape while there's sound instead of moving bars. Hidden from VoiceOver.
struct BarLevels: View {
    let meter: LevelMeter
    /// False while paused or with audio lost: flat.
    var live: Bool
    var reduceMotion: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// The steady shape for Reduce Motion, as levels.
    static let steady: [Float] = [0.3, 0.6, 0.9, 0.6, 0.3]

    var body: some View {
        let still = reduceMotion ?? systemReduceMotion
        let active = live && meter.isActive
        let levels: [Float] = !live ? Array(repeating: 0, count: LevelMeter.bars)
            : still ? (active ? Self.steady : Array(repeating: 0, count: LevelMeter.bars)) : meter.levels
        HStack(spacing: Metric.levelGap) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: Metric.levelBar / 2)
                    .fill(active ? Ink.barEdge : Ink.barTextSecondary)
                    .frame(width: Metric.levelBar, height: Self.height(level))
            }
        }
        .frame(width: Metric.levelBoxWidth, height: Metric.levelBoxHeight)
        .animation(still ? nil : Motion.level, value: levels)
        .accessibilityHidden(true)
    }

    static func height(_ level: Float) -> CGFloat {
        Metric.levelMin + (Metric.levelMax - Metric.levelMin) * CGFloat(min(1, max(0, level)))
    }
}

/// The grip: six muted ivory dots and the scribe, the bar's only drag region. In life an
/// AppKit view under the drawing takes the drag, the arrow keys, and the hover fill.
struct GripHandle: View {
    weak var mover: BarMover?
    var forcedHover = false

    var body: some View {
        HStack(spacing: Metric.gripGap) {
            dots
            Image(nsImage: Brand.menuBarGlyph)
                .renderingMode(.template)
                .resizable()
                .frame(width: Metric.barScribe, height: Metric.barScribe)
                .foregroundStyle(Ink.barText)
        }
        .frame(width: Metric.gripWidth, height: Metric.gripHeight)
        .allowsHitTesting(false)
        .background {
            if let mover {
                GripTarget(mover: mover)
            } else if forcedHover {
                RoundedRectangle(cornerRadius: Metric.gripCorner).fill(Ink.barRaised)
            }
        }
        .accessibilityHidden(mover == nil)
    }

    private var dots: some View {
        VStack(spacing: Metric.gripDotPitchY - Metric.gripDot) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: Metric.gripDotPitchX - Metric.gripDot) {
                    Circle().frame(width: Metric.gripDot, height: Metric.gripDot)
                    Circle().frame(width: Metric.gripDot, height: Metric.gripDot)
                }
            }
        }
        .foregroundStyle(Ink.barTextSecondary)
    }
}

/// The grip's AppKit view: a drag moves the window (never a click on a button), a plain
/// click focuses it for the arrow keys, and Home puts the bar back. It never moves the
/// window by its background, and the first click works though the panel isn't key.
struct GripTarget: NSViewRepresentable {
    let mover: BarMover

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.mover = mover
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.mover = mover
    }
}

final class GripView: NSView {
    weak var mover: BarMover?
    private var dragged = false
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?

    static let step: CGFloat = 8
    static let bigStep: CGFloat = 24

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        NSCursor.closedHand.push()
        mover?.dragBegan(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        dragged = true
        mover?.dragMoved(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        mover?.dragEnded()
        // A click without a drag focuses the grip, so the arrow keys move the bar. Only a
        // deliberate click takes the keyboard from the app in front.
        if !dragged {
            window?.makeKey()
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        let step = event.modifierFlags.contains(.shift) ? Self.bigStep : Self.step
        switch event.specialKey {
        case .leftArrow: mover?.nudge(dx: -step, dy: 0)
        case .rightArrow: mover?.nudge(dx: step, dy: 0)
        case .upArrow: mover?.nudge(dx: 0, dy: step)
        case .downArrow: mover?.nudge(dx: 0, dy: -step)
        case .home: mover?.resetPosition()
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: Metric.gripCorner,
                                 yRadius: Metric.gripCorner)
        if hovering {
            Ink.appKit(.barRaised).setFill()
            shape.fill()
        }
        if window?.isKeyWindow == true, window?.firstResponder === self {
            Ink.appKit(.barEdge).setStroke()
            shape.lineWidth = Metric.focusRing
            shape.stroke()
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .handle }
    override func accessibilityLabel() -> String? { "Move recording controls" }
    override func accessibilityHelp() -> String? {
        "Drag, or use the arrow keys; Shift moves farther, and Home puts the controls back."
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let moves: [(String, CGFloat, CGFloat)] = [("Move left", -Self.bigStep, 0), ("Move right", Self.bigStep, 0),
                                                   ("Move up", 0, Self.bigStep), ("Move down", 0, -Self.bigStep)]
        var actions = moves.map { name, dx, dy in
            NSAccessibilityCustomAction(name: name) { [weak self] in
                self?.mover?.nudge(dx: dx, dy: dy)
                return true
            }
        }
        actions.append(NSAccessibilityCustomAction(name: "Reset position") { [weak self] in
            self?.mover?.resetPosition()
            return true
        })
        return actions
    }
}

/// Pause/Resume (outlined: a muted ivory edge, ivory icon) and Stop (solid ivory, midnight
/// icon): 36 × 36, corner 8. Hover raises the outlined one's fill and brightens the solid
/// one; pressed dims a little; focus is a 2 pt gold ring 3 outside.
struct BarButtonStyle: ButtonStyle {
    var solid: Bool
    var look: BarButtonLook?

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, solid: solid, look: look)
    }

    private struct Content: View {
        let configuration: Configuration
        let solid: Bool
        let look: BarButtonLook?
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let hover = look.map { $0 == .hover } ?? hovering
            let pressed = look.map { $0 == .pressed } ?? configuration.isPressed
            let focused = look.map { $0 == .focused } ?? isFocused
            let shape = RoundedRectangle(cornerRadius: Metric.barButtonCorner)
            configuration.label
                .foregroundStyle(solid ? Ink.barGround : Ink.barText)
                .frame(width: Metric.barButton, height: Metric.barButton)
                .background(shape.fill(solid ? Ink.barText : (hover || pressed ? Ink.barRaised : Color.clear)))
                .overlay(shape.strokeBorder(solid ? Ink.barText : Ink.barTextSecondary, lineWidth: Metric.hairline))
                .brightness(pressed ? -0.05 : hover && solid ? 0.06 : 0)
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: Metric.barButtonCorner + Metric.gripGap)
                            .strokeBorder(Ink.barEdge, lineWidth: Metric.focusRing)
                            .padding(-Metric.gripGap)
                    }
                }
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hover)
        }
    }
}
