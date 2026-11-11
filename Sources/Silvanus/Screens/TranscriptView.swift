import SilvanusKit
import SwiftUI

/// Transcript (⌘3, the view pill): the open meeting's `transcript.json`, read through
/// `MeetingLibrary`, under the 46 pt canvas header. The meeting header isn't on this page
/// (KIT.md "Transcript view" starts the player strip 6 below the canvas header).
struct MeetingTranscript: View {
    @Environment(AppModel.self) private var model
    let meeting: Meeting
    /// What the layout was built from, and the layout (nil when there's no transcript yet).
    @State private var loaded: (key: Key, layout: TranscriptView.Layout?, audio: URL?)?

    /// A new meeting, or new speaker names for this one, reads the transcript again.
    private struct Key: Equatable {
        let id: String
        let speakers: [String: String]
    }

    var body: some View {
        let key = Key(id: meeting.id, speakers: meeting.info.speakers)
        Group {
            if let loaded, loaded.key.id == meeting.id {
                TranscriptView(layout: loaded.layout, audio: loaded.audio, onSeek: model.seek)
                    // A new meeting starts with nothing selected.
                    .id(meeting.id)
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            let names = AppDefaults.speakerNames(meeting.info)
            let layout = model.library.readTranscript(id: meeting.id)
                .map { TranscriptView.Layout($0, me: names.me, them: names.them) }
            // Playback needs at least one stitched track (after-call makes them).
            let audio = model.library.audioURL(for: meeting.id)
            let hasAudio = ["mic", "system"].contains { name in
                audio.map { FileManager.default.fileExists(atPath: $0.appending(path: "\(name).caf").path) } ?? false
            }
            loaded = (key, layout?.blocks.isEmpty == false ? layout : nil, hasAudio ? audio : nil)
        }
    }
}

/// The transcript page itself: the player strip, then one block per speaker's turn in a lazy
/// stack, so a two-hour meeting only lays out what's on screen. Clicking a word or a
/// timestamp selects that time: the word is filled, the strip shows the time, `onSeek` gets
/// it, and the meeting plays from there (MeetingPlayer, when `audio` is the folder with the
/// stitched tracks). While it plays the filled word follows the player's time. With no
/// transcript, one line says so where the strip would be.
struct TranscriptView: View {
    /// Nil when the meeting has no transcript yet.
    let layout: Layout?
    /// The meeting's `audio/` folder when it has stitched tracks; nil keeps Play disabled.
    var audio: URL?
    var onSeek: (TimeInterval) -> Void = { _ in }

    @State private var selected: Int?
    @State private var time: TimeInterval = 0
    @State private var player = MeetingPlayer()
    /// Set when the tracks failed to open (the strip starts out as playable when there's audio).
    @State private var loadFailed = false
    private var canPlay: Bool { audio != nil && !loadFailed }

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
                                play: canPlay ? { togglePlay(in: layout) } : nil, isPlaying: player.isPlaying,
                                seek: { seek(to: $0, in: layout) })
                        .padding(.top, Metric.playerTop)
                        .padding(.leading, Metric.contentX - Metric.canvasX)
                        .padding(.trailing, Metric.contentTrailing)
                        .gridProbe("playerStrip", area: "transcript")
                    ScrollViewReader { scroller in
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
                    // The block being played stays in view as playback moves on.
                    .onChange(of: playingBlock(in: layout)) { _, id in
                        if let id { withAnimation(Motion.hover) { scroller.scrollTo(id, anchor: .center) } }
                    }
                    }
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
        .task(id: audio) { loadFailed = audio.map { !player.load(audio: $0) } ?? false }
        // Space plays and pauses while the transcript is on screen.
        .background {
            if canPlay, let layout {
                Button("Play or pause") { togglePlay(in: layout) }
                    .keyboardShortcut(.space, modifiers: [])
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .task(id: player.isPlaying) { await follow() }
        .onDisappear { player.stop() }
    }

    /// While playing, the strip's time and the filled word follow the player's time.
    private func follow() async {
        guard player.isPlaying, let layout else { return }
        while !Task.isCancelled && player.isPlaying {
            let now = player.currentTime
            time = now
            selected = TranscriptLayout.wordIndex(at: now, in: layout.words)
            try? await Task.sleep(for: .milliseconds(50))
        }
        // The end of the audio stops the player; show where it stopped.
        time = player.currentTime
    }

    private func togglePlay(in layout: Layout) {
        if player.isPlaying { player.pause() } else { player.resume() }
    }

    /// The block holding the current word while playing (nil when not playing).
    private func playingBlock(in layout: Layout) -> Int? {
        guard player.isPlaying, let selected else { return nil }
        return layout.blocks.last { $0.firstWord <= selected }?.id
    }

    private func selection(in block: TranscriptLayout.Block) -> Int? {
        guard let selected, selected >= block.firstWord, selected < block.firstWord + block.words.count else { return nil }
        return selected
    }

    private func select(_ index: Int, in layout: Layout) {
        guard layout.words.indices.contains(index) else { return }
        selected = index
        time = TranscriptLayout.time(ofWord: index, in: layout.words)
        onSeek(time)
        if canPlay { player.play(from: time) }
    }

    private func seek(to t: TimeInterval, in layout: Layout) {
        time = t
        selected = TranscriptLayout.wordIndex(at: t, in: layout.words)
        onSeek(t)
        if canPlay { player.play(from: t) }
    }
}
