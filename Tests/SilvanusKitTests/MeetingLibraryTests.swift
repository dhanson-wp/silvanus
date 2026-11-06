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
    #expect(!FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path))
}

@Test func trashKeepsSeriesWithOtherMeetings() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let a = kickoff(id: "a")
    let b = kickoff(id: "b", at: start.addingTimeInterval(86_400))
    let folderA = try lib.save(a)
    let folderB = try lib.save(b)
    try lib.moveToTrash(a.id)
    #expect(!FileManager.default.fileExists(atPath: folderA.path))
    #expect(FileManager.default.fileExists(atPath: folderB.path))
    #expect(FileManager.default.fileExists(atPath: folderA.deletingLastPathComponent().path))
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

@Test func saveNotesWritesOnlyNotes() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var m = kickoff(id: "one")
    m.summary = "Old summary"
    let folder = try library(root).save(m)
    // Another app rewrites the summary; saving notes must leave it alone.
    try Data("New summary".utf8).write(to: folder.appending(path: MeetingFolder.summary))
    let lib = library(root)
    #expect(lib.readNotes(for: "one") == m.notes)
    try lib.saveNotes("# Acme kickoff\n- Scope\n", for: "one")
    #expect(try String(contentsOf: folder.appending(path: MeetingFolder.notes), encoding: .utf8) == "# Acme kickoff\n- Scope\n")
    #expect(try String(contentsOf: folder.appending(path: MeetingFolder.summary), encoding: .utf8) == "New summary")
    #expect(lib.readNotes(for: "one") == "# Acme kickoff\n- Scope\n")
    #expect(lib.notesURL(for: "one") == folder.appending(path: MeetingFolder.notes))
    // Atomic: no temporary files are left beside it.
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(Set(names) == [MeetingFolder.notes, MeetingFolder.summary, MeetingFolder.todo,
                           MeetingFolder.transcript, MeetingFolder.info])
}

@Test func saveNotesForAnUnknownMeetingThrows() {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: MeetingLibrary.NotFound.self) { try library(root).saveNotes("x", for: "missing") }
    #expect(library(root).readNotes(for: "missing") == nil)
}

@Test func readNotesOfAMissingFileIsNil() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let folder = try library(root).save(kickoff(id: "one"))
    try FileManager.default.removeItem(at: folder.appending(path: MeetingFolder.notes))
    #expect(library(root).readNotes(for: "one") == nil)
    try Data().write(to: folder.appending(path: MeetingFolder.notes))
    #expect(library(root).readNotes(for: "one") == "")
}

@Test func saveInfoWritesOnlyMeetingJSON() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var m = kickoff(id: "one")
    let folder = try library(root).save(m)
    // Other apps change the other files; saving details must leave them alone.
    let others = [MeetingFolder.notes, MeetingFolder.summary, MeetingFolder.todo, MeetingFolder.transcript]
    for name in others { try Data("changed \(name)".utf8).write(to: folder.appending(path: name)) }
    try Data("{}".utf8).write(to: folder.appending(path: MeetingFolder.transcriptJSON))
    m.info.title = "Acme kickoff, renamed"
    m.notes = "stale copy"
    let lib = library(root)
    try lib.saveInfo(m)
    for name in others {
        #expect(try String(contentsOf: folder.appending(path: name), encoding: .utf8) == "changed \(name)")
    }
    #expect(try String(contentsOf: folder.appending(path: MeetingFolder.transcriptJSON), encoding: .utf8) == "{}")
    #expect(library(root).loadAll().meetings.first?.info.title == "Acme kickoff, renamed")
    #expect(throws: MeetingLibrary.NotFound.self) { try lib.saveInfo(kickoff(id: "missing")) }
}

@Test func conflictCopySitsBesideTheNotes() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let folder = try library(root).save(kickoff(id: "one"))
    let lib = library(root)
    let first = try lib.saveConflictCopy("Theirs\n", for: "one", at: start)
    #expect(first == folder.appending(path: "notes.conflict-20261106-143000.md"))
    #expect(try String(contentsOf: first, encoding: .utf8) == "Theirs\n")
    let second = try lib.saveConflictCopy("Again\n", for: "one", at: start)
    #expect(second != first)
    #expect(try String(contentsOf: first, encoding: .utf8) == "Theirs\n")
    #expect(lib.loadAll().meetings.count == 1)
}

@Test func recoveredNotesGoUnderTheStore() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    // Works for a meeting whose folder is gone, or was never known.
    let url = try lib.saveRecoveredNotes("Typed before the folder went\n", for: "gone", at: start)
    #expect(url == root.appending(path: "recovered/gone-20261106-143000.md"))
    #expect(try String(contentsOf: url, encoding: .utf8) == "Typed before the folder went\n")
    let again = try lib.saveRecoveredNotes("More\n", for: "gone", at: start)
    #expect(again != url)
    // A document that already has a recovery file keeps writing to it.
    let reused = try lib.saveRecoveredNotes("Latest\n", for: "gone", at: start, replacing: url)
    #expect(reused == url)
    #expect(try String(contentsOf: url, encoding: .utf8) == "Latest\n")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "recovered").path).count == 2)
    #expect(lib.loadAll().meetings.isEmpty)
}

@Test func folderExistsFollowsTheDisk() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let folder = try library(root).save(kickoff(id: "one"))
    let lib = library(root)
    #expect(lib.folderExists(for: "one"))
    try FileManager.default.removeItem(at: folder)
    #expect(!lib.folderExists(for: "one"))
    #expect(!lib.folderExists(for: "missing"))
}

@Test func transcriptRoundTripsThroughTheSidecar() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let folder = try library(root).save(kickoff(id: "one"))
    let lib = library(root)
    #expect(lib.readTranscript(id: "one") == nil)
    let t = Transcript(lines: [TranscriptLine(side: .them, words: [Word(text: "Hello", start: 1, end: 1.4, confidence: 0.4)])],
                       engine: "test", processedAt: start)
    try lib.saveTranscript(t, for: "one")
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: MeetingFolder.transcriptJSON).path))
    // A fresh library finds the folder on disk.
    #expect(library(root).readTranscript(id: "one") == t)
    #expect(lib.readTranscript(id: "missing") == nil)
    #expect(throws: MeetingLibrary.NotFound.self) { try lib.saveTranscript(t, for: "missing") }
    // Unreadable JSON is no transcript, not an error.
    try Data("{".utf8).write(to: folder.appending(path: MeetingFolder.transcriptJSON))
    #expect(lib.readTranscript(id: "one") == nil)
}

@Test func readSummaryReadsOnlySummaryMd() throws {
    let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let lib = library(root)
    let m = kickoff()
    try lib.save(m)
    #expect(library(root).readSummary(id: m.id) == "Agreed on scope.")
    #expect(library(root).readSummary(id: "no-such-meeting") == nil)
}
