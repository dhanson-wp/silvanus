import Foundation
import Testing
@testable import SilvanusKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

// 2026-11-06 14:30:00 UTC, whole seconds.
private let start = Date(timeIntervalSince1970: 1_793_975_400)

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "silvanus-tests-\(UUID().uuidString)")
}

/// Deletes instead of trashing, so tests never touch the real Trash.
private func library(_ root: URL) -> MeetingLibrary {
    MeetingLibrary(root: root, calendar: utc, trash: { try FileManager.default.removeItem(at: $0) })
}

private func kickoff(id: String = UUID().uuidString, at date: Date = start) -> Meeting {
    Meeting(
        info: MeetingInfo(
            id: id, title: "Acme kickoff", series: "Acme kickoff", start: date,
            end: date.addingTimeInterval(1800),
            attendees: ["Sam Rivera", "Priya Natarajan", "Jordan Lee"],
            folder: "Clients", source: "granola", granolaID: "g-123",
            speakers: ["mic": "Sam Rivera", "call": "Priya Natarajan"],
            asr: ASRInfo(engine: "parakeet", model: "v3", processedAt: date.addingTimeInterval(2400))),
        notes: "Agenda\n- scope\n- dates\n",
        summary: "Agreed on scope.",
        todo: "- [ ] Sam sends the plan\n",
        transcriptMarkdown: "[0:00] Sam Rivera: Hello\n")
}

private func names(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

@Test func roundTrip() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let m = kickoff()
    try lib.save(m)
    let loaded = library(root).loadAll()
    #expect(loaded.unreadable.isEmpty)
    #expect(loaded.meetings == [m])
    #expect(loaded.meetings.first?.info.attendees == ["Sam Rivera", "Priya Natarajan", "Jordan Lee"])
    #expect(loaded.meetings.first?.info.speakers["call"] == "Priya Natarajan")
}

@Test func loadAllIsNewestFirst() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let older = kickoff(id: "a", at: start.addingTimeInterval(-86_400))
    let newer = kickoff(id: "b")
    try lib.save(older); try lib.save(newer)
    #expect(library(root).loadAll().meetings.map(\.id) == ["b", "a"])
}

@Test func layout() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var m = kickoff()
    m.summary = ""; m.todo = ""; m.transcriptMarkdown = ""
    let folder = try library(root).save(m)
    #expect(folder == root.appending(path: "meetings/Acme kickoff/2026-11-06 1430"))
    #expect(names(folder) == ["meeting.json", "notes.md"])
}

@Test func emptyNotesStillWritesNotesFile() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var m = kickoff(); m.notes = ""
    let folder = try library(root).save(m)
    #expect(names(folder).contains("notes.md"))
}

@Test func emptiedFieldsDeleteStaleFiles() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    var m = kickoff()
    let folder = try lib.save(m)
    #expect(names(folder) == ["meeting.json", "notes.md", "summary.md", "todo.md", "transcript.md"])
    m.summary = ""; m.todo = ""; m.transcriptMarkdown = ""
    try lib.save(m)
    #expect(names(folder) == ["meeting.json", "notes.md"])
}

@Test func emptySeriesUsesTheTitle() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var m = kickoff(); m.info.series = ""; m.info.title = "Design review"
    let folder = try library(root).save(m)
    #expect(folder.deletingLastPathComponent().lastPathComponent == "Design review")
}

@Test func jsonKeys() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let folder = try library(root).save(kickoff())
    let data = try Data(contentsOf: folder.appending(path: "meeting.json"))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"granola_id\""))
    #expect(text.contains("\"processed_at\""))
    #expect(text.contains("2026-11-06T14:30:00Z"))
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["granola_id"] as? String == "g-123")
    let sorted = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    #expect(String(decoding: sorted, as: UTF8.self) == text)
}

@Test func sameMinuteGetsSuffix() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let first = try lib.save(kickoff(id: "one"))
    let second = try lib.save(kickoff(id: "two"))
    let third = try lib.save(kickoff(id: "three"))
    #expect(first.lastPathComponent == "2026-11-06 1430")
    #expect(second.lastPathComponent == "2026-11-06 1430 2")
    #expect(third.lastPathComponent == "2026-11-06 1430 3")
    // Saving the first again keeps its folder.
    #expect(try lib.save(kickoff(id: "one")) == first)
    #expect(library(root).loadAll().meetings.count == 3)
}

@Test func reloadedLibraryKeepsFolders() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let first = try library(root).save(kickoff(id: "one"))
    let second = library(root)
    _ = second.loadAll()
    #expect(second.folderURL(for: "one") == first)
    #expect(try second.save(kickoff(id: "one")) == first)
}

@Test func renameKeepsFolder() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    var m = kickoff()
    let folder = try lib.save(m)
    m.info.title = "Acme: renamed"
    m.info.series = "Another series"
    #expect(try lib.save(m) == folder)
    #expect(lib.folderURL(for: m.id) == folder)
    #expect(library(root).loadAll().meetings.first?.info.title == "Acme: renamed")
}

@Test func saveIsAtomic() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    var m = kickoff()
    let folder = try lib.save(m)
    m.notes = "Changed notes"
    try lib.save(m)
    #expect(names(folder) == ["meeting.json", "notes.md", "summary.md", "todo.md", "transcript.md"])
    #expect(try String(contentsOf: folder.appending(path: "notes.md"), encoding: .utf8) == "Changed notes")
    #expect(library(root).loadAll().meetings == [m])
}

@Test func unreadableFolderIsReported() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let good = try lib.save(kickoff(id: "good"))
    let badFolder = root.appending(path: "meetings/Broken/2026-11-05 0900")
    try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: badFolder.appending(path: "meeting.json"))
    let loaded = library(root).loadAll()
    #expect(loaded.meetings.map(\.id) == ["good"])
    #expect(loaded.unreadable == [badFolder])
    #expect(FileManager.default.fileExists(atPath: good.path))
}

@Test func loadAllOnAMissingRootIsEmpty() {
    let loaded = library(tempRoot()).loadAll()
    #expect(loaded.meetings.isEmpty && loaded.unreadable.isEmpty)
}

@Test func trashRemovesFolder() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let m = kickoff()
    let folder = try lib.save(m)
    try lib.moveToTrash(m.id)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(lib.folderURL(for: m.id) == nil)
    #expect(library(root).loadAll().meetings.isEmpty)
}

@Test func trashingAnUnknownIdDoesNothing() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let folder = try library(root).save(kickoff(id: "one"))
    try library(root).moveToTrash("one")
    #expect(FileManager.default.fileExists(atPath: folder.path))
}

@Test func twoInstancesSameMinute() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let first = try library(root).save(kickoff(id: "one"))
    let second = try library(root).save(kickoff(id: "two"))
    #expect(first.lastPathComponent == "2026-11-06 1430")
    #expect(second.lastPathComponent == "2026-11-06 1430 2")
}

@Test func freshInstanceFindsExistingFolder() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let first = try library(root).save(kickoff(id: "one"))
    var renamed = kickoff(id: "one")
    renamed.info.series = "Renamed series"
    #expect(try library(root).save(renamed) == first)
    #expect(library(root).loadAll().meetings.count == 1)
}
