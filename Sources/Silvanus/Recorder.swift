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

    private(set) var state = RecorderState()
    var phase: RecorderPhase { state.phase }
    /// Kept apart from `state` and set only when it changes, so the menu bar item (its
    /// glyph and its menu) redraws when a recording starts or stops, never on progress.
    private(set) var isRecording = false
    /// When the recording started, while it records.
    private(set) var since: Date?
    /// The meeting being recorded.
    private(set) var meetingID: String?
    /// The meeting being transcribed.
    private(set) var transcribingID: String?
    /// The banner over the canvas: a failure with Retry, or news.
    private(set) var notice: RecorderNotice?
    /// Shown in the pill and the banner while recording: call audio couldn't start, or
    /// has been silent for 30 seconds.
    private(set) var warning: String?
    /// The live level for the waves, sampled 10 times a second.
    let meter = LevelMeter()

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored var captures = CaptureFactory.live
    /// True when recording can start without asking for a permission first. Reading it
    /// never prompts.
    @ObservationIgnored var permissionsReady: () -> Bool = { Permissions.microphone == .allowed && Permissions.systemAudioAsked }
    /// The after-call pass for a meeting, reporting progress 0…1 from any thread.
    @ObservationIgnored var afterCall: (String, @escaping @Sendable (Double) -> Void) async throws -> Void
    @ObservationIgnored var sampleInterval: Duration = .milliseconds(100)
    /// Call audio silent this long while recording shows a warning.
    @ObservationIgnored var silenceWarning: TimeInterval = 30
    /// For the checks: how many times the level was sampled.
    @ObservationIgnored private(set) var samples = 0

    @ObservationIgnored private var mic: AudioCapture?
    @ObservationIgnored private var system: AudioCapture?
    @ObservationIgnored private var micWriter: SegmentWriter?
    @ObservationIgnored private var systemWriter: SegmentWriter?
    @ObservationIgnored private var sampler: Task<Void, Never>?
    @ObservationIgnored private var systemHeard = Date()
    @ObservationIgnored private var queue: [(id: String, recovered: Bool)] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    /// The app's recorder, for the app delegate: closing the window mustn't quit mid-call.
    @ObservationIgnored private(set) static weak var current: Recorder?

    init(library: MeetingLibrary) {
        afterCall = { id, progress in
            try await AfterCall.run(meetingID: id, library: library, transcriber: .shared, me: AppDefaults.meName,
                                    progress: progress)
        }
        Self.current = self
        // Quitting while recording closes the files and writes tracks.json; the next launch
        // transcribes the meeting (recoverInterrupted).
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording, let id = self.meetingID else { return }
                self.closeRecording(id)
            }
        }
    }

    /// Seconds into the recording when `id` is the meeting recording, else nil. The notes
    /// stamp new lines with it.
    func elapsed(for id: String) -> TimeInterval? {
        guard isRecording, meetingID == id, let since else { return nil }
        return Date().timeIntervalSince(since)
    }

    private var library: MeetingLibrary? { model?.library }

    // MARK: - Recording

    /// Starts recording into `meetingID`, or into a new meeting titled with the date and
    /// time when it's nil, and opens that meeting on My notes. Throws when a meeting is
    /// already recording, or when the microphone can't start (the phase is then failed).
    /// Call audio that can't start is a warning: the microphone records on its own.
    func start(into meetingID: String?) throws {
        guard let model else { throw Failure.noFolder }
        guard apply(.start) else { throw Failure.busy }
        let start = Date()
        let id: String
        if let meetingID, model.library.folderExists(for: meetingID) {
            id = meetingID
        } else if let made = model.newMeeting(now: start, title: RecordingRules.title(for: start)) {
            id = made.id
        } else {
            fail("Couldn't start recording: \(Failure.noFolder.localizedDescription)")
            throw Failure.noFolder
        }
        model.settingsOpen = false
        model.open(id)
        model.canvasMode = .notes
        guard let audio = model.library.audioURL(for: id) else {
            fail("Couldn't start recording: \(Failure.noFolder.localizedDescription)")
            throw Failure.noFolder
        }
        do {
            try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
            let micWriter = SegmentWriter(directory: audio, name: "mic", recordingStart: start)
            let mic = captures.mic()
            try mic.start(into: micWriter)
            self.mic = mic
            self.micWriter = micWriter
        } catch {
            fail("Couldn't start recording: \(error.localizedDescription)")
            throw error
        }
        let systemWriter = SegmentWriter(directory: audio, name: "system", recordingStart: start)
        let system = captures.system()
        do {
            try system.start(into: systemWriter)
            self.system = system
            self.systemWriter = systemWriter
            warning = nil
            Permissions.markSystemAudioAsked()
        } catch {
            warning = "Recording your microphone only. \(error.localizedDescription)"
        }
        self.meetingID = id
        meter.reset()
        systemHeard = start
        apply(.started(start))
        startSampler()
    }

    /// Stop: closes the captures and files, writes `tracks.json`, sets the meeting's end,
    /// and queues the after-call pass. Nothing happens unless a meeting records.
    func stop() {
        guard isRecording, let id = meetingID else { return }
        apply(.stop)
        closeRecording(id)
        apply(.stopped)
        model?.reload()
        enqueue(id, recovered: false)
    }

    /// Stops the captures, closes the files, and writes what the meeting needs to be
    /// transcribed later: `tracks.json` and the end time.
    private func closeRecording(_ id: String) {
        sampler?.cancel()
        sampler = nil
        mic?.stop()
        system?.stop()
        micWriter?.finish()
        systemWriter?.finish()
        let tracks = Tracks(mic: micWriter.map(Tracks.Track.init), system: systemWriter.map(Tracks.Track.init))
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
        meetingID = nil
        warning = nil
        meter.reset()
    }

    /// A writer failed mid-recording: stop, keep what was written, and say why. Retry
    /// transcribes the audio saved so far.
    private func failRecording(_ reason: String) {
        guard isRecording, let id = meetingID else { return }
        closeRecording(id)
        fail(reason)
        notice = RecorderNotice(message: reason, retryMeetingID: id)
        model?.reload()
    }

    private func startSampler() {
        sampler?.cancel()
        let interval = sampleInterval
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, self.isRecording else { return }
                self.sample()
            }
        }
    }

    /// Ten times a second while recording: the live level, a writer that failed, and call
    /// audio that stays silent.
    func sample() {
        samples += 1
        let micPeak = micWriter?.samplePeak() ?? 0
        let systemPeak = systemWriter?.samplePeak() ?? 0
        meter.push(max(micPeak, systemPeak))
        if let reason = micWriter?.failure ?? systemWriter?.failure {
            failRecording(reason)
            return
        }
        guard systemWriter != nil else { return }
        let now = Date()
        if systemPeak > 0.001 {
            systemHeard = now
            if warning == Self.silentCall { warning = nil }
        } else if now.timeIntervalSince(systemHeard) > silenceWarning, warning == nil {
            warning = Self.silentCall
        }
    }

    static let silentCall = "No call audio yet. Check that the call plays on this Mac."

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
                let reason = "Couldn't transcribe this meeting: \(error.localizedDescription)"
                print("RECORDER \(job.id): \(reason)")
                notice = RecorderNotice(message: reason, retryMeetingID: job.id)
                if case .transcribing = phase { apply(.fail(reason)) }
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
        guard let model else { return }
        model.reload()
        if recovered {
            notice = RecorderNotice(message: "Finished transcribing an interrupted recording")
        }
        if model.selection == id, !model.settingsOpen {
            model.show(.transcript)
        }
    }

    /// The banner's Retry: runs the after-call pass again on the saved audio.
    func retry() {
        guard let id = notice?.retryMeetingID else { return }
        notice = nil
        enqueue(id, recovered: false)
    }

    /// Closes the banner (and clears a failure).
    func dismissNotice() {
        notice = nil
        if case .failed = phase { apply(.dismiss) }
    }

    /// At launch: any meeting whose audio folder holds segments but no transcript was cut
    /// off by a quit or crash. Each gets `tracks.json` (both tracks from zero) if it's
    /// missing and an end time, then the after-call pass, with a banner when it's done.
    /// Returns the meetings queued.
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
        if isRecording != state.isRecording { isRecording = state.isRecording }
        if since != state.since { since = state.since }
        return true
    }

    private func fail(_ reason: String) {
        apply(.fail(reason))
    }

    /// Snapshots draw the recording and transcribing states without any capture.
    func force(_ phase: RecorderPhase, meetingID: String? = nil, levels: [Float] = []) {
        state = RecorderState(phase: phase)
        isRecording = state.isRecording
        since = state.since
        self.meetingID = state.isRecording ? meetingID : nil
        transcribingID = { if case .transcribing = phase { meetingID } else { nil } }()
        meter.reset()
        for level in levels { meter.push(level) }
    }
}

/// The floating recording pill's window: a small always-on-top panel, shown while a
/// meeting records and the main window isn't the key window. It never takes focus from
/// the app in front.
@MainActor
final class RecordingPanel {
    private let recorder: Recorder
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []

    init(recorder: Recorder, model: AppModel) {
        self.recorder = recorder
        self.model = model
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                          NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        track()
        update()
    }

    /// Updates when the recorder's phase or warning changes.
    private func track() {
        withObservationTracking {
            _ = recorder.isRecording
            _ = recorder.phase
            _ = recorder.warning
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.track()
            }
        }
    }

    /// True when the main window is the key window. The self-test sets it: a run started
    /// from a terminal may never be the active app.
    var mainWindowIsKey: () -> Bool = {
        NSApp.windows.contains { $0.isKeyWindow && $0.canBecomeMain && !($0 is NSPanel) }
    }

    func update() {
        if recorder.state.showsPill(mainWindowIsKey: mainWindowIsKey()) { show() } else { hide() }
    }

    var isShowing: Bool { panel != nil }

    private func show() {
        guard panel == nil, let model else { return }
        let view = RecordingPillHost(recorder: recorder, model: model)
            .padding(Space.md)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.setFrameSize(size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        if let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - size.width - Space.md, y: screen.maxY - size.height - Space.md))
        }
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

/// The pill with the recorder's values: the meeting's title (or the warning), the elapsed
/// time, Stop, and the live button that brings the main window forward.
struct RecordingPillHost: View {
    let recorder: Recorder
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RecordingPill(status: status, line: line, meter: recorder.meter,
                      open: {
                          NSApp.activate()
                          if let main = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                              main.makeKeyAndOrderFront(nil)
                          }
                      },
                      stop: recorder.stop)
    }

    private var status: RecordingPill.Status {
        switch recorder.phase {
        case let .recording(since): .recording(since: since)
        case let .failed(reason): .failed(reason)
        default: .stopping
        }
    }

    private var line: String {
        if let warning = recorder.warning { return warning }
        let title = recorder.meetingID.flatMap { id in model.meetings.first { $0.id == id }?.displayTitle }
        return title ?? "Recording"
    }
}
