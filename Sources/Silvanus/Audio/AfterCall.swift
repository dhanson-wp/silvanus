import AVFoundation
import FluidAudio
import Foundation
import SilvanusKit

/// The after-call pass for one meeting: stitches each track's segment files in
/// `<meeting folder>/audio/` into `mic.caf` and `system.caf`, transcribes both
/// sides, takes the call's leak out of the mic side, and writes `transcript.json` and
/// `transcript.md`, then records the engine in `meeting.json`. Never touches `notes.md`.
enum AfterCall {
    enum Failure: LocalizedError {
        case noMeeting(String)
        case noAudio

        var errorDescription: String? {
            switch self {
            case .noMeeting: "This meeting's folder isn't on disk."
            case .noAudio: "This meeting has no recorded audio."
            }
        }
    }

    /// `me` names the mic side when the meeting doesn't (`AppDefaults.meName` in the app).
    /// `progress` gets the whole pass's progress, 0…1: stitching, the speech model (its
    /// download the first time), each side's words, then saving. Called on any thread.
    @discardableResult
    static func run(meetingID: String, library: MeetingLibrary, transcriber: Transcriber, me: String,
                    progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Transcript {
        guard let notes = library.notesURL(for: meetingID), library.folderExists(for: meetingID) else {
            throw Failure.noMeeting(meetingID)
        }
        let audio = notes.deletingLastPathComponent().appending(path: MeetingFolder.audio)
        let stitched = try await stitch(in: audio)
        guard stitched.mic != nil || stitched.system != nil else { throw Failure.noAudio }
        progress(0.05)

        try await transcriber.prepare { progress(0.05 + 0.25 * $0) }
        progress(0.3)
        // The words take most of the time: 0.3 to 0.9, split between the sides.
        let sides = Double([stitched.mic, stitched.system].compactMap { $0 }.count)
        var done = 0.3
        // With both sides recorded, their levels tell my voice from the call leaking into the mic.
        var levels: TrackLevels?
        if let mic = stitched.mic, let call = stitched.system {
            levels = await Self.levels(mic: mic, call: call)
        }
        var mine: [Word] = [], theirs: [Word] = [], bleed: [Word] = []
        if let url = stitched.mic {
            // The speech model writes down the faintest leak, so it hears my side with the
            // leak silenced, and the leak on its own. `mic.caf` stays as recorded.
            let scratch = FileManager.default.temporaryDirectory.appending(path: "silvanus-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: scratch) }
            if let mute = levels.map(EchoCleanup.bleedFrames), mute.contains(true),
               let split = try? await Self.split(url, mute: mute, into: scratch) {
                mine = try await transcriber.words(in: split.voice, source: .microphone)
                bleed = try await transcriber.words(in: split.bleed, source: .microphone)
            } else {
                mine = try await transcriber.words(in: url, source: .microphone)
            }
            done += 0.6 / sides
            progress(done)
        }
        if let url = stitched.system {
            theirs = try await transcriber.words(in: url, source: .system)
            done += 0.6 / sides
            progress(done)
        }
        var transcript = TranscriptBuilder.build(me: mine, them: theirs, engine: Transcriber.engineName, levels: levels,
                                                 bleed: bleed)
        // Whole seconds, as the JSON keeps them, so what this returns is what's on disk.
        transcript.processedAt = Date(timeIntervalSince1970: transcript.processedAt.timeIntervalSince1970.rounded(.down))

        // Read again just before writing, so a rename made meanwhile is kept.
        guard var meeting = library.meeting(id: meetingID) else { throw Failure.noMeeting(meetingID) }
        let names = AppDefaults.speakerNames(meeting.info, me: me)
        try library.saveTranscript(transcript, markdown: transcript.markdown(me: names.me, them: names.them) + "\n",
                                   for: meetingID)
        meeting.info.asr = ASRInfo(engine: Transcriber.engine, model: Transcriber.model, processedAt: transcript.processedAt)
        try library.saveInfo(meeting)
        progress(1)
        return transcript
    }

    /// Writes the mic track twice into `folder`: `voice` with the `mute` frames
    /// (20 ms each, `EchoCleanup.bleedFrames`) silenced, and `bleed` with only those
    /// frames. Both have the rumble under the voice cut, and the switch between them
    /// is eased over a few milliseconds, so neither file clicks or thumps.
    @concurrent
    nonisolated static func split(_ mic: URL, mute: [Bool], into folder: URL) async throws -> (voice: URL, bleed: URL) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = TrackFormat.format
        let input = try AVAudioFile(forReading: mic, commonFormat: .pcmFormatFloat32, interleaved: false)
        let voiceURL = folder.appending(path: "voice.caf"), bleedURL = folder.appending(path: "bleed.caf")
        let voice = try AVAudioFile(forWriting: voiceURL, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let bleed = try AVAudioFile(forWriting: bleedURL, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_000),
              let other = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_000) else {
            throw Failure.noAudio
        }
        let frame = Int(TrackLevels.frame * TrackFormat.sampleRate)
        // Rumble switched on and off reads as thumps the speech model turns into words.
        var filter = HighPass(sampleRate: TrackFormat.sampleRate)
        var gain: Float = 1
        var position = 0
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0], let rest = other.floatChannelData?[0] else { break }
            other.frameLength = buffer.frameLength
            filter.process(UnsafeMutableBufferPointer(start: samples, count: Int(buffer.frameLength)))
            for index in 0..<Int(buffer.frameLength) {
                let at = (position + index) / frame
                let target: Float = at < mute.count && mute[at] ? 0 : 1
                gain += (target - gain) * 0.01
                rest[index] = samples[index] * (1 - gain)
                samples[index] *= gain
            }
            position += Int(buffer.frameLength)
            try voice.write(from: buffer)
            try bleed.write(from: other)
        }
        // Close explicitly: AVAudioFile buffers the last frames until it closes.
        voice.close()
        bleed.close()
        return (voiceURL, bleedURL)
    }

    /// How loud the speech in each stitched track is, frame by frame, read off the
    /// main thread: rumble under the voice is cut first (`HighPass`), or it hides the
    /// leak. Nil when either file won't open; the transcript is then built without it.
    @concurrent
    nonisolated static func levels(mic: URL, call: URL) async -> TrackLevels? {
        func read(_ url: URL) -> [Float]? {
            guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 160_000)
            else { return nil }
            var meter = SpeechLevels(sampleRate: TrackFormat.sampleRate)
            // read(into:) can return less than asked; the meter keeps the frames lined up.
            while file.framePosition < file.length {
                guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
                      let samples = buffer.floatChannelData?[0] else { break }
                meter.add(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
            }
            return meter.levels
        }
        guard let micLevels = read(mic), let callLevels = read(call) else { return nil }
        return TrackLevels(mic: micLevels, call: callLevels)
    }

    /// Joins each track's segments into one file per side, off the main thread, with
    /// silence in front so both share the recording's clock. A side with no segments is nil.
    @concurrent
    nonisolated static func stitch(in audio: URL) async throws -> (mic: URL?, system: URL?) {
        let tracks = Tracks.load(from: audio)
        func one(_ track: Tracks.Track?, name: String) throws -> URL? {
            let segments = SegmentWriter.segments(named: name, in: audio)
            guard !segments.isEmpty else { return nil }
            let url = audio.appending(path: "\(name).caf")
            try Stitcher.stitch(segments, leadingSilence: track?.startOffset ?? 0, to: url)
            return url
        }
        return (try one(tracks.mic, name: "mic"), try one(tracks.system, name: "system"))
    }
}
