import Foundation

/// Cuts what sits under the voice (desk bumps, fans, breath) so a track's level
/// says how loud the speech is. A second-order high-pass; it keeps its state, so
/// a track can be filtered buffer by buffer.
public struct HighPass: Sendable {
    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    public init(cutoff: Double = 150, sampleRate: Double) {
        let w = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w) / (2 * 0.7071)
        let a0 = 1 + alpha
        b0 = (1 + cos(w)) / 2 / a0
        b1 = -(1 + cos(w)) / a0
        b2 = b0
        a1 = -2 * cos(w) / a0
        a2 = (1 - alpha) / a0
    }

    public mutating func process(_ samples: UnsafeMutableBufferPointer<Float>) {
        for index in samples.indices {
            let x = Double(samples[index])
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            samples[index] = Float(y)
        }
    }
}

/// One track's speech level over time: a decibel value per 20 ms frame
/// (`TrackLevels.frame`), with the rumble under the voice cut first. Samples can
/// arrive in pieces of any size; what's left of a frame waits for the next piece,
/// so frame N is always the same 20 ms of the track.
public struct SpeechLevels: Sendable {
    public private(set) var levels: [Float] = []
    private var filter: HighPass
    private var pending: [Float] = []
    private let frame: Int

    public init(sampleRate: Double) {
        filter = HighPass(sampleRate: sampleRate)
        frame = Int(TrackLevels.frame * sampleRate)
    }

    public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        let from = pending.count
        pending.append(contentsOf: samples)
        pending.withUnsafeMutableBufferPointer { buffer in
            filter.process(UnsafeMutableBufferPointer(rebasing: buffer[from...]))
            var at = 0
            while at + frame <= buffer.count {
                levels.append(TrackLevels.decibels(UnsafeBufferPointer(rebasing: buffer[at..<at + frame])))
                at += frame
            }
        }
        pending.removeFirst(pending.count - pending.count % frame)
    }
}
