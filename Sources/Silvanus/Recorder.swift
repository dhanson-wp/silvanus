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
/// It keeps recording through what it can: call audio that fails drops to the microphone
/// alone, a microphone that changes restarts in a new segment, and a microphone that fails
/// stops the recording and transcribes what was saved.
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
    /// The banner over the canvas: the latest failure (with Retry when there's audio to
    /// transcribe again), or news.
    private(set) var notice: RecorderNotice?
    /// Why the recording stopped early (a microphone that couldn't write). The pill stays up
    /// with it until it's closed.
    private(set) var recordingFailure: String?
    /// Every meeting whose transcription failed, with the reason, until Retry works. The
    /// meeting's page shows it with Retry.
    private(set) var failedMeetings: [String: String] = [:]
    /// Shown in the pill and the banner while recording: call audio couldn't start or
    /// stopped, or a side has been silent for 30 seconds. In the order they came.
    private(set) var warnings: [String] = []
    var warning: String? { warnings.isEmpty ? nil : warnings.joined(separator: " ") }
    /// The live level for the waves, sampled 10 times a second.
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
    @ObservationIgnored var sampleInterval: Duration = .milliseconds(100)
    /// A side silent this long while recording shows a warning.
    @ObservationIgnored var silenceWarning: TimeInterval = 30
    /// For the checks: how many times the level was sampled.
    @ObservationIgnored private(set) var samples = 0

    @ObservationIgnored private var mic: AudioCapture?
    @ObservationIgnored private var system: AudioCapture?
    @ObservationIgnored private var micWriter: SegmentWriter?
    @ObservationIgnored private var systemWriter: SegmentWriter?
    /// Call audio that failed mid-recording: what it saved, for tracks.json.
    @ObservationIgnored private var droppedSystem: Tracks.Track?
    @ObservationIgnored private var sampler: Task<Void, Never>?
    @ObservationIgnored private var systemHeard = Date()
    @ObservationIgnored private var micHeard = Date()
    @ObservationIgnored private var queue: [(id: String, recovered: Bool)] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    /// The app's recorder, for the app delegate: closing the window or quitting mustn't end
    /// a call by surprise.
    @ObservationIgnored private(set) static weak var current: Recorder?

    static let silentCall = "No call audio yet. Check that the call plays on this Mac."
    static let silentMic = "No microphone audio yet. Check the input in System Settings > Sound."
    static let micOnly = "Recording your microphone only."
    static let nothingRecorded = "Nothing was recorded."

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

    /// Seconds into the recording when `id` is the meeting recording, else nil. The notes
    /// stamp new lines with it.
    func elapsed(for id: String) -> TimeInterval? {
        guard isRecording, meetingID == id, let since else { return nil }
        return Date().timeIntervalSince(since)
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
    /// start is a warning: the microphone records on its own.
    func start(into meetingID: String?) throws {
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
        do {
            try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
            let micWriter = SegmentWriter(directory: audio, name: "mic", recordingStart: start)
            let mic = captures.mic()
            try mic.start(into: micWriter)
            self.mic = mic
            self.micWriter = micWriter
        } catch {
            startFailed(error, made: made)
            throw error
        }
        warnings = []
        droppedSystem = nil
        recordingFailure = nil
        let systemWriter = SegmentWriter(directory: audio, name: "system", recordingStart: start)
        let system = captures.system()
        do {
            try system.start(into: systemWriter)
            self.system = system
            self.systemWriter = systemWriter
            Permissions.markSystemAudioAsked()
        } catch {
            addWarning("\(Self.micOnly) \(error.localizedDescription)")
        }
        self.meetingID = id
        meter.reset()
        systemHeard = start
        micHeard = start
        apply(.started(start))
        startSampler()
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

    /// Stop: closes the captures and files, writes `tracks.json`, sets the meeting's end,
    /// and queues the after-call pass. Nothing happens unless a meeting records. A
    /// recording that never got a buffer isn't transcribed: the banner says so.
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
        // The recording may have ended while the question was up (a failure, the pill's
        // Stop): it's already closed, and closing again could only lose what it wrote.
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
        guard micWriter != nil || systemWriter != nil || droppedSystem != nil else { return false }
        sampler?.cancel()
        sampler = nil
        mic?.stop()
        system?.stop()
        micWriter?.finish()
        systemWriter?.finish()
        let tracks = Tracks(mic: micWriter.map(Tracks.Track.init),
                            system: systemWriter.map(Tracks.Track.init) ?? droppedSystem)
        let recorded = (micWriter?.framesWritten ?? 0) + (systemWriter?.framesWritten ?? 0) > 0
            || (droppedSystem?.seconds ?? 0) > 0
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
        droppedSystem = nil
        meetingID = nil
        warnings = []
        meter.reset()
        return recorded
    }

    /// The microphone's writer failed mid-recording: stop, keep what was written, and say
    /// why in the pill (until it's closed) and the banner. What was saved is transcribed.
    private func failRecording(_ reason: String) {
        guard isRecording, let id = meetingID else { return }
        let recorded = closeRecording(id)
        fail(reason)
        recordingFailure = reason
        notice = RecorderNotice(message: reason)
        model?.reload()
        if recorded { enqueue(id, recovered: false) }
    }

    /// Call audio failed mid-recording: keep what it saved, let it go, and record on with the
    /// microphone alone.
    private func dropSystem(_ reason: String) {
        system?.stop()
        systemWriter?.finish()
        droppedSystem = systemWriter.map(Tracks.Track.init)
        system = nil
        systemWriter = nil
        removeWarning(Self.silentCall)
        addWarning("\(Self.micOnly) \(reason)")
        print("RECORDER call audio stopped: \(reason)")
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

    /// Ten times a second while recording: the live level, a writer that failed, and a side
    /// that stays silent.
    func sample() {
        samples += 1
        let micPeak = micWriter?.samplePeak() ?? 0
        let systemPeak = systemWriter?.samplePeak() ?? 0
        meter.push(max(micPeak, systemPeak))
        if let reason = micWriter?.failure {
            failRecording(reason)
            return
        }
        if let reason = systemWriter?.failure { dropSystem(reason) }
        let now = Date()
        if micPeak > 0.001 {
            micHeard = now
            removeWarning(Self.silentMic)
        } else if now.timeIntervalSince(micHeard) > silenceWarning {
            addWarning(Self.silentMic)
        }
        guard systemWriter != nil else { return }
        if systemPeak > 0.001 {
            systemHeard = now
            removeWarning(Self.silentCall)
        } else if now.timeIntervalSince(systemHeard) > silenceWarning {
            addWarning(Self.silentCall)
        }
    }

    private func addWarning(_ text: String) {
        if !warnings.contains(text) { warnings.append(text) }
    }

    private func removeWarning(_ text: String) {
        if warnings.contains(text) { warnings.removeAll { $0 == text } }
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

    /// Closes the banner (and the pill's failure, and clears a failed phase).
    func dismissNotice() {
        notice = nil
        recordingFailure = nil
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
        if isRecording != state.isRecording { isRecording = state.isRecording }
        if since != state.since { since = state.since }
        return true
    }

    private func fail(_ reason: String) {
        apply(.fail(reason))
    }

    /// Snapshots draw the recording and transcribing states without any capture.
    func force(_ phase: RecorderPhase, meetingID: String? = nil, levels: [Float] = [], failure: String? = nil) {
        state = RecorderState(phase: phase)
        isRecording = state.isRecording
        since = state.since
        self.meetingID = state.isRecording ? meetingID : nil
        transcribingID = { if case .transcribing = phase { meetingID } else { nil } }()
        recordingFailure = failure
        meter.reset()
        for level in levels { meter.push(level) }
    }
}

/// The floating recording pill's window: a small always-on-top panel, shown while a
/// meeting records and the main window isn't the key window. It never takes focus from
/// the app in front. It joins every Space, drags by the pill's body, and remembers where it
/// was left (`PillPlacement`). Hovering widens the window leftward to fit the expanded
/// capsule, then narrows it again once the pill has shrunk back.
@MainActor
final class RecordingPanel {
    private let recorder: Recorder
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    /// The capsule's top trailing corner, in screen points.
    private(set) var anchor = NSPoint.zero
    private var hovering = false
    private var shrinkTask: Task<Void, Never>?
    private var dragStart: (mouse: NSPoint, anchor: NSPoint)?
    /// The window around the capsule, collapsed and expanded, measured from the pill at its
    /// widest (an hour into the call).
    private var collapsedSize = NSSize.zero
    private var expandedSize = NSSize.zero
    private let margin = Space.md

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
            _ = recorder.warnings
            _ = recorder.recordingFailure
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
        let key = mainWindowIsKey()
        // A recording that stopped on a failure keeps the pill up, with the reason, until closed.
        if recorder.state.showsPill(mainWindowIsKey: key) || (recorder.recordingFailure != nil && !key) {
            show()
        } else {
            hide()
        }
    }

    var isShowing: Bool { panel != nil }
    var frame: NSRect? { panel?.frame }
    var isExpanded: Bool { panel.map { $0.frame.width >= expandedSize.width } ?? false }

    private func show() {
        guard panel == nil, let model else { return }
        measure()
        let view = RecordingPillHost(recorder: recorder, model: model, panel: self)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(margin)
        let host = PillHostingView(rootView: view)
        let screens = NSScreen.screens.map(\.visibleFrame)
        let main = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        anchor = PillPlacement.resolve(saved: PillPlacement.saved(), screens: screens, main: main)
        hovering = false
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: collapsedSize),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        // The pill's body drags the window itself (a click there opens the meeting), so the
        // window doesn't move by its background.
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        panel = p
        place(size: collapsedSize)
        p.orderFrontRegardless()
    }

    private func hide() {
        shrinkTask?.cancel()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        dragStart = nil
    }

    /// The window sizes that fit the pill at rest and hovered, at its widest.
    private func measure() {
        guard collapsedSize == .zero else { return }
        let meter = LevelMeter()
        let since = Date().addingTimeInterval(-7199)
        func size(_ hover: Bool) -> NSSize {
            let fit = NSHostingView(rootView: RecordingPill(status: .recording(since: since), warning: "x", meter: meter,
                                                            forcedHover: hover).padding(margin)).fittingSize
            return NSSize(width: fit.width.rounded(.up), height: fit.height.rounded(.up))
        }
        collapsedSize = size(false)
        expandedSize = size(true)
    }

    private func place(size: NSSize) {
        guard let panel else { return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let visible = screens.first { $0.insetBy(dx: -1, dy: -1).contains(anchor) }
        panel.setFrame(PillPlacement.frame(anchor: anchor, size: size, inset: margin, visible: visible), display: true)
    }

    /// The pointer entered or left the capsule. The window widens at once, so the capsule
    /// has room to grow; it narrows after the capsule's shrink has played.
    func hoverChanged(_ inside: Bool) {
        hovering = inside
        shrinkTask?.cancel()
        if inside {
            place(size: expandedSize)
        } else {
            shrinkTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled, !self.hovering else { return }
                self.place(size: self.collapsedSize)
            }
        }
    }

    /// Moves the window with the pointer while the body is dragged; the end saves the spot.
    func drag(_ phase: PillDrag, mouse: NSPoint = NSEvent.mouseLocation) {
        switch phase {
        case .began:
            dragStart = (mouse, anchor)
        case .moved:
            guard let start = dragStart, let panel else { return }
            anchor = NSPoint(x: start.anchor.x + mouse.x - start.mouse.x, y: start.anchor.y + mouse.y - start.mouse.y)
            place(size: panel.frame.width >= expandedSize.width ? expandedSize : collapsedSize)
        case .ended:
            dragStart = nil
            if panel != nil { PillPlacement.save(anchor) }
        }
    }
}

/// Lets the first click act on the pill though the panel never becomes key.
final class PillHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The pill with the recorder's values: the meeting's title, any warning, the elapsed time,
/// Stop, and the body that brings the main window forward on the recording meeting.
struct RecordingPillHost: View {
    let recorder: Recorder
    let model: AppModel
    let panel: RecordingPanel

    var body: some View {
        RecordingPill(status: status, title: title, warning: recorder.warning, meter: recorder.meter,
                      open: openMeeting,
                      stop: recorder.stop,
                      dismiss: recorder.dismissNotice,
                      drag: { panel.drag($0) },
                      hoverChanged: { panel.hoverChanged($0) })
    }

    private func openMeeting() {
        if let id = recorder.meetingID, model.meetings.contains(where: { $0.id == id }) { model.selection = id }
        NSApp.activate()
        if let main = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            main.makeKeyAndOrderFront(nil)
        }
    }

    private var status: RecordingPill.Status {
        if let failure = recorder.recordingFailure { return .failed(failure) }
        return switch recorder.phase {
        case let .recording(since): .recording(since: since)
        case let .failed(reason): .failed(reason)
        default: .stopping
        }
    }

    private var title: String {
        recorder.meetingID.flatMap { id in model.meetings.first { $0.id == id }?.displayTitle } ?? "Recording"
    }
}
