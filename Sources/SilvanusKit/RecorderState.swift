import Foundation

/// Where the recorder is. One recording at a time; a finished recording's transcription
/// can go on behind the next one (a back-to-back call).
public enum RecorderPhase: Equatable, Sendable {
    case idle
    case starting
    case recording(since: Date)
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
    /// Stop.
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

    public var isRecording: Bool {
        if case .recording = phase { true } else { false }
    }

    /// When the recording started, while it records.
    public var since: Date? {
        if case let .recording(since) = phase { since } else { nil }
    }

    /// Applies an event; false when it doesn't fit the phase (the phase stays).
    @discardableResult
    public mutating func apply(_ event: RecorderEvent) -> Bool {
        let next: RecorderPhase? = switch (phase, event) {
        // Start while recording (or getting there, or wrapping up) is refused.
        case (.idle, .start), (.transcribing, .start), (.failed, .start): .starting
        case let (.starting, .started(date)): .recording(since: date)
        case (.recording, .stop): .stopping
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

    /// The floating recording pill shows while a meeting records (or is stopping) and the
    /// main window isn't the key window.
    public func showsPill(mainWindowIsKey: Bool) -> Bool {
        guard !mainWindowIsKey else { return false }
        return switch phase {
        case .recording, .stopping: true
        default: false
        }
    }
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
