import Foundation

/// Where a meeting lives on disk: `meetings/<series>/<yyyy-MM-dd HHmm>/`,
/// holding plain files.
public enum MeetingFolder {
    public static let notes = "notes.md"
    public static let transcript = "transcript.md"
    public static let transcriptJSON = "transcript.json"
    public static let summary = "summary.md"
    public static let todo = "todo.md"
    public static let info = "meeting.json"
    public static let audio = "audio"
    /// When each note line was written during the recording (`NoteTimes`).
    public static let noteTimes = "notes-times.json"
    /// In `audio/`: how many after-call passes failed in a row (a plain number).
    public static let attempts = "attempts"

    /// The top folder under the library root.
    public static let top = "meetings"

    /// `meetings/<safe series>/<yyyy-MM-dd HHmm>`. The series name is made safe
    /// for a file name (no slashes or colons, at most 80 characters, no leading
    /// dot). The time uses the calendar's time zone.
    public static func relativePath(series: String, start: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "\(top)/\(safeSeries(series))/\(formatter.string(from: start))"
    }

    /// The series name as a single safe folder name.
    public static func safeSeries(_ series: String) -> String {
        var name = MeetingTitle.fileSafe(series)
        if name.hasPrefix(".") { name = "-" + name.dropFirst() }
        return name
    }
}
