import AppKit
import AVFoundation
import SilvanusKit
import SwiftUI

/// One side's capture: my microphone or the call audio. The self-test swaps in fakes that
/// feed made-up buffers, so no check ever opens a device or asks for a permission.
nonisolated protocol AudioCapture: AnyObject, Sendable {
    func start(into writer: SegmentWriter) throws
    func stop()
}

extension MicCapture: AudioCapture {}
extension SystemCapture: AudioCapture {}

/// Makes the two captures for a recording.
struct CaptureFactory {
    var mic: () -> AudioCapture
    var system: () -> AudioCapture

    static let live = CaptureFactory(mic: { MicCapture() }, system: { SystemCapture() })
}

/// A message for the banner over the canvas: a failure with Retry, a warning, or news.
struct RecorderNotice: Equatable {
    var message: String
    /// The meeting Retry transcribes again, when there's something to retry.
    var retryMeetingID: String?
}

/// Starts and stops recordings and runs the after-call pass, one recording at a time. A
/// stopped meeting's transcription goes on behind the next recording, so back-to-back
/// calls both get recorded. The phases are `RecorderState`'s (SilvanusKit), which has the
/// tests; this class does the work each step names.
///
/// It keeps recording through what it can, and says so honestly. Each track's health is
/// watched on its own, from its writer's failures (never from silence, which is normal and
/// never warned about): call audio that
/// fails drops to the microphone alone ("Mic only", with Retry Call Audio in the menu bar),
/// a microphone that changes restarts in a new segment, and a microphone that fails is an
/// interruption ("Audio lost"): the captured time holds and nothing is saved until Retry
/// brings it back or Stop ends the meeting with what was saved.
///
/// Pause holds the shared capture clock: both writers drop what they hear from the same
/// moment, so nothing is saved, the tracks stay aligned, and the time (and the notes'
/// margin times) leave the pause out. Resume goes on in the same meeting.
///
/// A recording started during a call stops when the call ends (`CallEndStop`): once no call
/// app has used audio input or output for 15 seconds (a muted listener still plays the
/// call), the controls count down 10 seconds with Keep
/// recording, then it stops as if Stop were pressed.
@Observable
final class Recorder {
    enum Failure: LocalizedError {
        case busy
        case noFolder

        var errorDescription: String? {
            switch self {
            case .busy: "A meeting is already recording."
            case .noFolder: "The meeting's folder isn't on disk."
            }
        }
    }

    /// What the recording controls and the menu bar show. Stored apart from `state` and set
    /// only when it changes, so the menu bar never redraws on transcription progress.
    enum Mode: Equatable {
        case idle, recording, paused, interrupted
    }

    private(set) var state = RecorderState()
    var phase: RecorderPhase { state.phase }
    /// Kept apart from `state` and set only when it changes, so the menu bar item (its
    /// glyph and its menu) redraws when a recording starts or stops, never on progress.
    /// True while paused or interrupted too: the recording is still under way.
    private(set) var isRecording = false
    private(set) var mode: Mode = .idle
    /// When the recording started (wall clock), while one is under way.
    private(set) var startedAt: Date?
    /// The meeting being recorded.
    private(set) var meetingID: String?
    /// The meeting being transcribed.
    private(set) var transcribingID: String?
    /// The banner over the canvas: the latest failure (with Retry when there's audio to
    /// transcribe again), or news.
    private(set) var notice: RecorderNotice?
    /// Every meeting whose transcription failed, with the reason, until Retry works. The
    /// meeting's page shows it with Retry.
    private(set) var failedMeetings: [String: String] = [:]
    /// Shown in the banner while recording: call audio couldn't start or stopped ("Mic only").
    /// Silence never warns.
    private(set) var warnings: [String] = []
    var warning: String? { warnings.isEmpty ? nil : warnings.joined(separator: " ") }
    /// Why call audio isn't recording, while the microphone records on its own.
    private(set) var callAudioDown: String?
    /// The level bars, from both tracks' captured audio, sampled 10 times a second.
    let meter = LevelMeter()

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored var captures = CaptureFactory.live
    /// True when recording can start without the permissions sheet. Reading it never prompts.
    @ObservationIgnored var permissionsReady: () -> Bool = { Permissions.microphone == .allowed && Permissions.systemAudioAsked }
    /// True when the microphone is allowed: all the sheet's Start Recording needs. System
    /// audio never blocks a recording.
    @ObservationIgnored var micReady: () -> Bool = { Permissions.microphone == .allowed }
    /// The after-call pass for a meeting, reporting progress 0…1 from any thread.
    @ObservationIgnored var afterCall: (String, @escaping @Sendable (Double) -> Void) async throws -> Void
    /// How often the level and the tracks' health are sampled: at most `LevelMath.maxRate`.
    @ObservationIgnored var sampleInterval: Duration = .milliseconds(100)
    /// When the recording stops because the call ended, while the countdown runs ("Call ended.
    /// Stopping in 10 seconds."); set only when it changes.
    private(set) var callEndStopAt: Date?
    /// Stop when the call ends: the rule, and its setting (Settings > General).
    @ObservationIgnored private(set) var callEnd = CallEndStop(callAtStart: false, quickNote: false)
    @ObservationIgnored var stopWhenCallEnds: () -> Bool = { AppDefaults.stopWhenCallEnds }
    /// How long the call must be off the microphone, and the countdown. The self-test shortens them.
    @ObservationIgnored var callEndQuiet: TimeInterval = CallEndStop.quietAfter
    @ObservationIgnored var callEndCountdown: TimeInterval = CallEndStop.countdown
    /// For the checks: how many times the level was sampled.
    @ObservationIgnored private(set) var samples = 0
    /// Whether a call app is using audio input now (Silvanus's own process never counts). The
    /// call detector sets it every 2 seconds; the samples read it for Stop when the call ends.
    @ObservationIgnored var callAppRunning = false
    /// Whether a call app is playing audio now: a muted listener is still in the call.
    @ObservationIgnored var callAppPlaying = false
    /// Whether a call app is using audio input, read once as a recording starts (before our
    /// own microphone opens). The self-test fakes it.
    @ObservationIgnored var callAppProbe: () -> Bool = { CallDetector.Probe.live.callInProgress(recording: false) }
    /// The recording was started by Quick Note: a voice note, never a call.
    @ObservationIgnored private var isQuickNote = false
    /// A call app was using the microphone when the recording started.
    @ObservationIgnored private(set) var callAppAtStart = false

    @ObservationIgnored private var mic: AudioCapture?
    @ObservationIgnored private var system: AudioCapture?
    @ObservationIgnored private var micWriter: SegmentWriter?
    @ObservationIgnored private var systemWriter: SegmentWriter?
    /// The captured clock both writers share.
    @ObservationIgnored private var clock: CaptureClock?
    @ObservationIgnored private var audioDirectory: URL?
    @ObservationIgnored private var level: Float = 0
    /// The current "Audio lost" came while paused: Retry goes back to Paused.
    @ObservationIgnored private var interruptedWhilePaused = false
    @ObservationIgnored private var sampler: Task<Void, Never>?
    @ObservationIgnored private var queue: [(id: String, recovered: Bool)] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    /// The app's recorder, for the app delegate: closing the window or quitting mustn't end
    /// a call by surprise.
    @ObservationIgnored private(set) static weak var current: Recorder?

    static let micOnly = "Recording your microphone only."
    static let nothingRecorded = "Nothing was recorded."
    /// The track names in "Audio lost" notes.
    static let micTrack = "The microphone"

    init(library: MeetingLibrary) {
        afterCall = { id, progress in
            try await AfterCall.run(meetingID: id, library: library, transcriber: .shared, me: AppDefaults.meName,
                                    progress: progress)
        }
        Self.current = self
        // Any quit that gets past applicationShouldTerminate while recording (a logout)
        // closes the files and writes tracks.json; the next launch transcribes the meeting.
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording, let id = self.meetingID else { return }
                _ = self.closeRecording(id)
            }
        }
    }

    /// Captured seconds when `id` is the meeting recording, else nil: pauses and
    /// interruptions left out, so they match the saved audio. The notes stamp new lines
    /// with it.
    func elapsed(for id: String) -> TimeInterval? {
        guard isRecording, meetingID == id else { return nil }
        return state.elapsed(at: Date())
    }

    /// True while `id` records, transcribes, or waits to: it can't be moved to the Trash.
    func isBusy(_ id: String) -> Bool {
        meetingID == id || transcribingID == id || queue.contains { $0.id == id }
    }

    /// True while a pass runs or waits.
    var hasWork: Bool { worker != nil || !queue.isEmpty }

    private var library: MeetingLibrary? { model?.library }

    // MARK: - Recording

    /// Starts recording into `meetingID`, or into a new meeting titled with the date and
    /// time when it's nil, and opens that meeting on My notes. Throws when a meeting is
    /// already recording, or when the microphone can't start: the phase is then failed, the
    /// banner says why, and a meeting made for it is removed again. Call audio that can't
    /// start is a warning: the microphone records on its own. `quickNote` marks a voice
    /// note: it never stops when a call ends.
    func start(into meetingID: String?, quickNote: Bool = false) throws {
        guard let model else { throw Failure.noFolder }
        guard apply(.start) else { throw Failure.busy }
        let start = Date()
        let id: String
        var made: String?
        if let meetingID, model.library.folderExists(for: meetingID) {
            id = meetingID
        } else if let meeting = model.newMeeting(now: start, title: RecordingRules.title(for: start)) {
            id = meeting.id
            made = id
        } else {
            startFailed(Failure.noFolder, made: nil)
            throw Failure.noFolder
        }
        model.settingsOpen = false
        model.open(id)
        model.canvasMode = .notes
        guard let audio = model.library.audioURL(for: id) else {
            startFailed(Failure.noFolder, made: made)
            throw Failure.noFolder
        }
        let clock = CaptureClock(start: start)
        do {
            try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
            let micWriter = SegmentWriter(directory: audio, name: "mic", clock: clock)
            let mic = captures.mic()
            try mic.start(into: micWriter)
            self.mic = mic
            self.micWriter = micWriter
        } catch {
            startFailed(error, made: made)
            throw error
        }
        self.clock = clock
        audioDirectory = audio
        warnings = []
        callAudioDown = nil
        startSystem(into: SegmentWriter(directory: audio, name: "system", clock: clock))
        self.meetingID = id
        startedAt = start
        level = 0
        meter.reset()
        isQuickNote = quickNote
        callAppAtStart = quickNote ? false : callAppProbe()
        callAppRunning = callAppAtStart
        callEnd = CallEndStop(callAtStart: callAppAtStart, quickNote: quickNote, quietAfter: callEndQuiet,
                              countdown: callEndCountdown)
        syncCallEnd()
        apply(.started(start))
        startSampler()
    }

    /// Starts call audio into `writer`. A failure is a warning: the microphone records on
    /// its own ("Mic only"), and Retry Call Audio can try again.
    private func startSystem(into writer: SegmentWriter) {
        let system = captures.system()
        do {
            try system.start(into: writer)
            self.system = system
            systemWriter = writer
            callAudioDown = nil
            warnings.removeAll { $0.hasPrefix(Self.micOnly) }
            Permissions.markSystemAudioAsked()
        } catch {
            callAudioDown = error.localizedDescription
            warnings.removeAll { $0.hasPrefix(Self.micOnly) }
            addWarning("\(Self.micOnly) \(error.localizedDescription)")
        }
    }

    /// A start that failed: say why in the banner (nothing to retry), and remove a meeting
    /// made for this recording, since nothing was recorded into it.
    private func startFailed(_ error: Error, made: String?) {
        let reason = "Couldn't start recording: \(error.localizedDescription)"
        fail(reason)
        notice = RecorderNotice(message: reason)
        mic = nil
        micWriter = nil
        guard let made, let model else { return }
        do {
            try model.library.moveToTrash(made)
        } catch {
            print("RECORDER couldn't remove the empty meeting \(made): \(error)")
        }
        if model.selection == made { model.selection = nil }
        model.reload()
    }

    /// Pause: the time holds from this moment, both captures stop (the devices are released,
    /// so the microphone indicator goes off), and nothing is saved. Only while capturing
    /// (never while audio is lost).
    func pause() {
        guard state.isCapturing else { return }
        let now = Date()
        clock?.hold(at: now)
        mic?.stop()
        system?.stop()
        apply(.pause(now))
        level = 0
        meter.reset()
        stepCallEnd(at: now)
    }

    /// Resume: both captures start again into the same tracks, lined up with the clock, and
    /// the same meeting goes on from the time it held. A microphone that won't start is
    /// "Audio lost" (Retry, Stop); call audio that won't start is "Mic only".
    func resume() {
        guard state.isPaused else { return }
        guard let mic, let micWriter else {
            interrupt("Couldn't restart the microphone: it isn't running.", whilePaused: false)
            return
        }
        // The clock runs before the devices start, so their first audio counts as after.
        releaseClock(RecorderEvent.resume)
        do {
            try mic.start(into: micWriter)
        } catch {
            interrupt("Couldn't restart the microphone: \(error.localizedDescription)", whilePaused: false)
            return
        }
        restartSystem()
    }

    /// The controls' Pause/Resume button.
    func togglePause() {
        if state.isPaused { resume() } else { pause() }
    }

    /// Retry while audio is lost: restarts the microphone into its track (and call audio, if
    /// that's down too). Stays "Audio lost", with the new reason, while it can't start. A
    /// failure that came while paused goes back to Paused, with the devices released again.
    func retryCapture() {
        guard case .interrupted = phase else { return }
        if interruptedWhilePaused {
            if let reason = restartMic() {
                apply(.interrupt(Date(), reason))
                return
            }
            mic?.stop()
            apply(.recoveredToPause)
            return
        }
        releaseClock(RecorderEvent.recovered)
        if let reason = restartMic() {
            interrupt(reason, whilePaused: false)
            return
        }
        restartSystem()
        if callAudioDown != nil { retryCallAudio() }
    }

    /// Lets the clock run again (Resume, Retry): both tracks line up with it first, so each
    /// one's first buffer pads or trims to the same instant whatever its buffer size.
    private func releaseClock(_ event: (Date) -> RecorderEvent) {
        micWriter?.lineUp()
        systemWriter?.lineUp()
        let now = Date()
        clock?.release(at: now)
        apply(event(now))
    }

    /// Starts call audio again in its track after a hold; a failure drops to Mic only.
    private func restartSystem() {
        guard let system, let writer = systemWriter else { return }
        do {
            try system.start(into: writer)
        } catch {
            dropSystem("Couldn't restart call audio: \(error.localizedDescription)")
        }
    }

    /// Retry Call Audio (menu bar), while the microphone records on its own: starts call
    /// audio again in its track, lined up with the recording's clock.
    func retryCallAudio() {
        guard state.isCapturing, system == nil, let audio = audioDirectory, let clock else { return }
        let writer = systemWriter ?? SegmentWriter(directory: audio, name: "system", clock: clock)
        writer.resume()
        startSystem(into: writer)
    }

    /// Starts a new microphone capture in the same track. Nil when it runs, else why not.
    private func restartMic() -> String? {
        guard let writer = micWriter else { return "The meeting's folder isn't on disk." }
        mic?.stop()
        mic = nil
        writer.resume()
        let capture = captures.mic()
        do {
            try capture.start(into: writer)
            mic = capture
            return nil
        } catch {
            return "Couldn't restart the microphone: \(error.localizedDescription)"
        }
    }

    /// Stop: closes the captures and files, writes `tracks.json`, sets the meeting's end,
    /// and queues the after-call pass. Works while recording, paused, or with audio lost;
    /// nothing happens otherwise. A recording that never got a buffer isn't transcribed:
    /// the banner says so.
    func stop() {
        guard isRecording, let id = meetingID else { return }
        apply(.stop)
        let recorded = closeRecording(id)
        apply(.stopped)
        model?.reload()
        if recorded {
            enqueue(id, recovered: false)
        } else {
            notice = RecorderNotice(message: Self.nothingRecorded)
            if worker == nil { apply(.finished) }
        }
    }

    /// ⌘Q while recording: `confirm` asks "A meeting is recording. Stop and quit?". Stop
    /// and Quit closes the files (the next launch transcribes the meeting) and quits;
    /// Cancel keeps recording.
    func terminateReply(confirm: () -> Bool) -> NSApplication.TerminateReply {
        guard isRecording, let id = meetingID else { return .terminateNow }
        guard confirm() else { return .terminateCancel }
        // The recording may have ended while the question was up (the controls' Stop): it's
        // already closed, and closing again could only lose what it wrote.
        guard isRecording, meetingID == id else { return .terminateNow }
        apply(.stop)
        _ = closeRecording(id)
        return .terminateNow
    }

    /// Stops the captures, closes the files, and writes what the meeting needs to be
    /// transcribed later: `tracks.json` and the end time. True when any audio was written.
    private func closeRecording(_ id: String) -> Bool {
        // Already closed: tracks.json and the end time are written; never overwrite them
        // with empty tracks.
        guard micWriter != nil || systemWriter != nil else { return false }
        sampler?.cancel()
        sampler = nil
        mic?.stop()
        system?.stop()
        micWriter?.finish()
        systemWriter?.finish()
        let tracks = Tracks(mic: micWriter.map(Tracks.Track.init), system: systemWriter.map(Tracks.Track.init))
        let recorded = (micWriter?.framesWritten ?? 0) + (systemWriter?.framesWritten ?? 0) > 0
        if let audio = library?.audioURL(for: id) {
            do { try tracks.save(in: audio) } catch { print("RECORDER couldn't write tracks.json for \(id): \(error)") }
        }
        if let library, var meeting = library.meeting(id: id) {
            meeting.info.end = Date()
            do { try library.saveInfo(meeting) } catch { print("RECORDER couldn't save the end time for \(id): \(error)") }
        }
        mic = nil
        system = nil
        micWriter = nil
        systemWriter = nil
        clock = nil
        audioDirectory = nil
        meetingID = nil
        startedAt = nil
        warnings = []
        callAudioDown = nil
        callEnd = CallEndStop(callAtStart: false, quickNote: false)
        syncCallEnd()
        level = 0
        meter.reset()
        return recorded
    }

    /// A required track (the microphone) failed: hold the clock, so neither track saves,
    /// and say so ("Audio lost", with Retry and Stop). Silence never comes here.
    private func interrupt(_ reason: String, whilePaused: Bool? = nil) {
        guard isRecording else { return }
        interruptedWhilePaused = whilePaused ?? state.isPaused
        let now = Date()
        clock?.hold(at: now)
        mic?.stop()
        mic = nil
        // Call audio waits too, so both tracks skip the same stretch; Retry restarts it.
        system?.stop()
        apply(.interrupt(now, reason))
        level = 0
        meter.reset()
        stepCallEnd(at: now)
        print("RECORDER audio lost: \(reason)")
    }

    /// For the checks: the microphone's writer reports a failure, as a device or a disk might.
    func failMicForChecks(_ reason: String) {
        micWriter?.recordFailure(reason)
    }

    /// Call audio failed mid-recording: keep what it saved in its track, let it go, and
    /// record on with the microphone alone ("Mic only"). Retry Call Audio can bring it back.
    private func dropSystem(_ reason: String) {
        system?.stop()
        system = nil
        callAudioDown = reason
        warnings.removeAll { $0.hasPrefix(Self.micOnly) }
        addWarning("\(Self.micOnly) \(reason)")
        print("RECORDER call audio stopped: \(reason)")
    }

    private func startSampler() {
        sampler?.cancel()
        let interval = max(sampleInterval, .milliseconds(Int(1000 / LevelMath.maxRate)))
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, self.isRecording else { return }
                self.sample()
            }
        }
    }

    /// Ten times a second while recording: the level bars, each track's health, and Stop
    /// when the call ends. The bars combine both tracks; health is per track, from the
    /// writers' failures, never from silence (silence is normal and never warns).
    func sample() {
        samples += 1
        let mic = micWriter?.sampleLevels() ?? (peak: 0, rms: 0)
        let call = systemWriter?.sampleLevels() ?? (peak: 0, rms: 0)
        let capturing = state.isCapturing
        let next = capturing ? max(LevelMath.level(rms: mic.rms), LevelMath.level(rms: call.rms)) : 0
        level = capturing ? LevelMath.smooth(previous: level, next: next) : 0
        meter.push(level)
        if !state.isInterrupted, let reason = micWriter?.failure {
            interrupt(reason)
            return
        }
        if system != nil, let reason = systemWriter?.failure { dropSystem(reason) }
        stepCallEnd(at: Date())
    }

    /// Steps Stop when the call ends with what the call detector last saw; at 0 it stops,
    /// exactly as Stop does.
    private func stepCallEnd(at now: Date) {
        let action = callEnd.step(at: now, callInput: callAppRunning, callOutput: callAppPlaying,
                                  capturing: state.isCapturing, enabled: stopWhenCallEnds())
        syncCallEnd()
        if action == .stop {
            print("RECORDER the call ended: stopping")
            stop()
        }
    }

    /// The countdown's Keep recording: records on, and nothing counts until a new call starts.
    func keepRecording() {
        callEnd.keepRecording()
        syncCallEnd()
    }

    private func syncCallEnd() {
        let next = isRecording ? callEnd.stopAt : nil
        if callEndStopAt != next { callEndStopAt = next }
    }

    private func addWarning(_ text: String) {
        if !warnings.contains(text) { warnings.append(text) }
    }

    // MARK: - Transcribing

    /// Queues the after-call pass. One runs at a time; each reloads the meetings when done
    /// and opens the Transcript if that meeting is open.
    private func enqueue(_ id: String, recovered: Bool) {
        guard !queue.contains(where: { $0.id == id }), transcribingID != id else { return }
        queue.append((id, recovered))
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            transcribingID = job.id
            apply(.transcribe)
            do {
                try await afterCall(job.id) { [weak self] progress in
                    Task { @MainActor in self?.progress(progress) }
                }
                finished(job.id, recovered: job.recovered)
            } catch {
                failed(job.id, error)
            }
        }
        transcribingID = nil
        worker = nil
        if case .transcribing = phase { apply(.finished) }
    }

    private func progress(_ value: Double) {
        guard case let .transcribing(current) = phase, abs(value - current) >= 0.01 || value >= 1 else { return }
        apply(.progress(value))
    }

    private func finished(_ id: String, recovered: Bool) {
        try? library?.setTranscriptionAttempts(0, for: id)
        failedMeetings[id] = nil
        guard let model else { return }
        model.reload()
        model.writeTodos(for: id, asked: false)
        if recovered {
            notice = RecorderNotice(message: "Finished transcribing an interrupted recording")
        }
        if model.selection == id, !model.settingsOpen {
            model.show(.transcript)
        }
    }

    /// A failed pass counts toward the meeting's attempts; the meeting keeps its failure
    /// (with Retry) until a pass works.
    private func failed(_ id: String, _ error: Error) {
        let attempts = (library?.transcriptionAttempts(for: id) ?? 0) + 1
        try? library?.setTranscriptionAttempts(attempts, for: id)
        let reason = "Couldn't transcribe this meeting: \(error.localizedDescription)"
        print("RECORDER \(id): \(reason) (attempt \(attempts))")
        failedMeetings[id] = reason
        notice = RecorderNotice(message: reason, retryMeetingID: id)
        if case .transcribing = phase { apply(.fail(reason)) }
    }

    /// The banner's Retry: runs the after-call pass again on the saved audio.
    func retry() {
        guard let id = notice?.retryMeetingID else { return }
        retry(id)
    }

    /// Retry on a meeting whose transcription failed: starts its count over and runs the
    /// pass again.
    func retry(_ id: String) {
        if notice?.retryMeetingID == id { notice = nil }
        failedMeetings[id] = nil
        try? library?.setTranscriptionAttempts(0, for: id)
        enqueue(id, recovered: false)
    }

    /// Closes the banner (and clears a failed phase).
    func dismissNotice() {
        notice = nil
        if case .failed = phase { apply(.dismiss) }
    }

    /// At launch: any meeting whose audio folder holds segments but no transcript was cut
    /// off by a quit or crash, or its transcription failed. Each gets `tracks.json` (both
    /// tracks from zero) if it's missing and an end time, then the after-call pass, with a
    /// banner when it's done. A meeting that already failed `RecordingRules.maxAttempts`
    /// times isn't retried: it shows as failed, with Retry. Returns the meetings queued.
    @discardableResult
    func recoverInterrupted(library: MeetingLibrary) -> [String] {
        let fm = FileManager.default
        let meetings = model?.meetings ?? library.loadAll().meetings
        var queued: [String] = []
        for meeting in meetings where meeting.id != meetingID {
            guard let audio = library.audioURL(for: meeting.id), fm.fileExists(atPath: audio.path) else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: audio.path)) ?? []
            let transcript = audio.deletingLastPathComponent().appending(path: MeetingFolder.transcriptJSON)
            guard RecordingRules.isInterrupted(audioFiles: files, hasTranscript: fm.fileExists(atPath: transcript.path)) else { continue }
            let attempts = library.transcriptionAttempts(for: meeting.id)
            guard RecordingRules.shouldAutoRetry(attempts: attempts) else {
                failedMeetings[meeting.id] = "Transcription failed \(attempts) times, so it won't run on its own again."
                continue
            }
            if !files.contains(Tracks.fileName) {
                func track(_ name: String) -> Tracks.Track? {
                    RecordingRules.segments(in: files, track: name).isEmpty ? nil : Tracks.Track(startOffset: 0, seconds: 0)
                }
                try? Tracks(mic: track("mic"), system: track("system")).save(in: audio)
            }
            if var info = library.meeting(id: meeting.id), info.info.end == nil {
                let dates = files.compactMap {
                    try? audio.appending(path: $0).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                }
                info.info.end = dates.max()
                try? library.saveInfo(info)
            }
            queued.append(meeting.id)
            enqueue(meeting.id, recovered: true)
        }
        return queued
    }

    // MARK: - State

    @discardableResult
    private func apply(_ event: RecorderEvent) -> Bool {
        guard state.apply(event) else { return false }
        syncStored()
        return true
    }

    /// The stored copies the menu bar and the controls read, set only when they change.
    private func syncStored() {
        if isRecording != state.isRecording { isRecording = state.isRecording }
        let next: Mode = switch state.phase {
        case .recording: .recording
        case .paused: .paused
        case .interrupted: .interrupted
        default: .idle
        }
        if mode != next { mode = next }
    }

    private func fail(_ reason: String) {
        apply(.fail(reason))
    }

    /// Snapshots and the gallery draw the recording states without any capture.
    func force(_ phase: RecorderPhase, meetingID: String? = nil, levels: [Float] = [], callAudioDown: String? = nil,
               callEndStopAt: Date? = nil) {
        state = RecorderState(phase: phase)
        syncStored()
        self.callEndStopAt = state.isRecording ? callEndStopAt : nil
        self.meetingID = state.isRecording ? meetingID : nil
        startedAt = state.isRecording ? (startedAt ?? Date()) : nil
        transcribingID = { if case .transcribing = phase { meetingID } else { nil } }()
        self.callAudioDown = callAudioDown
        meter.reset()
        for level in levels { meter.push(level) }
    }
}
