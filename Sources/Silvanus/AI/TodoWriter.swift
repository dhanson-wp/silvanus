import Foundation
import SilvanusKit

/// Writes a meeting's to-do list: asks a model for the to-dos in the transcript and
/// saves them to `todo.md`, keeping what the user changed (`Todos.merge`).
enum TodoWriter {
    /// Asks a model: the system text, then the request. The local model by default;
    /// a connector to another model would be another one of these.
    typealias Ask = (_ system: String, _ user: String) async throws -> String

    /// Returns the list as saved, or nil when the meeting has no transcript to read.
    @discardableResult
    static func write(id: String, library: MeetingLibrary, me: String, ask: Ask) async throws -> String? {
        guard let meeting = library.meeting(id: id), !meeting.transcriptMarkdown.isEmpty else { return nil }
        let answer = try await ask(Todos.system, Todos.request(transcript: meeting.transcriptMarkdown, notes: meeting.notes, me: me))
        let generated = Todos.parse(answer)
        // Read again: the list may have been edited while the model was writing.
        let merged = Todos.merge(existing: library.readTodo(id: id) ?? "", written: library.readWrittenTodo(id: id),
                                 generated: generated)
        let written = generated.isEmpty ? Todos.none + "\n" : generated.joined(separator: "\n") + "\n"
        try library.saveTodo(merged, written: written, for: id)
        return merged
    }
}
