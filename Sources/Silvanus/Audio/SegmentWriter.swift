@preconcurrency import AVFoundation
import Foundation
import SilvanusKit

/// The format every track is stored in: 16 kHz mono float, what Parakeet expects.
nonisolated enum TrackFormat {
    static let sampleRate = 16_000.0
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    static let segmentSeconds = 30.0
}

/// The captured clock both tracks of a recording share (`CaptureTimeline`), safe to read
/// from audio threads. Pause and an interruption hold it; the writers drop what arrives
/// while it's held, so both tracks skip the same stretch.
nonisolated final class CaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var timeline: CaptureTimeline

    init(start: Date) {
        timeline = CaptureTimeline(start: start)
    }

    var start: Date { timeline.start }
    var isHeld: Bool { lock.withLock { timeline.isHeld } }

    func hold(at date: Date) { lock.withLock { timeline.hold(at: date) } }
    func release(at date: Date) { lock.withLock { timeline.release(at: date) } }

    /// The captured time at `date`, or nil while held (the buffer is dropped).
    func captured(at date: Date) -> TimeInterval? {
        lock.withLock { timeline.isHeld ? nil : timeline.captured(at: date) }
    }
}

/// Writes one track as 30-second CAF files (`mic-0001.caf`, `mic-0002.caf`…),
/// converting whatever the device delivers to 16 kHz mono. A crash loses at most
/// the segment being written. Safe to call from audio threads.
///
/// Times are captured time (`CaptureClock`): buffers that arrive while the clock is held
/// (Pause, an interruption) are dropped, never written. After a break in the track (the
/// microphone restarted, Retry), the first buffer is lined up with the clock again, with
/// silence for the time the track missed, so the two tracks stay aligned.
nonisolated final class SegmentWriter: @unchecked Sendable {
    let directory: URL
    let name: String
    let clock: CaptureClock
    private let queue: DispatchQueue
    private var file: AVAudioFile?
    private var index = 0
    private var framesInSegment: AVAudioFramePosition = 0
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    /// Captured seconds from the recording's start to this track's first sample.
    private(set) var startOffset: TimeInterval?
    private(set) var framesWritten: AVAudioFramePosition = 0
    /// Guards what other threads read while the queue writes: the first failure and the
    /// levels since the last sample.
    private let lock = NSLock()
    private var firstFailure: String?
    private var peakSinceSample: Float = 0
    private var squaresSinceSample: Double = 0
    private var countSinceSample = 0
    /// Set by `finish`, on the queue: buffers that arrive later (a device callback still in
    /// flight) are dropped there, so none can open a segment after the close.
    private var finished = false
    /// On the queue: the next buffer lines up with the clock (after a break).
    private var realign = false
    /// A gap shorter than this (5 ms) is left alone when lining up.
    static let realignThreshold: TimeInterval = 0.005

    init(directory: URL, name: String, clock: CaptureClock) {
        self.directory = directory
        self.name = name
        self.clock = clock
        queue = DispatchQueue(label: "silvanus.writer.\(name)")
    }

    /// A writer with a clock of its own (one track on its own, the checks).
    convenience init(directory: URL, name: String, recordingStart: Date) {
        self.init(directory: directory, name: name, clock: CaptureClock(start: recordingStart))
    }

    /// Copies the buffer and writes it on the writer's queue. Dropped while the clock is held.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let captured = clock.captured(at: Date()) else { return }
        guard let copy = Self.copy(buffer) else { return }
        queue.async { [self] in
            guard !finished else { return }
            let lead = Double(copy.frameLength) / copy.format.sampleRate
            let begins = max(0, captured - lead)
            guard let converted = convert(copy) else { return }
            if startOffset == nil {
                startOffset = begins
                realign = false
                write(converted)
                return
            }
            guard realign, let startOffset else {
                write(converted)
                return
            }
            // The first buffer after a release (Resume, Retry, a microphone change): line the
            // track up with the clock. Behind, pad silence; ahead (the buffer holds audio from
            // before the release), cut that front off. Each track does this on its own, so
            // their buffer sizes never let one drift ahead of the other.
            let position = startOffset + Double(framesWritten) / TrackFormat.sampleRate
            let gap = begins - position
            if gap > Self.realignThreshold {
                writeSilence(min(gap, 4 * 3600))
            } else if gap < -Self.realignThreshold {
                let cut = AVAudioFrameCount((-gap * TrackFormat.sampleRate).rounded())
                // All of it is from before the release: drop it and line up the next one.
                guard cut < converted.frameLength, let rest = Self.dropFront(converted, frames: cut) else { return }
                realign = false
                write(rest)
                return
            }
            realign = false
            write(converted)
        }
    }

    /// The buffer without its first `frames` frames (16 kHz mono float, as converted).
    private static func dropFront(_ buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let left = buffer.frameLength - frames
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: left),
              let src = buffer.floatChannelData?[0], let dst = out.floatChannelData?[0] else { return nil }
        out.frameLength = left
        memcpy(dst, src + Int(frames), Int(left) * MemoryLayout<Float>.size)
        return out
    }

    /// Every release of the clock (Resume, Retry): the next buffer lines up with it.
    func lineUp() {
        queue.sync { realign = true }
    }

    /// Why writing failed ("Couldn't write audio: …"), from the first open, convert, or
    /// write error. Nil while all is well. Safe to read from any thread.
    var failure: String? { lock.withLock { firstFailure } }

    /// The loudest level and the RMS since the last call, 0 to 1, and starts over. The
    /// recorder samples them 10 times a second for the level bars, never per buffer.
    func sampleLevels() -> (peak: Float, rms: Float) {
        lock.withLock {
            let peak = peakSinceSample
            let rms = countSinceSample > 0 ? Float((squaresSinceSample / Double(countSinceSample)).squareRoot()) : 0
            peakSinceSample = 0
            squaresSinceSample = 0
            countSinceSample = 0
            return (peak, rms)
        }
    }

    /// Records a failure from outside the writer (the microphone couldn't restart), as is.
    func recordFailure(_ message: String) {
        lock.withLock { if firstFailure == nil { firstFailure = message } }
    }

    private func fail(_ reason: String) {
        lock.withLock { if firstFailure == nil { firstFailure = "Couldn't write audio: \(reason)" } }
    }

    /// Retry: forgets the failure and starts a new segment in the same track, lined up with
    /// the clock. What was written stays.
    func resume() {
        queue.sync {
            file?.close()
            file = nil
            realign = true
        }
        lock.withLock { firstFailure = nil }
    }

    /// Writes what's queued and closes the current file. Later appends are dropped.
    func finish() {
        queue.sync {
            finished = true
            file?.close()
            file = nil
        }
    }

    /// Closes the current segment after what's queued, so the next buffer starts a new file
    /// in the same track: the microphone changed (another device, a new format).
    func breakSegment() {
        queue.async { [self] in
            file?.close()
            file = nil
            realign = true
        }
    }

    var segmentURLs: [URL] { Self.segments(named: name, in: directory) }

    /// A track's segment files in a folder (`mic-0001.caf`…), in order.
    static func segments(named name: String, in directory: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("\(name)-") && $0.pathExtension == "caf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let target = TrackFormat.format
        if buffer.format == target { return buffer }
        if sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            // Mix every channel into the mono track, not just the first (a stereo call, a
            // headset that puts the voice on the right).
            converter?.downmix = true
            sourceFormat = buffer.format
        }
        guard let converter else {
            fail("can't convert \(buffer.format.channelCount)-channel \(Int(buffer.format.sampleRate)) Hz audio")
            return nil
        }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        final class Once: @unchecked Sendable { var given = false }
        let once = Once()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if once.given { status.pointee = .noDataNow; return nil }
            once.given = true
            status.pointee = .haveData
            return buffer
        }
        if let error { fail(error.localizedDescription) }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard writeFrames(buffer) else { return }
        if let data = buffer.floatChannelData?[0] {
            var peak: Float = 0
            var squares: Double = 0
            for i in 0..<Int(buffer.frameLength) {
                let sample = data[i]
                peak = max(peak, abs(sample))
                squares += Double(sample * sample)
            }
            lock.withLock {
                peakSinceSample = max(peakSinceSample, min(1, peak))
                squaresSinceSample += squares
                countSinceSample += Int(buffer.frameLength)
            }
        }
    }

    /// Writes frames into the current segment, opening the next when this one is full.
    /// False when the file couldn't open or write (the failure is recorded).
    private func writeFrames(_ buffer: AVAudioPCMBuffer) -> Bool {
        if file == nil || framesInSegment >= AVAudioFramePosition(TrackFormat.segmentSeconds * TrackFormat.sampleRate) {
            index += 1
            framesInSegment = 0
            let url = directory.appending(path: String(format: "%@-%04d.caf", name, index))
            file?.close()
            do {
                file = try AVAudioFile(forWriting: url, settings: TrackFormat.format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            } catch {
                file = nil
                fail(error.localizedDescription)
                return false
            }
        }
        do {
            try file?.write(from: buffer)
        } catch {
            fail(error.localizedDescription)
            return false
        }
        framesInSegment += AVAudioFramePosition(buffer.frameLength)
        framesWritten += AVAudioFramePosition(buffer.frameLength)
        return true
    }

    /// Silence for a stretch the track missed, so it stays on the recording's clock. Its
    /// levels don't count toward the bars.
    private func writeSilence(_ seconds: TimeInterval) {
        var frames = AVAudioFramePosition(seconds * TrackFormat.sampleRate)
        let chunk = AVAudioFrameCount(TrackFormat.sampleRate)
        guard let silence = AVAudioPCMBuffer(pcmFormat: TrackFormat.format, frameCapacity: chunk) else { return }
        while frames > 0 {
            silence.frameLength = AVAudioFrameCount(min(AVAudioFramePosition(chunk), frames))
            if !writeFrames(silence) { return }
            frames -= AVAudioFramePosition(silence.frameLength)
        }
    }

    private static func copy(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength) else { return nil }
        c.frameLength = b.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: b.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(c.mutableAudioBufferList)
        for i in 0..<min(src.count, dst.count) {
            guard let s = src[i].mData, let d = dst[i].mData else { continue }
            let n = min(Int(src[i].mDataByteSize), Int(dst[i].mDataByteSize))
            memcpy(d, s, n)
            dst[i].mDataByteSize = UInt32(n)
        }
        return c
    }
}

/// Joins a track's segments into one file for transcription and playback,
/// with silence in front so both tracks share the recording's clock.
nonisolated enum Stitcher {
    static func stitch(_ segments: [URL], leadingSilence: TimeInterval, to url: URL) throws {
        let fmt = TrackFormat.format
        try? FileManager.default.removeItem(at: url)
        let out = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let silenceFrames = AVAudioFrameCount(max(0, leadingSilence) * fmt.sampleRate)
        if silenceFrames > 0, let silence = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: silenceFrames) {
            silence.frameLength = silenceFrames
            try out.write(from: silence)
        }
        for seg in segments {
            // A segment cut off by a crash may not open; skip it rather than fail the meeting.
            guard let input = try? AVAudioFile(forReading: seg, commonFormat: .pcmFormatFloat32, interleaved: false),
                  let buf = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_000)
            else { continue }
            // read(into:) can return less than asked, so read until the file ends.
            while input.framePosition < input.length {
                guard (try? input.read(into: buf)) != nil, buf.frameLength > 0 else { break }
                try out.write(from: buf)
            }
        }
        // Close explicitly: AVAudioFile buffers the last frames until it closes.
        out.close()
    }
}
