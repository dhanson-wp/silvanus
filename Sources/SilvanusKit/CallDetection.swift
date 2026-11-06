import Foundation

/// The apps a meeting happens in, by bundle id: call apps, plus browsers for calls on the
/// web (Meet, Zoom or Teams in a tab).
public enum CallApps {
    public static let bundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.tinyspeck.slackmacgap",
        "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
    ]

    /// The call apps among running apps' bundle ids.
    public static func running(in bundleIDs: some Sequence<String?>) -> Set<String> {
        Set(bundleIDs.compactMap { $0 }.filter { self.bundleIDs.contains($0) })
    }
}

/// Noticing a meeting start, with no audio and no UI: the app's `CallDetector` polls every
/// 2 seconds and steps this. A meeting starts when the microphone is in use while a call
/// app runs. It's announced once per call, never while Silvanus records, and the detector
/// re-arms only after the microphone has been free for 10 seconds (so a call that drops
/// the mic for a moment, or a recording stopped mid-call, isn't announced again).
public enum CallDetection {
    public enum State: Equatable, Sendable {
        /// Waiting for a meeting to start.
        case armed
        /// A meeting was seen (announced, or recorded); `quietFor` is how long the microphone
        /// has been free since.
        case inCall(quietFor: TimeInterval)
    }

    public enum Event: Equatable, Sendable {
        /// Show "Meeting detected".
        case meetingStarted
    }

    /// How often the app polls.
    public static let interval: TimeInterval = 2
    /// How long the microphone must be free before the next meeting can be announced.
    public static let rearmAfter: TimeInterval = 10

    /// One poll. `micInUse` is the input device running in any process (Silvanus's own
    /// recording included, which is why `recording` never announces); `callApps` the call
    /// apps running now.
    public static func step(previous: State, micInUse: Bool, callApps: Set<String>, recording: Bool,
                            interval: TimeInterval = CallDetection.interval) -> (state: State, event: Event?) {
        let busy = micInUse || recording
        switch previous {
        case .armed:
            guard busy, !callApps.isEmpty else { return (.armed, nil) }
            // A call that's already recording is used up: stopping mid-call announces nothing.
            return (.inCall(quietFor: 0), recording ? nil : .meetingStarted)
        case let .inCall(quiet):
            if busy { return (.inCall(quietFor: 0), nil) }
            let next = quiet + interval
            return next >= rearmAfter ? (.armed, nil) : (.inCall(quietFor: next), nil)
        }
    }
}

/// When the call-audio warning ("Nobody on the call is audible yet…") may show. Quick Note
/// is a voice note, never a call; and a recording with no call app running at its start,
/// and none now, has no call to hear. The microphone-silence warning shows for every
/// recording.
public enum CallAudioWarning {
    public static let text = "Nobody on the call is audible yet. Check System Audio access in Settings."

    public static func applies(quickNote: Bool, callAppAtStart: Bool, callAppNow: Bool) -> Bool {
        !quickNote && (callAppAtStart || callAppNow)
    }

    /// The warning to show now, or nil: call audio silent for `silentFor` seconds, past
    /// `threshold`, in a recording the warning applies to.
    public static func warning(quickNote: Bool, callAppAtStart: Bool, callAppNow: Bool,
                               silentFor: TimeInterval, threshold: TimeInterval) -> String? {
        guard applies(quickNote: quickNote, callAppAtStart: callAppAtStart, callAppNow: callAppNow),
              silentFor > threshold else { return nil }
        return text
    }
}
