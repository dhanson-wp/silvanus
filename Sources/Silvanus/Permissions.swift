import AVFoundation
import AppKit

/// The two permissions Silvanus needs: the microphone (my side) and System
/// Audio Recording (their side). The screen that asks for them comes with the
/// recording controls.
enum Permissions {
    enum State: Equatable { case notAsked, allowed, denied }

    static var microphone: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    static func requestMicrophone() async -> State {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return microphone
    }

    static let systemAudioAskedKey = "permissions.systemAudioAsked"

    /// macOS has no public way to read the System Audio Recording permission.
    /// Silvanus remembers that it asked; the recording bar warns if call audio stays silent.
    static var systemAudioAsked: Bool { AppDefaults.shared.bool(forKey: systemAudioAskedKey) }
    static func markSystemAudioAsked() { AppDefaults.shared.set(true, forKey: systemAudioAskedKey) }

    /// Starts call-audio capture for a moment, which makes macOS show its prompt.
    static func requestSystemAudio() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "silvanus-permission-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let capture = SystemCapture()
        try? capture.start(into: SegmentWriter(directory: dir, name: "probe", recordingStart: .now))
        try? await Task.sleep(for: .seconds(1))
        capture.stop()
        try? FileManager.default.removeItem(at: dir)
        markSystemAudioAsked()
    }

    static var needsSetup: Bool { microphone != .allowed || !systemAudioAsked }

    static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
