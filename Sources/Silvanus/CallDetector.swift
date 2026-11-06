import AppKit
import CoreAudio
import Foundation
import SilvanusKit

/// Notices a meeting starting: every 2 seconds (on a timer, never per audio buffer) it asks
/// Core Audio which processes are using audio input (kAudioHardwarePropertyProcessObjectList,
/// kAudioProcessPropertyIsRunningInput) and keeps the call apps among them
/// (`CallApps.usingInput`; our own process never counts), then steps `CallDetection`. A start
/// while Silvanus isn't recording calls `meetingStarted` (the "Meeting detected" prompt), when
/// Settings > General > Prompt when a meeting starts is on.
///
/// When the process list can't be read, it falls back to the default input device running
/// anywhere (kAudioDevicePropertyDeviceIsRunningSomewhere) while a call app runs.
///
/// These are property reads: they never open the microphone and never ask for permission.
@MainActor
final class CallDetector {
    /// What the detector reads each poll. The self-test fakes it.
    struct Probe {
        /// The call apps using audio input now, or nil when the process list can't be read.
        var callAppsUsingInput: @MainActor () -> Set<String>?
        /// The fallback: the default input device running in any process...
        var micInUseElsewhere: @MainActor () -> Bool
        /// ...while one of these call apps runs.
        var runningCallApps: @MainActor () -> Set<String>

        static let live = Probe(callAppsUsingInput: CallDetector.liveCallAppsUsingInput,
                                micInUseElsewhere: CallDetector.defaultInputIsRunning,
                                runningCallApps: CallDetector.liveCallApps)

        /// The call apps in a call now, and whether the microphone counts as in use.
        /// `recording` says our own process runs the device (it matters to the fallback only).
        func read(recording: Bool) -> (apps: Set<String>, micInUse: Bool) {
            let now = readDetail(recording: recording)
            return (now.apps, now.micInUse)
        }

        /// As `read`, and whether the apps are known to be the ones using the microphone
        /// (the process list), not just running beside it (the fallback).
        func readDetail(recording: Bool) -> (apps: Set<String>, micInUse: Bool, reliable: Bool) {
            if let apps = callAppsUsingInput() { return (apps, !apps.isEmpty, true) }
            return (runningCallApps(), recording || micInUseElsewhere(), false)
        }

        /// True when a call app is in a call: using input, or in the fallback, running while
        /// the input device runs.
        func callInProgress(recording: Bool) -> Bool {
            let now = read(recording: recording)
            return now.micInUse && !now.apps.isEmpty
        }
    }

    var probe: Probe
    /// True while Silvanus records.
    var isRecording: () -> Bool
    /// False turns the prompt off (Settings > General > Prompt when a meeting starts).
    var isEnabled: () -> Bool
    /// A meeting started while Silvanus wasn't recording, with the app's name when
    /// detection can tell which one is using the microphone.
    var meetingStarted: (String?) -> Void = { _ in }
    /// The call ended (the microphone was free long enough to re-arm).
    var meetingEnded: () -> Void = {}
    /// A call app's name, by bundle id, read at runtime. The self-test fakes it.
    var displayName: @MainActor (String) -> String? = CallDetector.liveDisplayName
    /// After each poll: whether a call app is in a call. The recorder's call-audio warning
    /// reads it.
    var callAppsChanged: (Bool) -> Void = { _ in }

    private(set) var state: CallDetection.State = .armed
    /// The call apps in a call at the last poll.
    private(set) var callApps: Set<String> = []
    /// For the checks: how many polls ran.
    private(set) var polls = 0
    private var timer: Timer?

    init(probe: Probe = .live, isRecording: @escaping () -> Bool, isEnabled: @escaping () -> Bool) {
        self.probe = probe
        self.isRecording = isRecording
        self.isEnabled = isEnabled
    }

    /// Starts polling every 2 seconds. A second start does nothing.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: CallDetection.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One poll: read the probe, step the state, and announce a start.
    func poll() {
        polls += 1
        let recording = isRecording()
        let (apps, mic, reliable) = probe.readDetail(recording: recording)
        callApps = mic ? apps : []
        callAppsChanged(mic && !apps.isEmpty)
        let (next, event) = CallDetection.step(previous: state, micInUse: mic, callApps: apps, recording: recording)
        let ended = state != .armed && next == .armed
        state = next
        if event == .meetingStarted, isEnabled() {
            // Name the app only when it's the one known to use the microphone, and only one.
            let name = reliable && apps.count == 1 ? apps.first.flatMap(displayName) : nil
            meetingStarted(name)
        }
        if ended { meetingEnded() }
    }

    /// The app's name as the Mac shows it ("FaceTime"), from the running app or its bundle.
    static func liveDisplayName(_ bundleID: String) -> String? {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName,
           !name.isEmpty {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    // MARK: - Live probe

    /// The call apps whose processes are using audio input, or nil when Core Audio's process
    /// list can't be read. Silvanus's own process never counts.
    static func liveCallAppsUsingInput() -> Set<String>? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var objects = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        var processes: [InputProcess] = []
        for object in objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
            guard uint32(object, kAudioProcessPropertyIsRunningInput) == 1,
                  let pid = int32(object, kAudioProcessPropertyPID) else { continue }
            let bundleID = string(object, kAudioProcessPropertyBundleID)
            var process = InputProcess(pid: pid, bundleID: bundleID)
            // Only WebKit's processes need their responsible app (Safari or not).
            if bundleID?.hasPrefix("com.apple.WebKit.") == true {
                process.responsibleBundleID = responsibleBundleID(for: pid)
                process.path = path(for: pid)
            }
            processes.append(process)
        }
        return CallApps.usingInput(processes, ownPID: getpid())
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func int32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var address = address(selector)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    /// libsystem's responsibility_get_pid_responsible_for_pid, when it's there: the app a
    /// helper or XPC process works for.
    private static let responsiblePID: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()

    private static func responsibleBundleID(for pid: pid_t) -> String? {
        guard let responsiblePID else { return nil }
        let owner = responsiblePID(pid)
        guard owner > 0, owner != pid else { return nil }
        return NSRunningApplication(processIdentifier: owner)?.bundleIdentifier
    }

    private static func path(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The call apps running now, by bundle id (the fallback only).
    static func liveCallApps() -> Set<String> {
        CallApps.running(in: NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
    }

    /// True when the default input device is running in any process. A property read only:
    /// it opens nothing and needs no permission.
    nonisolated static func defaultInputIsRunning() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
