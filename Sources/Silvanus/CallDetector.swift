import AppKit
import CoreAudio
import Foundation
import SilvanusKit

/// Notices a meeting starting: every 2 seconds (on a timer, never per audio buffer) it
/// asks Core Audio whether the default input device is running in any process, and which
/// call apps run, then steps `CallDetection`. A start while Silvanus isn't recording calls
/// `meetingStarted` (the "Meeting detected" prompt), when Settings > General > Prompt when a
/// meeting starts is on.
///
/// Reading kAudioDevicePropertyDeviceIsRunningSomewhere is a property read: it never opens
/// the microphone and never asks for permission. While Silvanus records, the device runs in
/// our own process; `CallDetection` ignores that by never announcing while recording.
@MainActor
final class CallDetector {
    /// What the detector reads each poll. The self-test fakes it.
    struct Probe {
        var micInUseElsewhere: @MainActor () -> Bool
        var runningCallApps: @MainActor () -> Set<String>

        static let live = Probe(micInUseElsewhere: CallDetector.defaultInputIsRunning,
                                runningCallApps: CallDetector.liveCallApps)
    }

    var probe: Probe
    /// True while Silvanus records.
    var isRecording: () -> Bool
    /// False turns the prompt off (Settings > General > Prompt when a meeting starts).
    var isEnabled: () -> Bool
    /// A meeting started while Silvanus wasn't recording.
    var meetingStarted: () -> Void = {}
    /// After each poll: whether any call app runs. The recorder's call-audio warning reads it.
    var callAppsChanged: (Bool) -> Void = { _ in }

    private(set) var state: CallDetection.State = .armed
    /// The call apps the last poll saw.
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
        let apps = probe.runningCallApps()
        callApps = apps
        callAppsChanged(!apps.isEmpty)
        let recording = isRecording()
        // While recording the device runs in our own process: no need to ask.
        let mic = recording ? true : probe.micInUseElsewhere()
        let (next, event) = CallDetection.step(previous: state, micInUse: mic, callApps: apps, recording: recording)
        state = next
        if event == .meetingStarted, isEnabled() {
            meetingStarted()
        }
    }

    // MARK: - Live probe

    /// The call apps running now, by bundle id.
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
