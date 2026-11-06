import Foundation

/// One recorded or imported conversation, as the app holds it in memory.
/// On disk it is a folder of plain files (see `MeetingFolder`).
public struct Meeting: Identifiable, Equatable, Sendable {
    public var info: MeetingInfo
    /// What I typed on the meeting's page. `notes.md`.
    public var notes: String
    /// The summary, when one exists. `summary.md`.
    public var summary: String
    /// Action items, when there are any. `todo.md`.
    public var todo: String
    /// The readable transcript. `transcript.md`. Empty until transcription runs.
    public var transcriptMarkdown: String

    public init(info: MeetingInfo, notes: String = "", summary: String = "",
                todo: String = "", transcriptMarkdown: String = "") {
        self.info = info
        self.notes = notes
        self.summary = summary
        self.todo = todo
        self.transcriptMarkdown = transcriptMarkdown
    }

    public var id: String { info.id }

    /// The title shown when the meeting has none yet.
    public static let untitled = "Untitled meeting"

    public var displayTitle: String {
        let t = MeetingTitle.clean(info.title)
        return t.isEmpty ? Self.untitled : t
    }
}

/// Rules for meeting titles and the folder names made from them.
public enum MeetingTitle {
    /// Trims spaces and line breaks and collapses inner runs of spaces.
    public static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A title made safe for a file name: no slashes or colons, at most 80 characters.
    public static func fileSafe(_ text: String) -> String {
        let cleaned = clean(text).map { "/:\\".contains($0) ? "-" : $0 }
        let s = String(String(cleaned).prefix(80)).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "Untitled meeting" : s
    }
}
