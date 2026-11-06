import SilvanusKit
import SwiftUI

/// KIT.md "Floating recording pill": its measures (provisional, from the reference's
/// floating bar and the 46 / 28 control rhythm).
extension Metric {
    static let recordingPillHeight: CGFloat = 40
    static let recordingPillWidth: CGFloat = 320
    /// The live button and the trailing buttons sit 6 inside the bar's ends.
    static let recordingPillInset: CGFloat = 6
    /// Between the live button and the line of text.
    static let recordingPillGap: CGFloat = 10
    /// The live wave: bars 2 wide, 2 apart, from 3 to 12 tall.
    static let waveBar: CGFloat = 2
    static let waveMin: CGFloat = 3
    static let waveMax: CGFloat = 12
    /// The Transcribing… bar in the canvas header.
    static let progressWidth: CGFloat = 64
    static let progressHeight: CGFloat = 4
}

extension Motion {
    /// The live button's 1 Hz pulse while recording.
    static let pulse = Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
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

/// The floating recording pill (KIT.md "Floating recording pill", provisional): a bar 40
/// tall, fully rounded, on the canvas fill with a 1 pt divider border. The live button
/// (recording fill, ivory wave) at 6 inside the leading end, the meeting's title (or a
/// warning) truncating, the elapsed time, then Pause (disabled until Phase 2) and Stop, 6
/// inside the trailing end.
///
/// | State | Contents |
/// | recording | live button pulses at 1 Hz, time counts up |
/// | stopping | spinner in the live button, Stop disabled |
/// | failed | the reason in recordingText, no time; Stop becomes Close, which dismisses it |
/// | hover on a button | as the icon button |
/// | focused | 2 pt focus ring on the focused button |
struct RecordingPill: View {
    enum Status: Equatable {
        case recording(since: Date)
        case stopping
        case failed(String)
    }

    var status: Status
    /// The meeting's title, or a warning ("Recording your microphone only…").
    var line: String
    var meter: LevelMeter
    /// The live button brings Silvanus forward.
    var open: (() -> Void)?
    var stop: (() -> Void)?
    /// Closes a failed pill.
    var dismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 0) {
            liveButton
                .padding(.trailing, Metric.recordingPillGap)
            Text(lineText)
                .kitType(.rowTitle)
                .foregroundStyle(isFailed ? Ink.recordingText : Ink.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(lineText)
            if case let .recording(since) = status {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Clock.text(context.date.timeIntervalSince(since)))
                        .kitType(.monoTime)
                        .foregroundStyle(Ink.text)
                        .accessibilityLabel("Recording for \(Clock.spoken(context.date.timeIntervalSince(since)))")
                }
                .padding(.horizontal, Space.sm)
            }
            IconButton(.pause, "Pause", help: "Pause comes in a later version", action: nil)
            if isFailed {
                IconButton(.close, "Close", help: "Close this message", action: dismiss)
            } else {
                IconButton(.stop, "Stop", help: "Stop recording; transcription starts (⇧⌘R)", action: canStop ? stop : nil)
            }
        }
        .padding(.horizontal, Metric.recordingPillInset)
        .frame(width: Metric.recordingPillWidth, height: Metric.recordingPillHeight)
        // The soft shadow belongs to the fill alone, so the border stays a clean hairline.
        .background {
            Capsule()
                .fill(Ink.canvas)
                // The system's shadow color: dark in both themes (text-colored would glow in dark).
                .shadow(radius: Space.xs, y: Space.xs / 2)
        }
        .overlay(Capsule().strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording")
    }

    private var isFailed: Bool { if case .failed = status { true } else { false } }
    private var canStop: Bool { if case .recording = status { true } else { false } }

    private var lineText: String {
        if case let .failed(reason) = status { return reason }
        return line
    }

    private var liveButton: some View {
        Button { open?() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Metric.iconButtonCorner)
                    .fill(Ink.recording)
                    .opacity(pulsing ? 0.8 : 1)
                if status == .stopping {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Ink.onRecording)
                } else {
                    LiveWave(meter: meter)
                        .foregroundStyle(Ink.onRecording)
                }
            }
            .frame(width: Metric.iconButton, height: Metric.iconButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show Silvanus")
        .accessibilityLabel("Show Silvanus")
        .onAppear { updatePulse() }
        .onChange(of: status) { updatePulse() }
    }

    private func updatePulse() {
        let live = canStop && !reduceMotion
        withAnimation(live ? Motion.pulse : Motion.hover) { pulsing = live }
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
