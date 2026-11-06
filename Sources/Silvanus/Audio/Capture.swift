import AVFoundation
import CoreAudio
import Foundation

enum CaptureError: LocalizedError {
    case microphoneDenied
    case noInput
    case status(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off for Silvanus."
        case .noInput: "There's no microphone input right now."
        case let .status(step, code): "Unable to \(step) (Core Audio error \(code))."
        }
    }
}

/// What MicCapture needs from the audio engine: the live one is AVAudioEngine's input
/// node (`LiveMicEngine`); the self-test uses a fake that opens no device.
nonisolated protocol MicEngine: AnyObject, Sendable {
    /// What configuration-change notifications are posted for.
    var notificationObject: AnyObject { get }
    /// The input's format now, or nil when there's no usable input.
    func inputFormat() -> AVAudioFormat?
    func installTap(format: AVAudioFormat, block: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    func removeTap()
    func start() throws
    func stop()
}

nonisolated final class LiveMicEngine: MicEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()

    var notificationObject: AnyObject { engine }

    func inputFormat() -> AVAudioFormat? { engine.inputNode.outputFormat(forBus: 0) }

    func installTap(format: AVAudioFormat, block: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in block(buffer) }
    }

    func removeTap() { engine.inputNode.removeTap(onBus: 0) }

    func start() throws {
        engine.prepare()
        try engine.start()
    }

    func stop() { engine.stop() }
}

/// My side: the microphone through AVAudioEngine. When the input changes mid-call (a
/// headset plugged in or out, a Bluetooth profile switch, another default device, a new
/// sample rate), the engine stops and posts a configuration change: the tap is put back on
/// the new input and the engine restarts, and the track goes on in a new segment file.
///
/// Starts, restarts, and stop run one at a time on one queue, so a change that lands
/// during Stop never restarts the engine after it, and the tap is never installed twice.
/// An input with no usable format (mid Bluetooth switch) is retried after a short delay
/// instead of handed to installTap, which would raise.
nonisolated final class MicCapture: @unchecked Sendable {
    private let engine: MicEngine
    private let queue = DispatchQueue(label: "silvanus.mic")
    private var observer: NSObjectProtocol?
    private var writer: SegmentWriter?
    // Touched only on `queue`.
    private var stopped = false
    private var tapInstalled = false
    /// For the log and the checks: restarts after a configuration change.
    private(set) var restarts = 0
    /// How long to wait before trying an input again, and how many tries a change gets.
    var retryDelay: TimeInterval = 0.5
    var maxTries = 4

    init(engine: MicEngine = LiveMicEngine()) {
        self.engine = engine
    }

    func start(into writer: SegmentWriter) throws {
        try queue.sync {
            self.writer = writer
            stopped = false
            try run(into: writer)
        }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine.notificationObject,
                                                          queue: nil) { [weak self] _ in
            self?.configurationChanged()
        }
    }

    /// On `queue`: one tap on the input as it is now, then start. Throws, without touching
    /// installTap, when the input has no usable format.
    private func run(into writer: SegmentWriter) throws {
        guard !stopped else { return }
        guard let format = engine.inputFormat(), format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInput
        }
        if tapInstalled {
            engine.removeTap()
            tapInstalled = false
        }
        engine.installTap(format: format) { buffer in writer.append(buffer) }
        tapInstalled = true
        do {
            try engine.start()
        } catch {
            engine.removeTap()
            tapInstalled = false
            throw error
        }
    }

    /// The input changed. Called on any thread; the restart waits its turn on `queue`.
    func configurationChanged() {
        queue.async { [self] in restart(attempt: 1) }
    }

    /// On `queue`: a new segment, then listen again, retrying a few times while the input
    /// settles. Gives up with a failure the recorder shows. Never runs after stop.
    private func restart(attempt: Int) {
        guard !stopped, let writer else { return }
        if attempt == 1 {
            restarts += 1
            if tapInstalled {
                engine.removeTap()
                tapInstalled = false
            }
            engine.stop()
            writer.breakSegment()
            print("RECORDER the microphone changed; restarting (\(restarts))")
        }
        do {
            try run(into: writer)
        } catch {
            if attempt < maxTries {
                queue.asyncAfter(deadline: .now() + retryDelay) { [self] in restart(attempt: attempt + 1) }
            } else {
                writer.recordFailure("Couldn't restart the microphone: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        queue.sync {
            stopped = true
            if tapInstalled {
                engine.removeTap()
                tapInstalled = false
            }
            engine.stop()
        }
    }

    /// For the checks: waits for queued restarts to finish.
    func settle() { queue.sync {} }
}

/// Their side: everything the Mac plays, through a Core Audio process tap
/// (macOS 14.2+), excluding Silvanus's own sounds. No screen recording
/// indicator. macOS asks for "System Audio Recording" the first time.
/// Approach adapted from OpenOats (MIT), Audio/SystemAudioCapture.swift.
nonisolated final class SystemCapture: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "silvanus.system-audio")

    func start(into writer: SegmentWriter) throws {
        let own = Self.ownProcessObject()
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        description.name = "Silvanus call audio"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else { throw CaptureError.status("start capturing call audio", status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Silvanus call audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw CaptureError.status("create the call audio device", status) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        for _ in 0..<20 {
            status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
            if status == noErr { break }
            usleep(100_000)
        }
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            stop(); throw CaptureError.status("read the call audio format", status)
        }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            let frames = AVAudioFrameCount(input.pointee.mBuffers.mDataByteSize / max(1, format.streamDescription.pointee.mBytesPerFrame))
            guard frames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            buffer.frameLength = frames
            writer.append(buffer)
        }
        guard status == noErr, let procID else { stop(); throw CaptureError.status("listen to call audio", status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw CaptureError.status("start the call audio device", status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }
}
