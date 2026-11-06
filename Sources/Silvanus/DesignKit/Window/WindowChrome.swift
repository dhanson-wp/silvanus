import AppKit
import SwiftUI

extension View {
    /// The kit's window chrome (`WindowChrome`) and its minimum size, 720 × 480
    /// (`Metric.windowMinimum`). Use it on the main window's root view.
    func windowChrome() -> some View {
        modifier(WindowChromeModifier())
    }
}

/// SwiftUI adds the hidden title bar's height to a min frame's height, so the frame asks for
/// that much less and the whole window's minimum comes out at `Metric.windowMinimum`.
private struct WindowChromeModifier: ViewModifier {
    @State private var titlebarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(minWidth: Metric.windowMinimum.width,
                   minHeight: Metric.windowMinimum.height - titlebarHeight)
            .background(WindowChrome { titlebarHeight = $0 })
    }
}

/// The window's own chrome, from design/KIT.md "Window": no title bar, the content runs
/// under where it was, and the traffic lights stay native but sit at the kit's centers,
/// (19, 23), (42, 23), and (65, 23), vertically centered in the 46 pt header.
///
/// SwiftUI can't move the traffic lights, so this zero-size view reaches the NSWindow.
/// AppKit puts them back on resize, full screen, and theme changes, so it moves them again
/// each time their frames change. Put it in a `.background` of the window's root view; the
/// scene uses `.windowStyle(.hiddenTitleBar)`.
struct WindowChrome: NSViewRepresentable {
    /// Called with the hidden title bar's height once the window has laid it out.
    var titlebarHeight: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.titlebarHeight = titlebarHeight
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.titlebarHeight = titlebarHeight
    }

    final class ChromeView: NSView {
        var titlebarHeight: (CGFloat) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Leaving a window (or closing it) drops the old observers.
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // The canvas and sidebar fill the window; a title bar separator would draw a line
            // through the header.
            window.titlebarSeparatorStyle = .none
            let center = NotificationCenter.default
            for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeButtons() }
                })
            }
            for button in Self.buttons(of: window) {
                button.postsFrameChangedNotifications = true
                observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: button,
                                                    queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeButtons() }
                })
            }
            placeButtons()
            // AppKit lays the title bar out once more after the window first shows.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                placeButtons()
                titlebarHeight(window.frame.height - window.contentLayoutRect.height)
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            placeButtons()
        }

        /// Moves each button so its center lands on the kit's point, measured from the
        /// window's top left. Leaves full screen alone: there the buttons live in the menu bar.
        private func placeButtons() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let height = window.frame.height
            for (index, button) in Self.buttons(of: window).enumerated() {
                guard let container = button.superview else { continue }
                let target = NSPoint(x: Metric.trafficLightFirst.x + CGFloat(index) * Metric.trafficLightPitch,
                                     y: height - Metric.trafficLightFirst.y)
                let inContainer = container.convert(target, from: nil)
                let origin = NSPoint(x: (inContainer.x - button.frame.width / 2).rounded(),
                                     y: (inContainer.y - button.frame.height / 2).rounded())
                // Setting the same origin posts no change, so this never loops.
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        private static func buttons(of window: NSWindow) -> [NSButton] {
            [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        }
    }
}

/// The hide sidebar button, the first of KIT.md's "Sidebar header row": centered at x 94,
/// 28 × 28 at y 9. It sits in `PaneLayout`'s window header, so it stays put with the
/// sidebar hidden. View > Hide Sidebar (⌃⌘S) does the same.
struct SidebarToggleButton: View {
    var sidebarVisible: Bool
    var toggle: () -> Void

    private var title: String { sidebarVisible ? "Hide Sidebar" : "Show Sidebar" }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Metric.sidebarHeaderFirstX - Metric.iconButton / 2, height: Metric.iconButton)
            Button(action: toggle) {
                KitIconView(.hideSidebar)
            }
            .buttonStyle(HeaderIconButtonStyle())
            .gridProbe("hideSidebar", area: "windowHeader", edge: nil)
            .help(title)
            .accessibilityLabel(title)
        }
        .padding(.top, Metric.controlY)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A 28 × 28 icon button in the window header, with KIT.md "Sidebar header row"'s states:
/// rest (no fill, textSecondary), hover (selection fill, text), pressed (selection at 80%),
/// focused (2 pt focus ring, corner 7), and disabled (textSecondary at 40%).
struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        private var lit: Bool { isEnabled && (hovering || configuration.isPressed || isFocused) }

        private var fill: Color {
            guard isEnabled, hovering || configuration.isPressed else { return .clear }
            return configuration.isPressed ? Ink.selection.opacity(0.8) : Ink.selection
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metric.iconButtonCorner)
            configuration.label
                .foregroundStyle(lit ? Ink.text : Ink.textSecondary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(width: Metric.iconButton, height: Metric.iconButton)
                .background(fill, in: shape)
                .overlay {
                    if isFocused { shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing) }
                }
                .contentShape(shape)
                .focusEffectDisabled()
                .onHover { inside in
                    withAnimation(Motion.hover) { hovering = inside }
                }
        }
    }
}
