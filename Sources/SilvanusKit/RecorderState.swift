import Foundation

/// Where the recorder is. One recording at a time; a finished recording's transcription
/// can go on behind the next one (a back-to-back call).
///
/// A recording under way is `recording`, `paused`, or `interrupted`. Its time is captured
/// time: pauses and interruptions don't count, so it matches the saved audio, the
/// transcript, and the notes' margin times.
public enum RecorderPhase: Equatable, Sendable {
    case idle
    case starting
    /// Capturing. `since` is the clock origin: the captured time is now − `since`. At the
    /// start it's when the recording started; each Resume or Retry moves it later by the
    /// time that wasn't captured.
    case recording(since: Date)
    /// Pause: both tracks drop what they hear; `elapsed` is the captured time, held.
    case paused(elapsed: TimeInterval)
    /// A required track stopped (the microphone): nothing is saved until Retry works.
    /// `elapsed` is the captured time, held; `reason` says what stopped.
    case interrupted(elapsed: TimeInterval, reason: String)
    case stopping
    case transcribing(progress: Double)
    case failed(String)
}

/// What happens to the recorder. `RecorderState.apply` says whether it was taken.
public enum RecorderEvent: Equatable, Sendable {
    /// Start Recording or Quick Note.
    case start
    /// The captures are running.
    case started(Date)
    /// Pause, at a moment.
    case pause(Date)
    /// Resume after Pause, at a moment.
    case resume(Date)
    /// A required track's capture failed, at a moment.
    case interrupt(Date, String)
    /// Retry worked: the track captures again, at a moment.
    case recovered(Date)
    /// Retry worked on a failure that came while paused: back to Paused, the time still held.
    case recoveredToPause
    /// Stop. Allowed while recording, paused, or interrupted.
    case stop
    /// The captures and files are closed; transcription begins.
    case stopped
    case progress(Double)
    case finished
    case fail(String)
    /// Retry, or a recording recovered at launch: transcribe without recording first.
    case transcribe
    /// The failure was seen.
    case dismiss
}

/// The recorder's state machine, with no audio and no UI: the app's `Recorder` drives it
/// and does the work each step names.
public struct RecorderState: Equatable, Sendable {
    public private(set) var phase: RecorderPhase

    public init(phase: RecorderPhase = .idle) {
        self.phase = phase
    }

    /// True while a recording is under way: capturing, paused, or interrupted. The menu bar,
    /// ⌘Q, and Move to Trash treat all three alike.
    public var isRecording: Bool {
        switch phase {
        case .recording, .paused, .interrupted: true
        default: false
        }
    }

    /// True only while audio is being saved.
    public var isCapturing: Bool {
        if case .recording = phase { true } else { false }
    }

    public var isPaused: Bool {
        if case .paused = phase { true } else { false }
    }

    public var isInterrupted: Bool {
        if case .interrupted = phase { true } else { false }
    }

    /// The captured time at `date` while a recording is under way, else nil. Held while
    /// paused or interrupted.
    public func elapsed(at date: Date) -> TimeInterval? {
        switch phase {
        case let .recording(since): max(0, date.timeIntervalSince(since))
        case let .paused(elapsed), let .interrupted(elapsed, _): elapsed
        default: nil
        }
    }

    /// Applies an event; false when it doesn't fit the phase (the phase stays).
    @discardableResult
    public mutating func apply(_ event: RecorderEvent) -> Bool {
        let next: RecorderPhase? = switch (phase, event) {
        // Start while recording (or getting there, or wrapping up) is refused.
        case (.idle, .start), (.transcribing, .start), (.failed, .start): .starting
        case let (.starting, .started(date)): .recording(since: date)
        case let (.recording(since), .pause(date)): .paused(elapsed: max(0, date.timeIntervalSince(since)))
        case let (.paused(elapsed), .resume(date)): .recording(since: date.addingTimeInterval(-elapsed))
        case let (.recording(since), .interrupt(date, reason)):
            .interrupted(elapsed: max(0, date.timeIntervalSince(since)), reason: reason)
        // A track can fail while paused (a device unplugged): Resume would only lie.
        case let (.paused(elapsed), .interrupt(_, reason)), let (.interrupted(elapsed, _), .interrupt(_, reason)):
            .interrupted(elapsed: elapsed, reason: reason)
        case let (.interrupted(elapsed, _), .recovered(date)): .recording(since: date.addingTimeInterval(-elapsed))
        case let (.interrupted(elapsed, _), .recoveredToPause): .paused(elapsed: elapsed)
        case (.recording, .stop), (.paused, .stop), (.interrupted, .stop): .stopping
        case (.stopping, .stopped): .transcribing(progress: 0)
        case let (.transcribing, .progress(p)): .transcribing(progress: min(1, max(0, p)))
        case (.transcribing, .finished): .idle
        case (.idle, .transcribe), (.failed, .transcribe): .transcribing(progress: 0)
        case (.failed, .dismiss): .idle
        case let (_, .fail(reason)): .failed(reason)
        default: nil
        }
        guard let next else { return false }
        phase = next
        return true
    }

    /// The recording controls show for the whole recording, whichever app is in front.
    public var showsControls: Bool { isRecording }
}

/// The rules around starting a recording and finding one cut off by a quit or crash.
public enum RecordingRules {
    /// Start Recording records into the open meeting when it was made here, has no audio
    /// and no transcript yet, and started in the last 12 hours (so ⇧⌘R never records into
    /// last week's notes). Otherwise it starts a new meeting.
    public static func canRecord(into meeting: Meeting, hasAudio: Bool, hasTranscript: Bool, now: Date = Date()) -> Bool {
        meeting.info.source == "silvanus" && !hasAudio && !hasTranscript
            && now.timeIntervalSince(meeting.info.start) < 12 * 3600
    }

    /// A new recording's title: its date and time ("Nov 6, 2026 at 2:30 PM").
    public static func title(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return plainSpaces(formatter.string(from: date))
    }

    /// The menu bar item's static line while recording ("Recording since 2:30 PM").
    /// Never a running timer: the menu bar must not change every second.
    public static func since(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Recording since \(plainSpaces(formatter.string(from: date)))"
    }

    /// Formatters put a narrow no-break space before AM and PM; titles name folders on
    /// disk, so they get a plain space.
    private static func plainSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// After this many failed after-call passes in a row, launch stops retrying a meeting on
    /// its own; Retry on the meeting starts over.
    public static let maxAttempts = 3

    public static func shouldAutoRetry(attempts: Int) -> Bool { attempts < maxAttempts }

    /// The two tracks' names, as the segment files start (`mic-0001.caf`).
    public static let tracks = ["mic", "system"]

    /// One track's segment files among a folder's file names, in order.
    public static func segments(in files: [String], track: String) -> [String] {
        files.filter { name in
            guard name.hasPrefix("\(track)-"), name.hasSuffix(".caf") else { return false }
            let number = name.dropFirst(track.count + 1).dropLast(4)
            return !number.isEmpty && number.allSatisfy(\.isNumber)
        }.sorted()
    }

    public static func hasSegments(_ files: [String]) -> Bool {
        tracks.contains { !segments(in: files, track: $0).isEmpty }
    }

    /// A meeting whose audio folder holds segments but has no transcript was cut off
    /// (a quit or crash while recording or transcribing): finish it at launch.
    public static func isInterrupted(audioFiles: [String], hasTranscript: Bool) -> Bool {
        !hasTranscript && hasSegments(audioFiles)
    }
}

/// Stop when the call ends (Settings > General): a recording started while a call app was
/// using the microphone stops on its own once the call is over. The signal is the call app
/// letting go of the microphone (no call app process using audio input; Silvanus's own
/// process never counts), never how loud anything is: silence is normal.
///
/// After `quietAfter` seconds of no call input while capturing, a `countdown` starts ("Call
/// ended. Stopping in 10 seconds.", with Keep recording); at 0 the recording stops as if Stop
/// were pressed. Call input coming back cancels it. Keep recording turns it off for this
/// recording until a new call starts using the microphone. Quick Note and recordings with no
/// call at the start never stop on their own; nothing counts while paused or with audio lost.
/// The app's `Recorder` steps it ten times a second with what the call detector last saw.
public struct CallEndStop: Equatable, Sendable {
    public static let quietAfter: TimeInterval = 15
    public static let countdown: TimeInterval = 10

    public enum Phase: Equatable, Sendable {
        /// Quick Note, no call at the start, or already stopped: never.
        case off
        /// Watching the call; `quietSince` is when its input stopped, nil while it's heard.
        case watching(quietSince: Date?)
        /// "Call ended. Stopping in N seconds."; the recording stops at `stopAt`.
        case countingDown(stopAt: Date)
        /// Keep recording: off until a call app uses the microphone again.
        case kept
    }

    public enum Action: Equatable, Sendable {
        /// Stop the recording, as Stop does.
        case stop
    }

    public private(set) var phase: Phase
    public var quietAfter: TimeInterval
    public var countdown: TimeInterval

    public init(callAtStart: Bool, quickNote: Bool, quietAfter: TimeInterval = CallEndStop.quietAfter,
                countdown: TimeInterval = CallEndStop.countdown) {
        phase = callAtStart && !quickNote ? .watching(quietSince: nil) : .off
        self.quietAfter = quietAfter
        self.countdown = countdown
    }

    /// When the recording stops, while the countdown runs.
    public var stopAt: Date? {
        if case let .countingDown(stopAt) = phase { stopAt } else { nil }
    }

    /// The whole seconds left on the countdown at `date` (10 … 1), else nil.
    public func secondsLeft(at date: Date) -> Int? {
        guard let stopAt else { return nil }
        return max(1, Int(stopAt.timeIntervalSince(date).rounded(.up)))
    }

    /// One step. `callInput` is a call app using audio input now; `capturing` is false while
    /// paused or with audio lost; `enabled` is the setting. Returns `.stop` once, at 0.
    public mutating func step(at now: Date, callInput: Bool, capturing: Bool, enabled: Bool) -> Action? {
        switch phase {
        case .off:
            return nil
        case .kept:
            if callInput { phase = .watching(quietSince: nil) }
            return nil
        case let .watching(quietSince):
            guard enabled, capturing, !callInput else {
                phase = .watching(quietSince: nil)
                return nil
            }
            let since = quietSince ?? now
            phase = now.timeIntervalSince(since) >= quietAfter
                ? .countingDown(stopAt: now.addingTimeInterval(countdown))
                : .watching(quietSince: since)
            return nil
        case let .countingDown(stopAt):
            guard enabled, capturing, !callInput else {
                phase = .watching(quietSince: nil)
                return nil
            }
            guard now >= stopAt else { return nil }
            phase = .off
            return .stop
        }
    }

    /// Keep recording: cancels the countdown, and nothing counts until a new call starts.
    public mutating func keepRecording() {
        guard phase != .off else { return }
        phase = .kept
    }
}
