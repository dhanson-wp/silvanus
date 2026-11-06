import Foundation

/// The meetings on disk. Every meeting is one folder of plain files under
/// `<root>/meetings/<series>/<date time>/`; the folders are the whole database.
public final class MeetingLibrary {
    public let root: URL
    private let calendar: Calendar
    /// Where each meeting's folder is, so a renamed meeting keeps its folder.
    private var folders: [String: URL] = [:]

    public init(root: URL, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
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

    /// Moves the whole meeting folder to the Trash, so it can be put back.
    public func moveToTrash(_ id: String) throws {
        guard let folder = folders[id] else { return }
        try fm.trashItem(at: folder, resultingItemURL: nil)
        folders[id] = nil
    }

    // MARK: - Private

    private func folderForSaving(_ m: Meeting) throws -> URL {
        if let known = folders[m.id] { return known }
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
