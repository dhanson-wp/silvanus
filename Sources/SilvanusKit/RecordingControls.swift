import CoreGraphics
import Foundation

/// The recording's captured clock, shared by both tracks' writers: Pause and an interruption
/// hold it, and the time they hold for isn't captured. Both writers drop what arrives while
/// it's held, so the two tracks skip the same stretch and stay aligned.
public struct CaptureTimeline: Equatable, Sendable {
    /// When the recording started.
    public let start: Date
    /// When the current hold began, while one lasts.
    public private(set) var heldSince: Date?
    /// Seconds held in holds that have ended.
    public private(set) var heldTotal: TimeInterval = 0

    public init(start: Date) {
        self.start = start
    }

    public var isHeld: Bool { heldSince != nil }

    /// Holds the clock at `date`. A second hold changes nothing.
    public mutating func hold(at date: Date) {
        guard heldSince == nil else { return }
        heldSince = max(date, start)
    }

    /// Lets the clock run again at `date`.
    public mutating func release(at date: Date) {
        guard let since = heldSince else { return }
        heldTotal += max(0, date.timeIntervalSince(since))
        heldSince = nil
    }

    /// Captured seconds at `date`: the time since the start, less every hold.
    public func captured(at date: Date) -> TimeInterval {
        let end = heldSince.map { min($0, date) } ?? date
        return max(0, end.timeIntervalSince(start) - heldTotal)
    }
}

/// The recording controls' five level bars: from the captured audio's RMS, in decibels, so
/// a quiet room reads flat and speech reads in the middle. Never a separate microphone.
public enum LevelMath {
    /// At or below this, the bars are flat (a quiet room is about −60 dBFS).
    public static let floorDB: Float = -50
    /// At or above this, the bars are full.
    public static let ceilingDB: Float = -12
    /// Levels under this count as quiet.
    public static let quiet: Float = 0.04

    /// A level from 0 to 1 for an RMS amplitude (0 to 1).
    public static func level(rms: Float) -> Float {
        guard rms > 0, rms.isFinite else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db - floorDB) / (ceilingDB - floorDB)))
    }

    /// Rises at once and falls by `release` each sample, so the bars don't flicker between
    /// words. Settles to 0 once it's quiet.
    public static func smooth(previous: Float, next: Float, release: Float = 0.55) -> Float {
        if next >= previous { return next }
        let fallen = previous * release + next * (1 - release)
        return fallen < quiet ? next : fallen
    }

    /// The meter's update rate is bounded: the recorder samples at most this often.
    public static let maxRate: Double = 15
}

/// Where the recording controls sit: bottom center above the Dock by default, wherever they
/// were dragged to on each display after that, and always inside a screen's visible frame
/// (below the menu bar, above the Dock).
public enum BarPlacement {
    public struct Screen: Equatable, Sendable {
        public var id: String
        /// The screen's visible frame, in screen points (origin bottom left).
        public var visible: CGRect

        public init(id: String, visible: CGRect) {
            self.id = id
            self.visible = visible
        }
    }

    /// Bottom center of `visible`, `inset` above its bottom (the Dock's top, when it's there).
    public static func defaultOrigin(size: CGSize, in visible: CGRect, inset: CGFloat) -> CGPoint {
        CGPoint(x: (visible.midX - size.width / 2).rounded(), y: visible.minY + inset)
    }

    /// Moves `origin` so a `size` rect from it, and `above` more points over it (the note
    /// shown above the bar while paused or interrupted), fit inside `visible`.
    public static func clamp(_ origin: CGPoint, size: CGSize, above: CGFloat = 0, in visible: CGRect) -> CGPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height - above)
        return CGPoint(x: min(max(origin.x, visible.minX), maxX), y: min(max(origin.y, visible.minY), maxY))
    }

    /// The screen showing most of a rect, else the one nearest its center.
    public static func screen(for rect: CGRect, in screens: [Screen]) -> Screen? {
        let best = screens.max { overlap($0.visible, rect) < overlap($1.visible, rect) }
        if let best, overlap(best.visible, rect) > 0 { return best }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screens.min { distance($0.visible, center) < distance($1.visible, center) }
    }

    /// Where to show: on the display the controls were last left on, at the spot saved
    /// there, while that display is connected; else on `preferred` (the main window's
    /// display) at its saved spot or the default. Always clamped to the screen.
    public static func resolve(saved: [String: CGPoint], last: String?, preferred: String?, screens: [Screen],
                               size: CGSize, inset: CGFloat) -> (screen: Screen, origin: CGPoint)? {
        if let last, let point = saved[last], let screen = screens.first(where: { $0.id == last }) {
            return (screen, clamp(point, size: size, in: screen.visible))
        }
        guard let screen = screens.first(where: { $0.id == preferred }) ?? screens.first else { return nil }
        let origin = saved[screen.id] ?? defaultOrigin(size: size, in: screen.visible, inset: inset)
        return (screen, clamp(origin, size: size, in: screen.visible))
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

/// The words on the recording controls and the "Meeting detected" prompt, kept here so the
/// tests and the views say the same thing (docs/GLOSSARY.md).
public enum RecordingWords {
    public static let recording = "Recording"
    public static let paused = "Paused"
    public static let audioLost = "Audio lost"
    /// Recording, with call audio gone: the microphone records on its own.
    public static let micOnly = "Mic only"
    public static let pausedNote = "Audio isn't being saved."
    /// Stop when the call ends: the note above the bar while the countdown runs, and its button.
    public static let callEnded = "Call ended"
    public static let keepRecording = "Keep recording"

    /// "Stopping in 10 seconds" … "Stopping in 1 second".
    public static func stoppingIn(_ seconds: Int) -> String {
        "Stopping in \(seconds) \(seconds == 1 ? "second" : "seconds")"
    }

    /// The countdown note: "Call ended. Stopping in 10 seconds."
    public static func callEndedNote(seconds: Int) -> String {
        "\(callEnded). \(stoppingIn(seconds))."
    }

    /// The state line's time suffix.
    public static func timeSuffix(paused: Bool, interrupted: Bool) -> String {
        interrupted ? "stopped" : paused ? "paused" : "elapsed"
    }

    /// The note above the bar while a required track is down.
    public static func lostNote(track: String) -> String {
        "\(track) stopped. Check your audio devices, then retry."
    }

    /// The prompt's lines: with a call app it can name, a meeting; with only microphone
    /// evidence, a plainer question that doesn't claim a meeting.
    public struct Prompt: Equatable, Sendable {
        public var title: String
        public var source: String
        public var question: String
        public var record: String
        public var notNow = "Not now"
    }

    public static func prompt(appName: String?) -> Prompt {
        if let appName, !appName.isEmpty {
            return Prompt(title: "Meeting detected", source: "Silvanus · \(appName) is using your microphone",
                          question: "Start recording this meeting?", record: "Record meeting")
        }
        return Prompt(title: "Microphone in use", source: "Silvanus", question: "Start a recording?",
                      record: "Start recording")
    }
}
