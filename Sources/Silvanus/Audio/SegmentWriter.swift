@preconcurrency import AVFoundation
import Foundation

/// The format every track is stored in: 16 kHz mono float, what Parakeet expects.
nonisolated enum TrackFormat {
    static let sampleRate = 16_000.0
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    static let segmentSeconds = 30.0
}

/// Writes one track as 30-second CAF files (`mic-0001.caf`, `mic-0002.caf`…),
/// converting whatever the device delivers to 16 kHz mono. A crash loses at most
/// the segment being written. Safe to call from audio threads.
nonisolated final class SegmentWriter: @unchecked Sendable {
    let directory: URL
    let name: String
    private let queue: DispatchQueue
    private var file: AVAudioFile?
    private var index = 0
    private var framesInSegment: AVAudioFramePosition = 0
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    /// Seconds from the recording's start to this track's first sample.
    private(set) var startOffset: TimeInterval?
    private let recordingStart: Date
    /// Loudest recent level, 0 to 1, for "no call audio" warnings.
    private(set) var recentPeak: Float = 0
    private(set) var framesWritten: AVAudioFramePosition = 0
    /// Guards what other threads read while the queue writes: the first failure and the
    /// loudest level since the last sample.
    private let lock = NSLock()
    private var firstFailure: String?
    private var peakSinceSample: Float = 0
    /// Set by `finish`, on the queue: buffers that arrive later (a device callback still in
    /// flight) are dropped there, so none can open a segment after the close.
    private var finished = false

    init(directory: URL, name: String, recordingStart: Date) {
        self.directory = directory
        self.name = name
        self.recordingStart = recordingStart
        queue = DispatchQueue(label: "silvanus.writer.\(name)")
    }

    /// Copies the buffer and writes it on the writer's queue.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        let arrived = Date()
        queue.async { [self] in
            guard !finished else { return }
            if startOffset == nil {
                let lead = Double(copy.frameLength) / copy.format.sampleRate
                startOffset = max(0, arrived.timeIntervalSince(recordingStart) - lead)
            }
            guard let converted = convert(copy) else { return }
            write(converted)
        }
    }

    /// Why writing failed ("Couldn't write audio: …"), from the first open, convert, or
    /// write error. Nil while all is well. Safe to read from any thread.
    var failure: String? { lock.withLock { firstFailure } }

    /// The loudest level since the last call, 0 to 1, and starts over. The recorder samples
    /// it 10 times a second for the live wave, never per buffer.
    func samplePeak() -> Float {
        lock.withLock {
            let peak = peakSinceSample
            peakSinceSample = 0
            return peak
        }
    }

    /// Records a failure from outside the writer (the microphone couldn't restart), as is.
    func recordFailure(_ message: String) {
        lock.withLock { if firstFailure == nil { firstFailure = message } }
    }

    private func fail(_ reason: String) {
        lock.withLock { if firstFailure == nil { firstFailure = "Couldn't write audio: \(reason)" } }
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
                return
            }
        }
        do {
            try file?.write(from: buffer)
        } catch {
            fail(error.localizedDescription)
            return
        }
        framesInSegment += AVAudioFramePosition(buffer.frameLength)
        framesWritten += AVAudioFramePosition(buffer.frameLength)
        if let data = buffer.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
            recentPeak = max(peak, recentPeak * 0.9)
            lock.withLock { peakSinceSample = max(peakSinceSample, min(1, peak)) }
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
