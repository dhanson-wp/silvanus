import Foundation

/// A meeting's to-do list: what the local model is asked, what's kept of its answer,
/// and how a new answer meets a list the user has changed. `todo.md` holds Markdown
/// checkboxes, one per line: `- [ ] Sam: send the project plan`.
public enum Todos {
    /// What `todo.md` says when the model found nothing to do.
    public static let none = "No to-dos from this call."

    public static let system = """
        You read a meeting transcript and list the to-dos people committed to. \
        A to-do is something a person said they will do after the meeting, or was asked to do and agreed to. \
        Ideas, opinions, and things already done are not to-dos. Never invent one.

        Answer with one line per to-do and nothing else, in this form:
        - [ ] Owner: what they will do, with the deadline if one was said

        Use the speaker's name as the owner. Write each to-do once, short and specific. \
        If there are no to-dos, answer with exactly: NONE
        """

    /// The request: the transcript, and the user's own notes when there are any.
    public static func request(transcript: String, notes: String = "", me: String = "Me") -> String {
        var parts = ["The person reading this list is \(me)."]
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty { parts.append("Their own notes from the meeting:\n\n\(trimmedNotes)") }
        parts.append("The transcript:\n\n\(transcript.trimmingCharacters(in: .whitespacesAndNewlines))")
        return parts.joined(separator: "\n\n")
    }

    /// The to-dos in the model's answer, each as "- [ ] text". Lines that aren't list
    /// items are dropped, and so are repeats.
    public static func parse(_ answer: String) -> [String] {
        var seen = Set<String>(), items: [String] = []
        for line in answer.split(whereSeparator: \.isNewline) {
            var text = line.trimmingCharacters(in: .whitespaces)
            guard let bullet = text.first, "-*•".contains(bullet) else { continue }
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            for box in ["[ ]", "[x]", "[X]", "[]"] where text.hasPrefix(box) {
                text = String(text.dropFirst(box.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            let key = key(text)
            guard !key.isEmpty, key != "none", seen.insert(key).inserted else { continue }
            items.append("- [ ] \(text)")
        }
        return items
    }

    /// What `todo.md` becomes when the model writes the list again.
    /// - `existing`: the file now. `written`: what the model wrote last time.
    /// A list the user never touched is replaced. One they ticked, edited, or added to
    /// keeps every line, and gains only the to-dos it doesn't already have and that
    /// weren't in the last answer (those were removed or reworded on purpose).
    public static func merge(existing: String, written: String, generated: [String]) -> String {
        let lines = existing.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let fresh = generated.isEmpty ? none + "\n" : generated.joined(separator: "\n") + "\n"
        let untouched = lines.isEmpty || normalized(existing) == normalized(written)
        if untouched { return fresh }
        guard !generated.isEmpty else { return lines.joined(separator: "\n") + "\n" }
        let known = Set((lines + written.split(whereSeparator: \.isNewline).map(String.init)).map(key))
        let added = generated.filter { !known.contains(key($0)) }
        let kept = lines.filter { $0.trimmingCharacters(in: .whitespaces) != none }
        return (kept + added).joined(separator: "\n") + "\n"
    }

    /// A to-do's words only: no bullet, box, case, or punctuation, so a ticked or
    /// lightly reworded line still matches itself.
    static func key(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let bullet = text.first, "-*•".contains(bullet) { text = String(text.dropFirst()) }
        text = text.trimmingCharacters(in: .whitespaces)
        for box in ["[ ]", "[x]", "[X]", "[]"] where text.hasPrefix(box) { text = String(text.dropFirst(box.count)); break }
        return text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// The Summary page as one text: a To-dos heading, the to-do list, then the summary.
/// Only the list can be edited; the heading before it and the summary after it are locked.
public struct TodoPage: Equatable, Sendable {
    public static let heading = "## To-dos\n"

    public let prefix: String
    public let suffix: String

    public init(summary: String) {
        prefix = Self.heading
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        suffix = trimmed.isEmpty ? "" : "\n\n" + trimmed + "\n"
    }

    /// The page's text for this to-do list.
    public func text(todo: String) -> String {
        prefix + todo.trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }

    /// The to-do list in the page's text, as `todo.md` holds it; empty when nothing is left.
    /// Nil when the text has lost its locked parts.
    public func todo(in text: String) -> String? {
        guard text.hasPrefix(prefix), text.hasSuffix(suffix),
              text.utf16.count >= prefix.utf16.count + suffix.utf16.count else { return nil }
        let list = text.dropFirst(prefix.count).dropLast(suffix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return list.isEmpty ? "" : list + "\n"
    }

    /// The locked lengths, in UTF-16 units, as the text view counts.
    public var lockedPrefix: Int { prefix.utf16.count }
    public var lockedSuffix: Int { suffix.utf16.count }
}
