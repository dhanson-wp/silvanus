import SilvanusKit
import SwiftUI

/// KIT.md "Transcript view", player strip: its measured sizes.
extension Metric {
    static let playerHeight: CGFloat = 42
    /// The strip starts 6 below the canvas header.
    static let playerTop: CGFloat = 6
    /// The play button sits 5 inside the strip.
    static let playerInset: CGFloat = 5
    /// Play button to time, and time to waveform.
    static let playerGap: CGFloat = 9
    /// The waveform ends 14 before the strip's end.
    static let waveformTrailing: CGFloat = 14
    static let waveformBar: CGFloat = 2
    static let waveformBarGap: CGFloat = 3
    /// The playhead's width.
    static let playhead: CGFloat = 2
}

/// The player strip above a transcript, from KIT.md "Transcript view": a fully rounded,
/// unfilled 42 pt strip with a 1 pt divider border; the play button, the time
/// ("00:00 / 00:55"), and a waveform of 2 pt bars, 3 apart (unplayed `divider`, played
/// `accent`, a 2 pt `text` playhead).
///
/// `levels` are the transcript's speech levels (TranscriptLayout.activity). A nil `play`
/// draws the play button disabled (a meeting with no audio); `isPlaying` shows pause. A
/// click on the waveform calls `seek` with that time.
struct PlayerStrip: View {
    var time: TimeInterval
    var duration: TimeInterval
    /// Heights from 0 to 1, spread over the waveform's width.
    var levels: [Double]
    var play: (() -> Void)?
    var isPlaying = false
    var seek: ((TimeInterval) -> Void)?

    var body: some View {
        let shape = Capsule()
        HStack(spacing: Metric.playerGap) {
            PlayButton(action: play, isPlaying: isPlaying)
            Text("\(Clock.text(time)) / \(Clock.text(duration))")
                .kitType(.monoSmall)
                .foregroundStyle(Ink.textSecondary)
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel("\(Clock.text(time)) of \(Clock.text(duration))")
            Waveform(levels: levels, played: duration > 0 ? min(1, time / duration) : 0)
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { point in
                                guard let seek, duration > 0, proxy.size.width > 0 else { return }
                                seek(max(0, min(1, point.x / proxy.size.width)) * duration)
                            }
                    }
                }
                .padding(.trailing, Metric.waveformTrailing - Metric.playerGap)
                .accessibilityLabel("Waveform")
        }
        .padding(.leading, Metric.playerInset)
        .frame(height: Metric.playerHeight)
        .frame(maxWidth: .infinity)
        .overlay(shape.strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        .contentShape(shape)
    }
}

/// The waveform's bars, drawn in one Canvas so a long strip stays one view.
private struct Waveform: View {
    let levels: [Double]
    /// How much has played, 0 to 1.
    let played: Double

    var body: some View {
        Canvas { context, size in
            let pitch = Metric.waveformBar + Metric.waveformBarGap
            let count = max(0, Int((size.width + Metric.waveformBarGap) / pitch))
            guard count > 0 else { return }
            let playedX = size.width * played
            var unplayedBars = Path(), playedBars = Path()
            for i in 0..<count {
                let level = levels.isEmpty ? 0 : levels[min(levels.count - 1, i * levels.count / count)]
                // A silent slice still shows a dot, so the strip reads as a timeline.
                let height = max(Metric.waveformBar, (size.height * level).rounded())
                let x = CGFloat(i) * pitch
                let bar = Path(roundedRect: CGRect(x: x, y: (size.height - height) / 2, width: Metric.waveformBar, height: height),
                               cornerRadius: Metric.waveformBar / 2)
                if x + Metric.waveformBar <= playedX { playedBars.addPath(bar) } else { unplayedBars.addPath(bar) }
            }
            context.fill(unplayedBars, with: .color(Ink.divider))
            context.fill(playedBars, with: .color(Ink.accent))
            let head = min(max(0, playedX - Metric.playhead / 2), size.width - Metric.playhead)
            context.fill(Path(CGRect(x: head, y: 0, width: Metric.playhead, height: size.height)), with: .color(Ink.text))
        }
        // Bars run the strip's middle 20 points, like a quiet recording's peaks.
        .frame(height: Space.xl)
        .frame(maxWidth: .infinity)
    }
}

/// The player's 28 × 28 play button: corner 7 with a 1 pt divider border, the play icon
/// at 9. States as the icon button's (IconButton), plus the border.
struct PlayButton: View {
    var action: (() -> Void)?
    var isPlaying = false

    var body: some View {
        Button {
            action?()
        } label: {
            KitIconView(isPlaying ? .pause : .play)
        }
        .buttonStyle(PlayButtonStyle())
        .disabled(action == nil)
        .help(action == nil ? "No audio for this meeting" : isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonStyle().makeBody(configuration: configuration)
            .overlay(RoundedRectangle(cornerRadius: Metric.iconButtonCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
            .environment(\.onCanvas, true)
    }
}
