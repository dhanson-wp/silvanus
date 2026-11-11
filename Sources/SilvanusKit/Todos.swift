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

/// Every meeting's to-dos in one place: the To-dos page in the sidebar.
public enum TodoBoard {
    /// One checkbox line of a meeting's `todo.md`.
    public struct Item: Equatable, Identifiable, Sendable {
        public var meetingID: String
        /// The line's place in `todo.md`, counting every line from 0.
        public var line: Int
        public var text: String
        public var done: Bool

        public init(meetingID: String, line: Int, text: String, done: Bool) {
            self.meetingID = meetingID
            self.line = line
            self.text = text
            self.done = done
        }

        public var id: String { "\(meetingID)#\(line)" }
    }

    /// A meeting that still has something to do, with all its to-dos.
    public struct Group: Equatable, Identifiable, Sendable {
        public var meetingID: String
        public var title: String
        public var start: Date
        public var items: [Item]

        public var id: String { meetingID }
        public var open: Int { items.count { !$0.done } }
    }

    /// The checkbox lines in a `todo.md`. Other lines (the "no to-dos" line, plain text) aren't to-dos.
    public static func items(in todo: String, meetingID: String) -> [Item] {
        todo.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            guard let parsed = parse(line) else { return nil }
            return Item(meetingID: meetingID, line: index, text: parsed.text, done: parsed.done)
        }
    }

    /// The meetings with at least one open to-do, in the order given (newest first in the
    /// app). A meeting whose to-dos are all done drops off the page.
    public static func groups(_ meetings: [Meeting]) -> [Group] {
        meetings.compactMap { meeting in
            let items = items(in: meeting.todo, meetingID: meeting.id)
            guard items.contains(where: { !$0.done }) else { return nil }
            return Group(meetingID: meeting.id, title: meeting.displayTitle, start: meeting.info.start, items: items)
        }
    }

    /// How many to-dos are still open across the meetings.
    public static func openCount(_ meetings: [Meeting]) -> Int {
        meetings.reduce(0) { $0 + items(in: $1.todo, meetingID: $1.id).count { !$0.done } }
    }

    /// `todo` with the checkbox on `line` ticked or unticked; nil when that line isn't a to-do.
    public static func toggled(_ todo: String, line: Int) -> String? {
        var lines = todo.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.indices.contains(line), let parsed = parse(Substring(lines[line])),
              let box = lines[line].range(of: parsed.done ? (lines[line].contains("[X]") ? "[X]" : "[x]") : "[ ]") else { return nil }
        lines[line].replaceSubrange(box, with: parsed.done ? "[ ]" : "[x]")
        return lines.joined(separator: "\n")
    }

    /// The id of the list that belongs to no meeting: to-dos added on the To-dos page itself.
    public static let own = ""

    /// `todo` with a new open to-do at the end. The "no to-dos" line goes once there is one.
    /// Blank text adds nothing.
    public static func added(_ todo: String, text: String) -> String {
        let text = oneLine(text)
        guard !text.isEmpty else { return todo }
        var lines = todo.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces) == Todos.none }
        lines.append("- [ ] \(text)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `todo` with the words of the to-do on `line` changed, its box as it was. Blank text
    /// removes the to-do. Nil when that line isn't a to-do.
    public static func edited(_ todo: String, line: Int, text: String) -> String? {
        let text = oneLine(text)
        guard !text.isEmpty else { return removed(todo, line: line) }
        var lines = todo.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.indices.contains(line), let parsed = parse(Substring(lines[line])) else { return nil }
        lines[line] = "- [\(parsed.done ? "x" : " ")] \(text)"
        return lines.joined(separator: "\n")
    }

    /// `todo` without the to-do on `line`; nil when that line isn't a to-do.
    public static func removed(_ todo: String, line: Int) -> String? {
        var lines = todo.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.indices.contains(line), parse(Substring(lines[line])) != nil else { return nil }
        lines.remove(at: line)
        let text = lines.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
    }

    /// A to-do is one line: line breaks become spaces.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func parse(_ line: Substring) -> (text: String, done: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for (mark, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false), ("* [x] ", true)] where trimmed.hasPrefix(mark) {
            let text = String(trimmed.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (text, done)
        }
        return nil
    }
}
