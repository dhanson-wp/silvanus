import SilvanusKit
import SwiftUI

/// The transcript family in the kit gallery: the play button in every state, the player strip
/// at the start and part way through, a speaker block at rest, hovered, playing (a word
/// filled), and focused, and the Transcript view put together at the default canvas width,
/// with its empty state. Fictional words only (the seed meeting's transcript).
struct TranscriptGallery: View {
    private let states: [PartState] = [.rest, .hover, .pressed, .focused, .disabled]
    private static let width = Metric.windowDefault.width - Metric.canvasX
    private static let layout = TranscriptView.Layout(SeedData.kickoffTranscript, me: "Sam Rivera", them: "Priya Natarajan")

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Transcript")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            VStack(alignment: .leading, spacing: Space.xxl) {
                HStack(spacing: Space.lg) {
                    Text("Play button")
                        .kitType(.rowTitle)
                        .foregroundStyle(Ink.text)
                    ForEach(states, id: \.self) { state in
                        VStack(spacing: Space.xs) {
                            Text(state.rawValue)
                                .kitType(.meta)
                                .foregroundStyle(Ink.textSecondary)
                            PlayButton(action: state == .disabled ? nil : {})
                                .environment(\.forcedPartState, state)
                        }
                    }
                }
                sample("Player strip, at the start (play waits for recording)") {
                    strip(time: 0)
                }
                sample("Player strip, part way through") {
                    strip(time: Self.layout.duration * 0.4)
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    ForEach([PartState.rest, .hover, .selected, .focused], id: \.self) { state in
                        sample(state == .selected ? "Block, playing" : "Block, \(state.rawValue)") {
                            TranscriptBlock(block: Self.layout.blocks[1],
                                            selectedWord: state == .selected ? Self.layout.blocks[1].firstWord + 3 : nil)
                                .environment(\.forcedPartState, state)
                                .padding(Space.sm)
                                .frame(width: Space.lg * 14)
                        }
                    }
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    sample("Transcript view, 910 pt window") {
                        TranscriptView(layout: Self.layout)
                            .frame(width: Self.width, height: Space.section * 12)
                    }
                    sample("No transcript yet") {
                        TranscriptView(layout: nil)
                            .frame(width: Space.lg * 16, height: Space.section * 3)
                    }
                }
            }
            .padding(Space.lg)
            .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.rowCorner))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }

    private func strip(time: TimeInterval) -> some View {
        PlayerStrip(time: time, duration: Self.layout.duration, levels: Self.layout.levels)
            .padding(.horizontal, Metric.contentTrailing)
            .padding(.vertical, Metric.playerTop)
            .frame(width: Self.width)
    }

    /// A part on the canvas's ground, as the window draws it.
    private func sample(_ name: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(name)
                .kitType(.meta)
                .foregroundStyle(Ink.textSecondary)
            content()
                .background(Ink.canvas)
                .overlay(Rectangle().strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }
}
