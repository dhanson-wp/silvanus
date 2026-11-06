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

    /// The call apps among running apps' bundle ids. Only the fallback uses it: a running
    /// app isn't a call.
    public static func running(in bundleIDs: some Sequence<String?>) -> Set<String> {
        Set(bundleIDs.compactMap { $0 }.filter { self.bundleIDs.contains($0) })
    }

    /// Bundle id roots, each with the call app it stands for. A process matches a root when
    /// its id is the root or starts with the root and a dot, so browser and call-app helpers
    /// (com.google.Chrome.helper, us.zoom.CptHost) count as their app.
    public static let roots: [(root: String, app: String)] = [
        ("us.zoom", "us.zoom.xos"),
        ("com.microsoft.teams2", "com.microsoft.teams2"),
        ("com.microsoft.teams", "com.microsoft.teams"),
        ("com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap"),
        ("com.apple.FaceTime", "com.apple.FaceTime"),
        // FaceTime's calls run their audio in this daemon.
        ("com.apple.avconferenced", "com.apple.FaceTime"),
        ("com.cisco.webexmeetingsapp", "com.cisco.webexmeetingsapp"),
        ("com.webex.meetingmanager", "com.cisco.webexmeetingsapp"),
        ("com.google.Chrome", "com.google.Chrome"),
        ("company.thebrowser", "company.thebrowser.Browser"),
        ("com.apple.Safari", "com.apple.Safari"),
        ("org.mozilla", "org.mozilla.firefox"),
        ("com.microsoft.edgemac", "com.microsoft.edgemac"),
    ]

    static let safari = "com.apple.Safari"

    /// The call app a process using audio input belongs to, or nil. Silvanus's own process
    /// never counts. WebKit's processes (com.apple.WebKit.*) serve every app that shows a web
    /// page, so they count only when the app responsible for them is Safari.
    public static func app(for process: InputProcess, ownPID: Int32) -> String? {
        guard process.pid != ownPID, let id = process.bundleID, !id.isEmpty else { return nil }
        if id.hasPrefix("com.apple.WebKit.") {
            let safari = process.responsibleBundleID.map { $0 == Self.safari || $0.hasPrefix(Self.safari + ".") } ?? false
                || process.path?.contains("/Safari.app/") == true
            return safari ? Self.safari : nil
        }
        return roots.first { id == $0.root || id.hasPrefix($0.root + ".") }?.app
    }

    /// The call apps whose processes are using audio input now.
    public static func usingInput(_ processes: [InputProcess], ownPID: Int32) -> Set<String> {
        Set(processes.filter(\.isRunningInput).compactMap { app(for: $0, ownPID: ownPID) })
    }

    /// The call apps whose processes are playing audio now (a muted listener still hears the call).
    public static func usingOutput(_ processes: [InputProcess], ownPID: Int32) -> Set<String> {
        Set(processes.filter(\.isRunningOutput).compactMap { app(for: $0, ownPID: ownPID) })
    }

    /// Both, from one read of the process list.
    public static func audio(_ processes: [InputProcess], ownPID: Int32) -> CallAppAudio {
        CallAppAudio(input: usingInput(processes, ownPID: ownPID), output: usingOutput(processes, ownPID: ownPID))
    }
}

/// The call apps using audio input (the microphone: a call starting, and the prompt) and
/// output (the call playing, so a muted listener is still in the call), from one read.
public struct CallAppAudio: Equatable, Sendable {
    public var input: Set<String>
    public var output: Set<String>

    public init(input: Set<String> = [], output: Set<String> = []) {
        self.input = input
        self.output = output
    }
}

/// A process Core Audio reports as using audio input or output, with what's known about it.
public struct InputProcess: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    /// The bundle id of the app responsible for the process (Safari for its WebKit processes).
    public var responsibleBundleID: String?
    /// The process's executable path.
    public var path: String?
    /// kAudioProcessPropertyIsRunningInput and kAudioProcessPropertyIsRunningOutput.
    public var isRunningInput: Bool
    public var isRunningOutput: Bool

    public init(pid: Int32, bundleID: String?, responsibleBundleID: String? = nil, path: String? = nil,
                isRunningInput: Bool = true, isRunningOutput: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.responsibleBundleID = responsibleBundleID
        self.path = path
        self.isRunningInput = isRunningInput
        self.isRunningOutput = isRunningOutput
    }
}

/// Noticing a meeting start, with no audio and no UI: the app's `CallDetector` polls every
/// 2 seconds and steps this. A meeting starts when a call app's process is using audio
/// input (`callApps` is those apps). It's announced once per call, never while Silvanus records, and the detector
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
