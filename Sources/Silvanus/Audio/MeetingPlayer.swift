import AVFoundation
import Observation
import SilvanusKit

/// Plays a meeting's two stitched tracks (`audio/mic.caf`, `audio/system.caf`) together
/// through one AVAudioEngine with a player node per track. Output only: it never touches the
/// microphone or the audio tap. Both nodes start on one host time, so they stay in sync; a
/// seek stops them and schedules both again from the target frame.
///
/// The stitched files begin with silence up to their `startOffset`, so both already share
/// the recording's clock and play from offset 0 (PlaybackMath handles files that don't).
@MainActor
@Observable
final class MeetingPlayer {
    private(set) var isPlaying = false
    /// The longest track's length on the recording's clock; 0 with no audio.
    private(set) var duration: TimeInterval = 0
    var hasAudio: Bool { !tracks.isEmpty }
    /// 0 to 1. Self-tests mute the output.
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    private struct Track {
        let file: AVAudioFile
        let node: AVAudioPlayerNode
        let startOffset: TimeInterval
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var tracks: [Track] = []
    /// Where the current run began (meeting time), the node whose frame count tells the time,
    /// and how long that node waited before sounding.
    @ObservationIgnored private var seekTime: TimeInterval = 0
    @ObservationIgnored private var reference: (node: AVAudioPlayerNode, delay: TimeInterval)?
    /// Where playback is while paused.
    @ObservationIgnored private var position: TimeInterval = 0

    /// Opens the tracks in `audio`. False when neither file is there.
    @discardableResult
    func load(audio: URL) -> Bool {
        stop()
        for track in tracks { engine.detach(track.node) }
        tracks = []
        for name in ["mic", "system"] {
            let url = audio.appending(path: "\(name).caf")
            guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                  file.length > 0 else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            tracks.append(Track(file: file, node: node, startOffset: 0))
        }
        duration = tracks.map {
            PlaybackMath.end(startOffset: $0.startOffset, frames: $0.file.length, rate: $0.file.processingFormat.sampleRate)
        }.max() ?? 0
        position = 0
        return hasAudio
    }

    /// Plays from `time` (meeting time), starting or restarting both tracks.
    func play(from time: TimeInterval) {
        guard hasAudio else { return }
        haltNodes()
        let at = min(max(0, time), duration)
        var starts: [(Track, PlaybackMath.Start)] = []
        for track in tracks {
            let rate = track.file.processingFormat.sampleRate
            if let start = PlaybackMath.start(at: at, startOffset: track.startOffset, frames: track.file.length, rate: rate) {
                starts.append((track, start))
            }
        }
        guard !starts.isEmpty else {
            position = duration
            isPlaying = false
            return
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch {
                print("PLAYBACK couldn't start the output: \(error.localizedDescription)")
                position = at
                isPlaying = false
                return
            }
        }
        for (track, start) in starts {
            track.node.scheduleSegment(track.file, startingFrame: start.frame,
                                       frameCount: AVAudioFrameCount(track.file.length - start.frame), at: nil)
        }
        // One host time for every node, a moment out so they all begin together.
        let begin = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05)
        for (track, start) in starts {
            track.node.play(at: AVAudioTime(hostTime: begin + AVAudioTime.hostTime(forSeconds: start.delay)))
        }
        seekTime = at
        let first = starts.min { $0.1.delay < $1.1.delay }!
        reference = (first.0.node, first.1.delay)
        position = at
        isPlaying = true
    }

    /// Moves to `time`: keeps playing from there when playing, otherwise just moves.
    func seek(to time: TimeInterval) {
        if isPlaying { play(from: time) } else { position = min(max(0, time), duration) }
    }

    func pause() {
        guard isPlaying else { return }
        position = currentTime
        halt()
    }

    /// Plays from where it paused (or from the start after the end).
    func resume() {
        play(from: position >= duration ? 0 : position)
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    /// Stops and lets the output go.
    func stop() {
        if isPlaying { position = currentTime }
        halt()
    }

    /// The meeting time now, from the engine's player time (not the wall clock). Reaching the
    /// end stops playback.
    var currentTime: TimeInterval {
        guard isPlaying, let reference else { return position }
        let rate = tracks.first { $0.node === reference.node }?.file.processingFormat.sampleRate ?? 16_000
        var played: Int64 = 0
        if let render = reference.node.lastRenderTime, let player = reference.node.playerTime(forNodeTime: render) {
            played = player.sampleTime
        }
        let time = PlaybackMath.meetingTime(seek: seekTime, delay: reference.delay, playedFrames: played,
                                            rate: rate, duration: duration)
        if time >= duration {
            position = duration
            halt()
            return duration
        }
        position = time
        return time
    }

    private func haltNodes() {
        for track in tracks { track.node.stop() }
    }

    private func halt() {
        haltNodes()
        if engine.isRunning { engine.stop() }
        isPlaying = false
        reference = nil
    }
}
