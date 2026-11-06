import Foundation

/// Formats elapsed time for transcript and note timestamps.
public enum Clock {
    /// `mm:ss` under an hour, `h:mm:ss` from one hour on. The brackets around
    /// a timestamp are added by the caller.
    public static func text(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
