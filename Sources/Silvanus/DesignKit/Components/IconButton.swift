import SwiftUI

/// A 28 × 28 icon button, from KIT.md "Sidebar header row" (the sidebar header's four
/// buttons), "Canvas header" (More), and "Record button and quick-note mic" (the mic).
///
/// | State | Fill | Icon |
/// | rest | none | textSecondary |
/// | hover | selection (controlHover on the canvas) | text |
/// | pressed | selection at 80% (controlHover on the canvas) | text |
/// | focused | 2 pt focus ring, corner 7 | text |
/// | disabled | none | textSecondary at 40% |
/// | recording (the mic) | controlHover | recordingText |
///
/// `title` is the accessibility label; `help` the tooltip (what it does, then its shortcut).
/// A nil action draws the button disabled: the feature hasn't landed, but its place has.
/// Parts on the canvas set `.environment(\.onCanvas, true)` so hover shows there.
struct IconButton: View {
    let icon: KitIcon
    let title: String
    var help: String?
    var isRecording = false
    var action: (() -> Void)?

    init(_ icon: KitIcon, _ title: String, help: String? = nil, isRecording: Bool = false,
         action: (() -> Void)?) {
        self.icon = icon
        self.title = title
        self.help = help
        self.isRecording = isRecording
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            KitIconView(icon)
        }
        .buttonStyle(IconButtonStyle(isRecording: isRecording))
        .disabled(action == nil)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// The icon button's look and states (see `IconButton`). The gallery forces a state with
/// `forcedPartState`.
struct IconButtonStyle: ButtonStyle {
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
        @Environment(\.onCanvas) private var onCanvas
        @State private var hovering = false

        private var state: PartState {
            forced ?? (!isEnabled ? .disabled : configuration.isPressed ? .pressed
                : hovering ? .hover : isFocused ? .focused : .rest)
        }

        private var hoverFill: Color { onCanvas ? Ink.controlHover : Ink.selection }

        private var fill: Color {
            switch state {
            case .hover: hoverFill
            case .pressed: hoverFill.opacity(0.8)
            case .disabled: .clear
            default: isRecording ? hoverFill : .clear
            }
        }

        private var ink: Color {
            if isRecording && state != .disabled { return Ink.recordingText }
            return [.hover, .pressed, .focused].contains(state) ? Ink.text : Ink.textSecondary
        }

        private var ringed: Bool { state == .focused || (isFocused && state != .disabled) }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.iconButtonCorner)
            configuration.label
                .foregroundStyle(ink)
                .opacity(state == .disabled ? 0.4 : 1)
                .frame(width: Metric.iconButton, height: Metric.iconButton)
                .background(fill, in: shape)
                .overlay {
                    if ringed { shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing) }
                }
                .contentShape(shape)
                .focusEffectDisabled()
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
        }
    }
}

private struct OnCanvasKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for parts that sit on `Ink.canvas`: their hover and pressed fills use
    /// `Ink.controlHover`, since `Ink.selection` matches the canvas.
    var onCanvas: Bool {
        get { self[OnCanvasKey.self] }
        set { self[OnCanvasKey.self] = newValue }
    }
}
