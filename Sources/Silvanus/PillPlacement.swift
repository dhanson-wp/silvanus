import AppKit

/// Where the floating recording pill sits. The anchor is the capsule's top trailing corner,
/// so hovering can grow it leftward without moving it. Saved in AppDefaults.
enum PillPlacement {
    static let defaultsKey = "recordingPill.anchor"

    /// Top right of a screen's visible frame, `Space.lg` in from both edges.
    static func defaultAnchor(in visible: NSRect) -> NSPoint {
        NSPoint(x: visible.maxX - Space.lg, y: visible.maxY - Space.lg)
    }

    /// The saved anchor if it's still on a screen (a monitor may have gone away), else the
    /// default on the main screen.
    static func resolve(saved: NSPoint?, screens: [NSRect], main: NSRect) -> NSPoint {
        if let saved, screens.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(saved) }) { return saved }
        return defaultAnchor(in: main)
    }

    static func saved(_ defaults: UserDefaults = AppDefaults.shared) -> NSPoint? {
        defaults.string(forKey: defaultsKey).map(NSPointFromString).flatMap { $0 == .zero ? nil : $0 }
    }

    static func save(_ anchor: NSPoint, to defaults: UserDefaults = AppDefaults.shared) {
        defaults.set(NSStringFromPoint(anchor), forKey: defaultsKey)
    }

    /// A frame of `size` whose top trailing corner (less `inset`) is at `anchor`, kept
    /// inside `visible` (the screen holding the anchor) so a widened pill never runs off it.
    static func frame(anchor: NSPoint, size: NSSize, inset: CGFloat, visible: NSRect?) -> NSRect {
        var origin = NSPoint(x: anchor.x + inset - size.width, y: anchor.y + inset - size.height)
        if let visible {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        return NSRect(origin: origin, size: size)
    }
}
