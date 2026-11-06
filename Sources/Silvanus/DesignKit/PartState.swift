import SwiftUI

/// The state a kit part draws. Each part works out its own from hover, press, focus, and
/// enabled; the gallery forces one with `.environment(\.forcedPartState, ...)` so hover and
/// pressed show up in a snapshot. "Window inactive" is separate: force it with
/// `.environment(\.appearsActive, false)`.
enum PartState: String, CaseIterable {
    case rest, hover, pressed, selected, focused, disabled
}

// A plain key, not @Entry: Command Line Tools ship without the SwiftUI macro plugin.
private struct ForcedPartStateKey: EnvironmentKey {
    static let defaultValue: PartState? = nil
}

extension EnvironmentValues {
    /// Set by the gallery only. Nil in the app.
    var forcedPartState: PartState? {
        get { self[ForcedPartStateKey.self] }
        set { self[ForcedPartStateKey.self] = newValue }
    }
}
