import FluidAudio
import Foundation
import SilvanusKit

/// The after-call pass for one meeting: stitches each track's segment files in
/// `<meeting folder>/audio/` into `mic.caf` and `system.caf`, transcribes both
/// sides, drops mic lines that echo the call, and writes `transcript.json` and
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
        var mine: [Word] = [], theirs: [Word] = []
        if let url = stitched.mic {
            mine = try await transcriber.words(in: url, source: .microphone)
            done += 0.6 / sides
            progress(done)
        }
        if let url = stitched.system {
            theirs = try await transcriber.words(in: url, source: .system)
            done += 0.6 / sides
            progress(done)
        }
        var transcript = TranscriptBuilder.build(me: mine, them: theirs, engine: Transcriber.engineName)
        // Whole seconds, as the JSON keeps them, so what this returns is what's on disk.
        transcript.processedAt = Date(timeIntervalSince1970: transcript.processedAt.timeIntervalSince1970.rounded(.down))

        // Read again just before writing, so a rename made meanwhile is kept.
        guard var meeting = library.meeting(id: meetingID) else { throw Failure.noMeeting(meetingID) }
        let names = SpeakerNames.resolve(info: meeting.info, defaultMe: me)
        try library.saveTranscript(transcript, markdown: transcript.markdown(me: names.me, them: names.them) + "\n",
                                   for: meetingID)
        meeting.info.asr = ASRInfo(engine: Transcriber.engine, model: Transcriber.model, processedAt: transcript.processedAt)
        try library.saveInfo(meeting)
        progress(1)
        return transcript
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
