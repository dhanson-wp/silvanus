import Foundation

/// The time math behind transcript playback: where each track starts when the meeting plays
/// from a given time, and what meeting time the player's frame count means.
///
/// A track's `startOffset` is how many seconds after the recording's start the file's first
/// frame sits. (The stitched `mic.caf` and `system.caf` already begin with that much
/// silence, so the app passes 0 for them; the math is for any file that doesn't.)
public enum PlaybackMath {
    /// Where one track begins: the file frame to start reading and how many seconds to wait
    /// before it sounds (when the play time is before the track's first frame).
    public struct Start: Equatable, Sendable {
        public var frame: Int64
        public var delay: TimeInterval
        public init(frame: Int64, delay: TimeInterval) { self.frame = frame; self.delay = delay }
    }

    /// The start of a track when the meeting plays from `time`, or nil when the track has
    /// already ended by then (or is empty).
    public static func start(at time: TimeInterval, startOffset: TimeInterval, frames: Int64, rate: Double) -> Start? {
        guard frames > 0, rate > 0 else { return nil }
        let at = max(0, time), offset = max(0, startOffset)
        if at < offset { return Start(frame: 0, delay: offset - at) }
        let frame = Int64(((at - offset) * rate).rounded())
        return frame < frames ? Start(frame: frame, delay: 0) : nil
    }

    /// The meeting time after a track that started at `seek` (after `delay` seconds) has
    /// played `playedFrames`. Never before `seek`, never past `duration`.
    public static func meetingTime(seek: TimeInterval, delay: TimeInterval, playedFrames: Int64,
                                   rate: Double, duration: TimeInterval) -> TimeInterval {
        guard rate > 0 else { return seek }
        let played = Double(max(0, playedFrames)) / rate
        return min(max(seek, seek + delay + played), max(seek, duration))
    }

    /// How long a track runs on the recording's clock: its offset plus its length.
    public static func end(startOffset: TimeInterval, frames: Int64, rate: Double) -> TimeInterval {
        rate > 0 ? max(0, startOffset) + Double(frames) / rate : 0
    }
}

extension TranscriptLayout {
    /// Where word `index` starts, for playing from it. Clamped to the first and last word;
    /// 0 with no words.
    public static func time(ofWord index: Int, in words: [Word]) -> TimeInterval {
        guard !words.isEmpty else { return 0 }
        return words[min(max(0, index), words.count - 1)].start
    }
}
