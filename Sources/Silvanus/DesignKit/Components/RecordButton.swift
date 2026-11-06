import SwiftUI

/// KIT.md "Record button and quick-note mic": the record button's measures.
extension Metric {
    /// Before the icon, between the icon and the label, and after the label.
    static let recordLeading: CGFloat = 7
    static let recordIconGap: CGFloat = 7.5
    static let recordTrailing: CGFloat = 10.5
}

/// The labeled Record button in the canvas header, from KIT.md "Record button and
/// quick-note mic". It reads "Start Recording" and turns into "Stop" on the recording fill
/// while a meeting records. It only calls `action`; what that does belongs to the caller
/// (File > Start Recording, ⇧⌘R, does the same). A nil action draws it disabled, with a
/// tooltip that says recording isn't available yet.
struct RecordButton: View {
    var isRecording = false
    var action: (() -> Void)?

    /// The tooltip on a recording control while recording isn't wired in.
    static let unavailable = "Recording isn't available yet"

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: Metric.recordIconGap) {
                KitIconView(isRecording ? .stop : .record)
                Text(isRecording ? "Stop" : "Start Recording")
                    .kitType(.button)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(RecordButtonStyle(isRecording: isRecording))
        .disabled(action == nil)
        .help(action == nil ? Self.unavailable
            : isRecording ? "Stop recording; transcription starts (⇧⌘R)" : "Record this meeting (⇧⌘R)")
    }
}

/// The Record button's look: 28 tall, corner 6, padding 7 before the icon and 10.5 after
/// the label.
///
/// | State | Fill | Border | Label and icon |
/// | rest | canvas | 1 pt divider | text |
/// | hover | controlHover | 1 pt divider | text |
/// | pressed | controlHover at 80% | 1 pt divider | text |
/// | recording | recording | none | onRecording |
/// | focused | as rest | 2 pt focus ring | text |
/// | disabled | canvas | divider at 40% | text at 40% |
///
/// The gallery forces a state with `forcedPartState`.
struct RecordButtonStyle: ButtonStyle {
    var isRecording = false

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, isRecording: isRecording)
    }

    private struct Content: View {
        let configuration: Configuration
        let isRecording: Bool
        @Environment(\.forcedPartState) private var forced
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : configuration.isPressed ? .pressed
                : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var fill: Color {
            if isRecording && state != .disabled {
                return state == .pressed ? Ink.recording.opacity(0.8) : Ink.recording
            }
            return switch state {
            case .hover: Ink.controlHover
            case .pressed: Ink.controlHover.opacity(0.8)
            default: Ink.canvas
            }
        }

        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.buttonCorner)
            configuration.label
                .foregroundStyle(isRecording ? Ink.onRecording : Ink.text)
                .opacity(state == .disabled ? 0.4 : 1)
                .padding(.leading, Metric.recordLeading)
                .padding(.trailing, Metric.recordTrailing)
                .frame(height: Metric.controlHeight)
                .background(fill, in: shape)
                .overlay {
                    if ringed {
                        shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing)
                    } else if !isRecording {
                        shape.strokeBorder(Ink.divider.opacity(state == .disabled ? 0.4 : 1), lineWidth: Metric.hairline)
                    }
                }
                .contentShape(shape)
                .focusEffectDisabled()
                .animation(Motion.select, value: isRecording)
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
        }
    }
}

/// The Quick Note mic: an `IconButton` with the `mic` icon, 8 before the Record button. It
/// starts a new meeting that records right away (File > Quick Note, ⌥⌘N). While a meeting
/// records, its icon turns `recordingText` on a controlHover fill. A nil action draws it
/// disabled, with a tooltip that says recording isn't available yet.
struct QuickNoteButton: View {
    var isRecording = false
    var action: (() -> Void)?

    var body: some View {
        IconButton(.quickNoteMic, "Quick Note",
                   help: action == nil ? RecordButton.unavailable : "Start a new meeting and record right away (⌥⌘N)",
                   isRecording: isRecording, action: action)
            .environment(\.onCanvas, true)
    }
}
