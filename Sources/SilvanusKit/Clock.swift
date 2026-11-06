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

    /// The time as VoiceOver reads it: "14 seconds", "1 minute 5 seconds", "2 hours".
    public static func spoken(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.down)))
        func part(_ n: Int, _ unit: String) -> String? { n == 0 ? nil : "\(n) \(unit)\(n == 1 ? "" : "s")" }
        let parts = [part(s / 3600, "hour"), part(s % 3600 / 60, "minute"), part(s % 60, "second")].compactMap { $0 }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}
