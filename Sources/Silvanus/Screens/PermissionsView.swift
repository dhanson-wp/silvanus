import AppKit
import SwiftUI

/// The sheet the first Start Recording or Quick Note opens when Microphone access or System
/// audio access is missing: why each is needed, its state, and a button that asks for it or
/// opens the right System Settings pane. Nothing here asks on its own, and it never opens at
/// launch. Start Recording (the default button) starts once the microphone is allowed.
struct PermissionsView: View {
    let request: RecordRequest
    let start: () -> Void
    let cancel: () -> Void

    @State private var mic = Permissions.microphone
    @State private var systemAsked = Permissions.systemAudioAsked
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Silvanus needs two permissions to record")
                .kitType(.heading)
                .foregroundStyle(Ink.text)
            row(title: "Microphone access",
                reason: "So your side of the call is in the transcript.",
                status: mic == .allowed ? "Allowed" : mic == .denied ? "Off in System Settings" : "Not asked yet",
                done: mic == .allowed) {
                switch mic {
                case .allowed: EmptyView()
                case .denied:
                    Button("Open System Settings…") { Permissions.openSettings("Privacy_Microphone") }
                        .buttonStyle(KitButtonStyle())
                case .notAsked:
                    Button("Allow Microphone Access") {
                        asking = true
                        Task {
                            mic = await Permissions.requestMicrophone()
                            asking = false
                        }
                    }
                    .buttonStyle(KitButtonStyle())
                    .disabled(asking)
                }
            }
            row(title: "System audio access",
                reason: "So the other people on the call are in the transcript.",
                status: systemAsked ? "Asked. If call audio stays silent, turn it on in System Settings." : "Not asked yet",
                done: systemAsked) {
                if systemAsked {
                    Button("Open System Settings…") { Permissions.openSettings("Privacy_AudioCapture") }
                        .buttonStyle(KitButtonStyle())
                } else {
                    Button("Allow System Audio Access") {
                        asking = true
                        Task {
                            await Permissions.requestSystemAudio()
                            systemAsked = Permissions.systemAudioAsked
                            asking = false
                        }
                    }
                    .buttonStyle(KitButtonStyle())
                    .disabled(asking)
                }
            }
            if mic == .denied {
                Text("Recording can't start without microphone access.")
                    .kitType(.label)
                    .foregroundStyle(Ink.textSecondary)
            }
            HStack(spacing: Space.md) {
                Spacer()
                Button("Not Now", action: cancel)
                    .buttonStyle(KitButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(request == .quickNote ? "Quick Note" : "Start Recording", action: start)
                    .buttonStyle(KitButtonStyle(isSelected: mic == .allowed))
                    .keyboardShortcut(.defaultAction)
                    .disabled(mic != .allowed || asking)
            }
        }
        .padding(Space.xxl)
        .frame(width: Self.width)
        .background(Ink.canvas)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            mic = Permissions.microphone
            systemAsked = Permissions.systemAudioAsked
        }
        .gridArea("permissions", inset: Space.xxl)
    }

    static let width: CGFloat = 560

    private func row(title: String, reason: String, status: String, done: Bool,
                     @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Ink.accentText : Ink.textSecondary)
                .kitType(.subheading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .kitType(.settingTitle)
                    .foregroundStyle(Ink.text)
                Text(reason)
                    .kitType(.label)
                    .foregroundStyle(Ink.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status)
                    .kitType(.label)
                    .foregroundStyle(done ? Ink.text : Ink.textSecondary)
                    .accessibilityLabel("\(title): \(status)")
            }
            Spacer(minLength: Space.md)
            action().fixedSize()
        }
    }
}
