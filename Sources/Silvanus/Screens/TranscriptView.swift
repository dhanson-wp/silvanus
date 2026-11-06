import SilvanusKit
import SwiftUI

/// Transcript (⌘3, the view pill): the open meeting's `transcript.json`, read through
/// `MeetingLibrary`, under the 46 pt canvas header. The meeting header isn't on this page
/// (KIT.md "Transcript view" starts the player strip 6 below the canvas header).
struct MeetingTranscript: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    /// What the layout was built from, and the layout (nil when there's no transcript yet).
    @State private var loaded: (key: Key, layout: TranscriptView.Layout?)?

    /// A new meeting, or new speaker names for this one, reads the transcript again.
    private struct Key: Equatable {
        let id: String
        let speakers: [String: String]
    }

    var body: some View {
        let key = Key(id: meeting.id, speakers: meeting.info.speakers)
        Group {
            if let loaded, loaded.key.id == meeting.id {
                TranscriptView(layout: loaded.layout, onSeek: model.seek)
                    // A new meeting starts with nothing selected.
                    .id(meeting.id)
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            let names = SpeakerNames.resolve(info: meeting.info, defaultMe: AppDefaults.meName)
            let layout = model.library.readTranscript(id: meeting.id)
                .map { TranscriptView.Layout($0, me: names.me, them: names.them) }
            loaded = (key, layout?.blocks.isEmpty == false ? layout : nil)
        }
    }
}

/// The transcript page itself: the player strip, then one block per speaker's turn in a lazy
/// stack, so a two-hour meeting only lays out what's on screen. Clicking a word or a
/// timestamp selects that time: the word is filled, the strip shows the time, and `onSeek`
/// gets it (playback is wired after calls). With no transcript, one line says so where the
/// strip would be.
struct TranscriptView: View {
    /// Nil when the meeting has no transcript yet.
    let layout: Layout?
    var onSeek: (TimeInterval) -> Void = { _ in }

    @State private var selected: Int?
    @State private var time: TimeInterval = 0

    /// What the page draws, worked out once per transcript, off the view's body. `me` and
    /// `them` name the two sides.
    struct Layout {
        let blocks: [TranscriptLayout.Block]
        let words: [Word]
        let duration: TimeInterval
        let levels: [Double]

        init(_ t: Transcript, me: String, them: String) {
            blocks = TranscriptLayout.blocks(t, me: me, them: them)
            words = TranscriptLayout.words(blocks)
            duration = TranscriptLayout.duration(t)
            levels = TranscriptLayout.activity(t, slices: 400)
        }
    }

    var body: some View {
        Group {
            if let layout, !layout.blocks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    PlayerStrip(time: time, duration: layout.duration, levels: layout.levels,
                                play: nil, seek: { seek(to: $0, in: layout) })
                        .padding(.top, Metric.playerTop)
                        .padding(.leading, Metric.contentX - Metric.canvasX)
                        .padding(.trailing, Metric.contentTrailing)
                        .gridProbe("playerStrip", area: "transcript")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: TranscriptBlock.spacing) {
                            ForEach(layout.blocks) { block in
                                TranscriptBlock(block: block, selectedWord: selection(in: block)) { index in
                                    select(index, in: layout)
                                }
                            }
                        }
                        .padding(.leading, Metric.contentX - Metric.canvasX + Metric.blockIndent)
                        .padding(.trailing, Space.xxl)
                        .padding(.vertical, Space.xl)
                    }
                    .accessibilityLabel("Transcript")
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("No transcript yet")
                        .kitType(.label)
                        .foregroundStyle(Ink.textSecondary)
                        .padding(.leading, Metric.contentX - Metric.canvasX)
                        .padding(.top, Space.xl)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .gridArea("transcript", inset: 0)
    }

    private func selection(in block: TranscriptLayout.Block) -> Int? {
        guard let selected, selected >= block.firstWord, selected < block.firstWord + block.words.count else { return nil }
        return selected
    }

    private func select(_ index: Int, in layout: Layout) {
        guard layout.words.indices.contains(index) else { return }
        selected = index
        time = layout.words[index].start
        onSeek(time)
    }

    private func seek(to t: TimeInterval, in layout: Layout) {
        time = t
        selected = TranscriptLayout.wordIndex(at: t, in: layout.words)
        onSeek(t)
    }
}
