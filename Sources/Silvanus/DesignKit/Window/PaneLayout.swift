import AppKit
import SwiftUI

/// The window's frame, from design/KIT.md "Window": a 208 pt sidebar on `Ink.sidebar`, a
/// 1 pt `Ink.divider` line at x 208, and the canvas from x 209 to the window's edge on
/// `Ink.canvas`, with 10 pt corners where it meets the top and bottom of the window. A 46 pt
/// header runs across both panes with no fill or border of its own.
///
/// The slots:
/// - `windowHeader` sits at the window's top left over both panes, after the traffic
///   lights. It stays put when the sidebar hides, so the hide sidebar button never moves.
/// - `sidebar` fills the sidebar under the header.
/// - `header` is the canvas's header; its content starts at x 221 (`Metric.contentX`), or
///   just after `windowHeader` when the sidebar is hidden.
/// - `canvas` fills the canvas under the header.
///
/// Hiding the sidebar slides the canvas over it with `Motion.select`; the canvas then runs
/// edge to edge with square corners and no divider. Animate the change yourself
/// (`withAnimation(Motion.select)`) so menus and buttons animate alike.
struct PaneLayout<WindowHeader: View, Sidebar: View, Header: View, Canvas: View>: View {
    var sidebarVisible: Bool
    @ViewBuilder var windowHeader: WindowHeader
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var header: Header
    @ViewBuilder var canvas: Canvas

    /// Where canvas header content starts with the sidebar hidden: 12 after the last
    /// sidebar header button, the hide sidebar button (KIT.md "Sidebar header row").
    static var collapsedHeaderX: CGFloat {
        Metric.sidebarHeaderFirstX + Metric.controlHeight / 2 + Metric.contentTrailing
    }

    private var sidebarWidth: CGFloat { sidebarVisible ? Metric.sidebarWidth : 0 }
    private var corner: CGFloat { sidebarVisible ? Metric.canvasCorner : 0 }
    /// The divider is the canvas's leading border, so the canvas's content starts after it.
    private var edge: CGFloat { sidebarVisible ? Metric.hairline : 0 }
    /// The header content's inset from the canvas content's leading edge.
    private var headerInset: CGFloat {
        sidebarVisible ? Metric.contentX - Metric.canvasX : Self.collapsedHeaderX
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .padding(.top, Metric.headerHeight)
                .frame(width: Metric.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(alignment: .top) { WindowDragArea(area: .sidebar, active: sidebarVisible) }
                .frame(width: sidebarWidth, alignment: .leading)
                .clipped()
                // Hidden, the sidebar takes no clicks and no keyboard focus.
                .allowsHitTesting(sidebarVisible)
                .disabled(!sidebarVisible)
                .accessibilityHidden(!sidebarVisible)
            VStack(spacing: 0) {
                header
                    .padding(.leading, headerInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Metric.headerHeight)
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.leading, edge)
            // Here, not on `header`: an empty header slot would drop it.
            .background(alignment: .top) { WindowDragArea(area: .canvas, active: true) }
            .background {
                CanvasShape(corner: corner).fill(Ink.canvas)
                CanvasEdge(corner: corner, lineWidth: Metric.hairline)
                    .stroke(Ink.divider, lineWidth: Metric.hairline)
                    .opacity(sidebarVisible ? 1 : 0)
            }
        }
        .background(Ink.sidebar)
        .overlay(alignment: .topLeading) {
            windowHeader
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Metric.headerHeight)
                // The header's controls are measured from the window's edge, not inset.
                .gridArea("windowHeader", inset: 0)
        }
        .ignoresSafeArea()
    }
}

/// The canvas's ground: square on the trailing side, `corner` on the leading top and bottom.
private struct CanvasShape: Shape {
    var corner: CGFloat

    var animatableData: CGFloat {
        get { corner }
        set { corner = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: corner, bottomLeadingRadius: corner, style: .circular)
            .path(in: rect)
    }
}

/// The canvas's leading border, the divider at x 208: down the leading edge and around both
/// corners, with nothing along the top, bottom, or trailing side. Stroked 1 pt wide, its
/// outer edge follows `CanvasShape` exactly.
private struct CanvasEdge: Shape {
    var corner: CGFloat
    /// The stroke's width, so the path can sit half of it inside the edge.
    let lineWidth: CGFloat

    var animatableData: CGFloat {
        get { corner }
        set { corner = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let half = lineWidth / 2
        let x = rect.minX + half
        let radius = max(corner - half, 0)
        var path = Path()
        path.move(to: CGPoint(x: x + radius, y: rect.minY + half))
        path.addArc(tangent1End: CGPoint(x: x, y: rect.minY + half),
                    tangent2End: CGPoint(x: x, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: x, y: rect.maxY - half),
                    tangent2End: CGPoint(x: x + radius, y: rect.maxY - half), radius: radius)
        path.addLine(to: CGPoint(x: x + radius, y: rect.maxY - half))
        return path
    }
}

/// The header's empty space acts like a title bar: drag to move the window, double-click to
/// zoom or minimize it as System Settings > Desktop & Dock says. It sits behind the header's
/// controls, so it only gets the clicks they don't take. An AppKit view rather than SwiftUI
/// gestures, so a drag and a double click never compete.
private struct WindowDragArea: View {
    var area: HeaderClickView.Area
    var active: Bool

    var body: some View {
        HeaderClickView(area: area, active: active)
            .frame(height: Metric.headerHeight)
    }
}

/// The header's click target. `area` names which pane's header it is (the self-test checks
/// hits by it). While `active` is false (the sidebar's, with the sidebar hidden) it takes no
/// clicks at all, whatever frame AppKit left it.
struct HeaderClickView: NSViewRepresentable {
    enum Area: String { case sidebar, canvas }

    var area: Area
    var active: Bool

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.area = area
        view.active = active
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.area = area
        view.active = active
    }

    final class ClickView: NSView {
        var area: Area = .canvas
        var active = true

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            active ? super.hitTest(point) : nil
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            switch event.clickCount {
            case 1: window.performDrag(with: event)
            case 2: TitleBarDoubleClick.perform(on: window)
            // A triple click is not a title bar gesture.
            default: break
            }
        }
    }
}

/// What double-clicking a title bar does, from the person's setting (System Settings >
/// Desktop & Dock > "Double-click a window's title bar to"). Unset means zoom, as macOS does.
enum TitleBarDoubleClick: Equatable {
    case zoom, minimize, none

    static let defaultsKey = "AppleActionOnDoubleClick"

    init(setting: String?) {
        switch setting {
        case "Minimize": self = .minimize
        case "None": self = .none
        default: self = .zoom
        }
    }

    /// Runs the person's choice: `zoom` or `minimize` is called, or neither. The self-test
    /// passes its own closures; `perform(on:)` passes the window's.
    static func handle(setting: String?, zoom: () -> Void, minimize: () -> Void) {
        switch TitleBarDoubleClick(setting: setting) {
        case .zoom: zoom()
        case .minimize: minimize()
        case .none: break
        }
    }

    static func perform(on window: NSWindow) {
        handle(setting: UserDefaults.standard.string(forKey: defaultsKey),
               zoom: { window.performZoom(nil) },
               minimize: { window.performMiniaturize(nil) })
    }
}
