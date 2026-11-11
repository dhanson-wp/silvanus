import Foundation

/// The meetings on disk. Every meeting is one folder of plain files under
/// `<root>/meetings/<series>/<date time>/`; the folders are the whole database.
public final class MeetingLibrary {
    public let root: URL
    private let calendar: Calendar
    /// Where each meeting's folder is, so a renamed meeting keeps its folder.
    private var folders: [String: URL] = [:]
    private let trash: (URL) throws -> Void

    /// `trash` moves a folder to the Trash. Tests and the self-test pass a
    /// closure that deletes instead, so they never touch the real Trash.
    public init(root: URL, calendar: Calendar = .current,
                trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.root = root
        self.calendar = calendar
        self.trash = trash
    }

    private var fm: FileManager { .default }

    /// Every meeting under the root, newest first. A folder without a readable
    /// `meeting.json` is skipped and reported.
    public func loadAll() -> (meetings: [Meeting], unreadable: [URL]) {
        var meetings: [Meeting] = [], bad: [URL] = []
        folders = [:]
        let top = root.appending(path: MeetingFolder.top)
        for series in subfolders(of: top) {
            for folder in subfolders(of: series) {
                if let m = read(folder) {
                    meetings.append(m)
                    folders[m.id] = folder
                } else {
                    bad.append(folder)
                }
            }
        }
        return (meetings.sorted { $0.info.start > $1.info.start }, bad)
    }

    /// Writes the meeting's files atomically, one by one. `notes.md` and
    /// `meeting.json` are always written; the others only when they have
    /// content, and a file whose content was emptied is removed.
    @discardableResult
    public func save(_ m: Meeting) throws -> URL {
        let folder = try folderForSaving(m)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        // Known before the files are written, so a caller can clean up after a failed save.
        folders[m.id] = folder
        try write(m.notes, to: MeetingFolder.notes, in: folder, always: true)
        try write(m.summary, to: MeetingFolder.summary, in: folder)
        try write(m.todo, to: MeetingFolder.todo, in: folder)
        try write(m.transcriptMarkdown, to: MeetingFolder.transcript, in: folder)
        try MeetingInfo.encoder().encode(m.info)
            .write(to: folder.appending(path: MeetingFolder.info), options: .atomic)
        folders[m.id] = folder
        return folder
    }

    /// The meeting's folder, once it has been loaded or saved.
    public func folderURL(for id: String) -> URL? { folders[id] }

    /// No meeting with this id is on disk.
    public struct NotFound: Error, Equatable {
        public let id: String
    }

    /// The meeting's `notes.md`, found on disk if this instance has not loaded it yet.
    public func notesURL(for id: String) -> URL? {
        if folders[id] == nil, let found = findFolder(for: id) { folders[id] = found }
        return folders[id]?.appending(path: MeetingFolder.notes)
    }

    /// The meeting's notes as they are on disk now, or nil when the meeting is unknown or
    /// `notes.md` can't be read (missing, mid-replace, not UTF-8). Nil is never "empty".
    public func readNotes(for id: String) -> String? {
        guard let url = notesURL(for: id) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The meeting's `summary.md` as it is on disk now, or nil when the meeting is unknown or
    /// the file is missing or can't be read. Read only: nothing in the app writes it after import.
    public func readSummary(id: String) -> String? {
        guard let url = notesURL(for: id)?.deletingLastPathComponent().appending(path: MeetingFolder.summary) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The meeting's `todo.md` as it is on disk now, or nil when the meeting is unknown or
    /// the file is missing or can't be read.
    public func readTodo(id: String) -> String? {
        guard let url = notesURL(for: id)?.deletingLastPathComponent().appending(path: MeetingFolder.todo) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Writes only `todo.md`, atomically; an empty list removes the file. With `written`,
    /// also records it as what the model wrote (`.todo-written.md`), so a later answer can
    /// tell a list the user changed from one they didn't.
    public func saveTodo(_ todo: String, written: String? = nil, for id: String) throws {
        guard let folder = notesURL(for: id)?.deletingLastPathComponent() else { throw NotFound(id: id) }
        try write(todo, to: MeetingFolder.todo, in: folder)
        if let written { try write(written, to: MeetingFolder.todoWritten, in: folder) }
    }

    /// The list as the model last wrote it, or empty when it never has.
    public func readWrittenTodo(id: String) -> String {
        guard let url = notesURL(for: id)?.deletingLastPathComponent().appending(path: MeetingFolder.todoWritten) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// To-dos that belong to no meeting, added on the To-dos page: `<root>/todo.md`.
    public func readOwnTodo() -> String {
        (try? String(contentsOf: root.appending(path: MeetingFolder.todo), encoding: .utf8)) ?? ""
    }

    /// Writes `<root>/todo.md`, atomically; an empty list removes the file.
    public func saveOwnTodo(_ todo: String) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try write(todo, to: MeetingFolder.todo, in: root)
    }

    /// Writes only `notes.md`, atomically. The notes canvas saves this way so a summary,
    /// transcript, or details another app changed meanwhile are never overwritten with
    /// an older copy.
    public func saveNotes(_ notes: String, for id: String) throws {
        guard let url = notesURL(for: id) else { throw NotFound(id: id) }
        try Data(notes.utf8).write(to: url, options: .atomic)
    }

    /// The meeting's `transcript.json`, or nil when the meeting is unknown or it has no
    /// readable transcript yet.
    public func readTranscript(id: String) -> Transcript? {
        guard let url = notesURL(for: id)?.deletingLastPathComponent().appending(path: MeetingFolder.transcriptJSON),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? MeetingInfo.decoder().decode(Transcript.self, from: data)
    }

    /// Writes only `transcript.json`, atomically, and `transcript.md` too when `markdown`
    /// is given. The notes, summary, to-dos, and details are never rewritten.
    public func saveTranscript(_ t: Transcript, markdown: String? = nil, for id: String) throws {
        guard let folder = notesURL(for: id)?.deletingLastPathComponent() else { throw NotFound(id: id) }
        try MeetingInfo.encoder().encode(t).write(to: folder.appending(path: MeetingFolder.transcriptJSON), options: .atomic)
        if let markdown {
            try Data(markdown.utf8).write(to: folder.appending(path: MeetingFolder.transcript), options: .atomic)
        }
    }

    /// The meeting's `notes-times.json`, or nil when there is none or it can't be read.
    public func readNoteTimes(for id: String) -> NoteTimes? {
        guard let url = notesURL(for: id)?.deletingLastPathComponent().appending(path: MeetingFolder.noteTimes),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? NoteTimes(json: data)
    }

    /// Writes only `notes-times.json`, atomically, beside the notes.
    public func saveNoteTimes(_ times: NoteTimes, for id: String) throws {
        guard let folder = notesURL(for: id)?.deletingLastPathComponent() else { throw NotFound(id: id) }
        try times.json().write(to: folder.appending(path: MeetingFolder.noteTimes), options: .atomic)
    }

    /// How many after-call passes failed in a row for this meeting (`audio/attempts`), 0
    /// when there's no record.
    public func transcriptionAttempts(for id: String) -> Int {
        guard let url = audioURL(for: id)?.appending(path: MeetingFolder.attempts),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Records the failed passes; 0 removes the record.
    public func setTranscriptionAttempts(_ count: Int, for id: String) throws {
        guard let audio = audioURL(for: id) else { throw NotFound(id: id) }
        let url = audio.appending(path: MeetingFolder.attempts)
        if count <= 0 {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        try fm.createDirectory(at: audio, withIntermediateDirectories: true)
        try Data("\(count)\n".utf8).write(to: url, options: .atomic)
    }

    /// The meeting's `audio/` folder (it may not exist yet).
    public func audioURL(for id: String) -> URL? {
        notesURL(for: id)?.deletingLastPathComponent().appending(path: MeetingFolder.audio)
    }

    /// The meeting as it is on disk now, found there if this instance has not loaded it yet.
    public func meeting(id: String) -> Meeting? {
        guard let folder = notesURL(for: id)?.deletingLastPathComponent() else { return nil }
        return read(folder)
    }

    /// Writes only `meeting.json`, atomically: a rename or other detail change never
    /// rewrites the notes, summary, to-dos, or transcript from an older copy.
    public func saveInfo(_ m: Meeting) throws {
        if folders[m.id] == nil, let found = findFolder(for: m.id) { folders[m.id] = found }
        guard let folder = folders[m.id] else { throw NotFound(id: m.id) }
        try MeetingInfo.encoder().encode(m.info).write(to: folder.appending(path: MeetingFolder.info), options: .atomic)
    }

    /// True when the meeting's folder is on disk now.
    public func folderExists(for id: String) -> Bool {
        guard let notes = notesURL(for: id) else { return false }
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: notes.deletingLastPathComponent().path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Typing that had nowhere to go (its meeting's folder was trashed or vanished) is
    /// kept as `<root>/recovered/<meeting id>-<yyyyMMdd-HHmmss>.md`. Pass the URL an
    /// earlier call returned as `replacing` to overwrite that file (atomically) instead of
    /// starting another. Returns where it went.
    @discardableResult
    public func saveRecoveredNotes(_ text: String, for id: String, at date: Date = Date(), replacing earlier: URL? = nil) throws -> URL {
        let folder = root.appending(path: "recovered")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let earlier {
            try Data(text.utf8).write(to: earlier, options: .atomic)
            return earlier
        }
        return try writeUnique(text, in: folder, base: "\(MeetingFolder.safeSeries(id))-\(stamp(date))")
    }

    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// Writes `<base>.md`, or `<base>-2.md` and so on when that's taken, atomically.
    private func writeUnique(_ text: String, in folder: URL, base: String) throws -> URL {
        var url = folder.appending(path: "\(base).md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appending(path: "\(base)-\(n).md")
            n += 1
        }
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Keeps another app's version of the notes beside `notes.md`, as
    /// `notes.conflict-<yyyyMMdd-HHmmss>.md` (a number added if that name is taken), when
    /// it couldn't be merged with unsaved typing. Returns where it went.
    @discardableResult
    public func saveConflictCopy(_ text: String, for id: String, at date: Date = Date()) throws -> URL {
        guard let notes = notesURL(for: id) else { throw NotFound(id: id) }
        return try writeUnique(text, in: notes.deletingLastPathComponent(), base: "notes.conflict-\(stamp(date))")
    }

    /// Moves the whole meeting folder to the Trash, so it can be put back, and
    /// removes its series folder if that is now empty. An id the library has
    /// not loaded or saved is a no-op.
    public func moveToTrash(_ id: String) throws {
        guard let folder = folders[id] else { return }
        try trash(folder)
        folders[id] = nil
        let series = folder.deletingLastPathComponent()
        if let left = try? fm.contentsOfDirectory(atPath: series.path), left.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(at: series)
        }
    }

    // MARK: - Private

    private func folderForSaving(_ m: Meeting) throws -> URL {
        if let known = folders[m.id] { return known }
        // A fresh instance has not loaded yet: find this meeting's folder on disk first.
        if let found = findFolder(for: m.id) { return found }
        let series = m.info.series.isEmpty ? m.displayTitle : m.info.series
        let relative = MeetingFolder.relativePath(series: series, start: m.info.start, calendar: calendar)
        var n = 1
        while true {
            let candidate = root.appending(path: n == 1 ? relative : "\(relative) \(n)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            // A folder this meeting already owns (saved by an earlier run) is reused.
            if read(candidate)?.id == m.id { return candidate }
            n += 1
        }
    }

    private func findFolder(for id: String) -> URL? {
        for series in subfolders(of: root.appending(path: MeetingFolder.top)) {
            for folder in subfolders(of: series) where read(folder)?.id == id { return folder }
        }
        return nil
    }

    private func read(_ folder: URL) -> Meeting? {
        guard let data = try? Data(contentsOf: folder.appending(path: MeetingFolder.info)),
              let info = try? MeetingInfo.decoder().decode(MeetingInfo.self, from: data) else { return nil }
        func text(_ name: String) -> String {
            (try? String(contentsOf: folder.appending(path: name), encoding: .utf8)) ?? ""
        }
        return Meeting(info: info, notes: text(MeetingFolder.notes), summary: text(MeetingFolder.summary),
                       todo: text(MeetingFolder.todo), transcriptMarkdown: text(MeetingFolder.transcript))
    }

    private func write(_ text: String, to name: String, in folder: URL, always: Bool = false) throws {
        let url = folder.appending(path: name)
        if text.isEmpty && !always {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func subfolders(of url: URL) -> [URL] {
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        // Rebuilt from names, so the URLs match the ones save() makes (no /private prefix, no trailing slash).
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url.appending(path: $0.lastPathComponent) }
    }
}
