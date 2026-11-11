import Foundation

/// A meeting's written summary: what the local model is asked, what's kept of its
/// answer, and how a new answer meets a `summary.md` that already has something in it.
public enum Summaries {
    public static let system = """
        You write a short summary of a meeting from its transcript, for someone who was there. \
        Use only what was said. Never invent a name, number, date, or decision.

        Answer in Markdown with these sections, in this order, and nothing else:

        ## Overview
        Two or three sentences on what the meeting was about and where it ended up.

        ## Decisions
        - One line per decision that was made.

        ## Open questions
        - One line per question left unanswered.

        Leave out Decisions or Open questions when there were none. Don't list to-dos: they're kept elsewhere. \
        Keep every line short and plain.
        """

    /// The request: the transcript, and the user's own notes when there are any.
    public static func request(transcript: String, notes: String = "", me: String = "Me") -> String {
        Todos.request(transcript: transcript, notes: notes, me: me)
            .replacingOccurrences(of: "The person reading this list is", with: "The person reading this summary is")
    }

    /// The summary in the model's answer: from its first heading on, without code fences
    /// or a closing remark after a blank line that isn't part of a section. Empty when the
    /// answer has no heading.
    public static func parse(_ answer: String) -> String {
        var lines = answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        guard let first = lines.firstIndex(where: { $0.hasPrefix("## ") }) else { return "" }
        let text = lines[first...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : text + "\n"
    }

    /// What `summary.md` becomes when the model writes a summary.
    /// - `existing`: the file now. `written`: what the model wrote last time.
    /// An empty file gets the summary. A file that starts with the last answer has that
    /// part replaced. Anything else (an imported summary) is kept, under the new one.
    public static func merge(existing: String, written: String, generated: String) -> String {
        let old = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = written.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return existing }
        if old.isEmpty { return new + "\n" }
        let rest = !last.isEmpty && old.hasPrefix(last)
            ? String(old.dropFirst(last.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : old
        return rest.isEmpty ? new + "\n" : new + "\n\n" + rest + "\n"
    }
}
