import Foundation
import Testing
@testable import SilvanusKit

/// How loud a sine at `hz` is after the filter, against before, in decibels.
private func change(at hz: Double) -> Float {
    let rate = 16_000.0
    var samples = (0..<16_000).map { Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    let before = samples.withUnsafeBufferPointer { TrackLevels.decibels($0) }
    var filter = HighPass(sampleRate: rate)
    samples.withUnsafeMutableBufferPointer { filter.process($0) }
    return samples.withUnsafeBufferPointer { TrackLevels.decibels($0) } - before
}

@Suite("Speech band") struct SpeechBandTests {
    @Test("Rumble under the voice is cut")
    func rumbleIsCut() {
        #expect(change(at: 50) < -15)
    }

    @Test("The voice passes through")
    func voicePasses() {
        #expect(abs(change(at: 1_000)) < 0.5)
    }

    @Test("Filtering in pieces gives the same result as in one go")
    func piecesMatch() {
        let input = (0..<4_000).map { Float(sin(Double($0) * 0.05) + sin(Double($0) * 0.9)) }
        var whole = input, parts = input
        var one = HighPass(sampleRate: 16_000), two = HighPass(sampleRate: 16_000)
        whole.withUnsafeMutableBufferPointer { one.process($0) }
        parts.withUnsafeMutableBufferPointer { buffer in
            two.process(UnsafeMutableBufferPointer(rebasing: buffer[0..<1_000]))
            two.process(UnsafeMutableBufferPointer(rebasing: buffer[1_000...]))
        }
        #expect(whole == parts)
    }

    @Test("Levels come out the same however the samples arrive")
    func levelsIgnoreHowSamplesArrive() {
        let input = (0..<16_000).map { Float(sin(Double($0) * 0.3)) * ($0 > 8_000 ? 0.5 : 0.05) }
        var whole = SpeechLevels(sampleRate: 16_000), pieces = SpeechLevels(sampleRate: 16_000)
        input.withUnsafeBufferPointer { whole.add($0) }
        // Pieces that never line up with the 20 ms frames (320 samples).
        var at = 0
        for size in [100, 333, 4_097, 1, 7_000, 4_469] {
            input[at..<at + size].withUnsafeBufferPointer { pieces.add($0) }
            at += size
        }
        #expect(at == input.count)
        #expect(whole.levels.count == 50)
        #expect(pieces.levels == whole.levels)
        #expect(whole.levels[10] < whole.levels[40] - 15)
    }
}
