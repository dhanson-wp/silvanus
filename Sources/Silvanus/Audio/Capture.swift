import AVFoundation
import CoreAudio
import Foundation

enum CaptureError: LocalizedError {
    case microphoneDenied
    case status(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off for Silvanus."
        case let .status(step, code): "Unable to \(step) (Core Audio error \(code))."
        }
    }
}

/// My side: the microphone through AVAudioEngine.
nonisolated final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()

    func start(into writer: SegmentWriter) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
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
