import SilvanusKit
import SwiftUI

/// The live wave and the Transcribing… bar: their measures.
extension Metric {
    /// The live wave: bars 2 wide, 2 apart, from 3 to 12 tall.
    static let waveBar: CGFloat = 2
    static let waveMin: CGFloat = 3
    static let waveMax: CGFloat = 12
    /// The Transcribing… bar in the canvas header.
    static let progressWidth: CGFloat = 64
    static let progressHeight: CGFloat = 4
}

/// The recording's loudness for the level bars and the live wave: the last five smoothed
/// levels, 0 to 1, from both tracks' captured audio, sampled 10 times a second by the
/// recorder (never per audio buffer, never a microphone of its own). Only the bars read it,
/// so a new level redraws them and nothing else.
@Observable
final class LevelMeter {
    static let bars = 5
    private(set) var levels: [Float] = Array(repeating: 0, count: LevelMeter.bars)

    init(levels: [Float]? = nil) {
        if let levels { self.levels = Array(levels.suffix(Self.bars)) }
    }

    func push(_ level: Float) {
        let level = min(1, max(0, level))
        // Quiet stays quiet without redrawing ten times a second.
        if level == 0, levels.allSatisfy({ $0 == 0 }) { return }
        levels = Array((levels + [level]).suffix(Self.bars))
    }

    func reset() {
        if levels.contains(where: { $0 != 0 }) { levels = Array(repeating: 0, count: Self.bars) }
    }

    /// True when any recent level is above quiet: Reduce Motion shows a steady indicator
    /// from it instead of moving bars.
    var isActive: Bool { levels.contains { $0 >= LevelMath.quiet } }
}

/// A small live wave (the view pill's Transcript tab while recording): one bar per level in
/// the meter, rounded, in the current foreground style. Quiet bars keep a 3 pt stub.
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

    /// The levels are already on a decibel scale (`LevelMath`), so they map straight to height.
    static func height(_ level: Float) -> CGFloat {
        Metric.waveMin + (Metric.waveMax - Metric.waveMin) * CGFloat(min(1, max(0, level)))
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
