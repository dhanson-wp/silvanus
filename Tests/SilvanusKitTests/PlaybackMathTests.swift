import Foundation
import Testing
@testable import SilvanusKit

@Test("A track playing from inside it starts at the matching frame")
func startInsideTrack() {
    let s = PlaybackMath.start(at: 2.5, startOffset: 0, frames: 160_000, rate: 16_000)
    #expect(s == PlaybackMath.Start(frame: 40_000, delay: 0))
}

@Test("A track that begins later waits, then plays from its first frame")
func startBeforeOffset() {
    let s = PlaybackMath.start(at: 1, startOffset: 3.5, frames: 160_000, rate: 16_000)
    #expect(s == PlaybackMath.Start(frame: 0, delay: 2.5))
}

@Test("Each track's offset moves its own seek frame")
func startHonorsEachOffset() {
    let mic = PlaybackMath.start(at: 5, startOffset: 0, frames: 320_000, rate: 16_000)
    let system = PlaybackMath.start(at: 5, startOffset: 1.5, frames: 320_000, rate: 16_000)
    #expect(mic?.frame == 80_000)
    #expect(system?.frame == 56_000)
}

@Test("A track that has ended, or is empty, doesn't start")
func startPastEnd() {
    #expect(PlaybackMath.start(at: 10, startOffset: 0, frames: 160_000, rate: 16_000) == nil)
    #expect(PlaybackMath.start(at: 30, startOffset: 9.5, frames: 160_000, rate: 16_000) == nil)
    #expect(PlaybackMath.start(at: 0, startOffset: 0, frames: 0, rate: 16_000) == nil)
    #expect(PlaybackMath.start(at: -3, startOffset: 0, frames: 16_000, rate: 16_000) == PlaybackMath.Start(frame: 0, delay: 0))
}

@Test("Meeting time is the seek plus the delay plus what has played, within the meeting")
func meetingTimeFromFrames() {
    #expect(PlaybackMath.meetingTime(seek: 4, delay: 0, playedFrames: 24_000, rate: 16_000, duration: 60) == 5.5)
    #expect(PlaybackMath.meetingTime(seek: 1, delay: 2.5, playedFrames: 16_000, rate: 16_000, duration: 60) == 4.5)
    #expect(PlaybackMath.meetingTime(seek: 4, delay: 0, playedFrames: -500, rate: 16_000, duration: 60) == 4)
    #expect(PlaybackMath.meetingTime(seek: 58, delay: 0, playedFrames: 160_000, rate: 16_000, duration: 60) == 60)
}

@Test("A track's end is its offset plus its length")
func trackEnd() {
    #expect(PlaybackMath.end(startOffset: 1.5, frames: 32_000, rate: 16_000) == 3.5)
}

@Test("A word's play time is its start, clamped to the transcript")
func wordTimes() {
    let words = [Word(text: "a", start: 0.5, end: 0.8), Word(text: "b", start: 2, end: 2.4)]
    #expect(TranscriptLayout.time(ofWord: 1, in: words) == 2)
    #expect(TranscriptLayout.time(ofWord: 9, in: words) == 2)
    #expect(TranscriptLayout.time(ofWord: -1, in: words) == 0.5)
    #expect(TranscriptLayout.time(ofWord: 0, in: []) == 0)
    #expect(TranscriptLayout.wordIndex(at: TranscriptLayout.time(ofWord: 1, in: words), in: words) == 1)
}
