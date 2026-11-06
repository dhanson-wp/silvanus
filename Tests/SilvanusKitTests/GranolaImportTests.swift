import Foundation
import Testing
@testable import SilvanusKit

/// The fictional archive in Tests/Fixtures/granola, found relative to this file.
private let archive = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Fixtures/granola")

private func scratch() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "silvanus-granola-\(UUID().uuidString)")
}

private func library(_ root: URL) -> MeetingLibrary {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    return MeetingLibrary(root: root, calendar: utc, trash: { try FileManager.default.removeItem(at: $0) })
}

private func imported(me: String = "Sam Rivera") throws -> (MeetingLibrary, GranolaImportResult, [String: Meeting]) {
    let lib = library(scratch())
    let result = GranolaImport.run(archive: archive, library: lib, me: me,
                                   now: Date(timeIntervalSince1970: 1_800_000_000))
    let byTitle = Dictionary(uniqueKeysWithValues: lib.loadAll().meetings.map { ($0.info.title, $0) })
    return (lib, result, byTitle)
}

@Test("The four fixture notes import with no failures")
func countsImported() throws {
    let (_, result, byTitle) = try imported()
    #expect(result == GranolaImportResult(imported: 4, skipped: 0))
    #expect(result.summary == "imported 4, skipped 0, failed 0")
    #expect(Set(byTitle.keys) == ["Acme kickoff", "Globex weekly", "Initech retro", "Hooli planning"])
}

@Test("Fields map onto the meeting")
func fieldMapping() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Acme kickoff"])
    #expect(m.info.source == "granola")
    #expect(m.info.granolaID == "not_AcmeKickoff0001")
    #expect(m.info.start == Date(timeIntervalSince1970: 1_773_154_800))  // 2026-03-10 15:00 UTC
    #expect(m.info.end == m.info.start.addingTimeInterval(1800))
    // The owner is left out; a guest with no name shows the email.
    #expect(m.info.attendees == ["Priya Natarajan", "jordan.lee@example.com"])
    #expect(m.info.speakers == ["me": "Sam Rivera", "them": "Them"])
    #expect(m.info.asr == nil)
    #expect(m.notes == "Agenda\n- scope\n- dates\n")
    // No audio is imported.
    let folder = try #require(lib.folderURL(for: m.id))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: MeetingFolder.audio).path))
}

@Test("The summary sits under Imported summary and notes stay verbatim")
func summaryAndNotes() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Acme kickoff"])
    #expect(m.summary.hasPrefix("## Imported summary\n\n### Decisions"))
    #expect(m.summary.hasSuffix("- Sam sends the plan\n"))
    let folder = try #require(lib.folderURL(for: m.id))
    let onDisk = try String(contentsOf: folder.appending(path: "summary.md"), encoding: .utf8)
    #expect(onDisk == m.summary)
}

@Test("Microphone is me and system audio is Them, with words spread over each segment")
func speakersAndWords() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Acme kickoff"])
    let folder = try #require(lib.folderURL(for: m.id))
    let data = try Data(contentsOf: folder.appending(path: "transcript.json"))
    let t = try MeetingInfo.decoder().decode(Transcript.self, from: data)
    // The blank segment is dropped.
    #expect(t.lines.map(\.side) == [.me, .them, .me])
    #expect(t.engine == "granola")
    let first = t.lines[0]
    #expect(first.words.count == 9)
    #expect(first.start == 0)  // times count from the first segment
    #expect(abs(first.end - 6) < 1e-9)
    #expect(first.words.allSatisfy { $0.confidence == 1 })
    #expect(abs(first.words[1].start - first.words[0].end) < 1e-9)
    #expect(abs(first.words[0].end - 6.0 / 9) < 1e-9)
    #expect(abs(t.lines[1].start - 7) < 1e-9)
    #expect(first.text == "Thanks for joining everyone, let's start with the plan.")
}

@Test("transcript.md uses the me name from the caller")
func importedTranscriptMarkdown() throws {
    let (_, _, byTitle) = try imported(me: "Sam Rivera")
    let md = try #require(byTitle["Acme kickoff"]).transcriptMarkdown
    #expect(md.hasPrefix("[00:00] **Sam Rivera:** Thanks for joining"))
    #expect(md.contains("[00:07] **Them:** Happy to be here."))
    #expect(md.contains("[00:15] **Sam Rivera:** Great, send the dates over."))
    let (_, _, plain) = try imported(me: "Me")
    let plainMD = try #require(plain["Acme kickoff"]).transcriptMarkdown
    #expect(plainMD.hasPrefix("[00:00] **Me:**"))
}

@Test("Folders come from the note or from folders.json, by name")
func folders() throws {
    let (_, _, byTitle) = try imported()
    #expect(byTitle["Acme kickoff"]?.info.folder == "Clients")   // folder_membership
    #expect(byTitle["Globex weekly"]?.info.folder == "Clients")  // folders.json, meeting_ids form, matched by web_url UUID
    #expect(byTitle["Initech retro"]?.info.folder == "Internal") // folders.json, list form, matched by id
}

@Test("A meeting with no transcript, notes, or summary still imports and opens empty")
func emptyMeeting() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Globex weekly"])
    #expect(m.notes.isEmpty && m.summary.isEmpty && m.transcriptMarkdown.isEmpty)
    #expect(m.info.attendees.isEmpty)
    #expect(m.info.start == Date(timeIntervalSince1970: 1_773_252_000))  // created_at, no calendar event
    let folder = try #require(lib.folderURL(for: m.id))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "transcript.json").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "transcript.md").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "summary.md").path))
    // It reloads cleanly.
    #expect(library(lib.root).loadAll().unreadable.isEmpty)
}

@Test("The MCP variant imports like an API note")
func mcpVariant() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Initech retro"])
    #expect(m.info.granolaID == "11111111-2222-4333-8444-555555555553")
    #expect(m.notes == "Retro notes\n")
    #expect(m.summary.contains("Imported summary") && m.summary.contains("shorten the sprint"))
    let folder = try #require(lib.folderURL(for: m.id))
    let t = try MeetingInfo.decoder().decode(
        Transcript.self, from: Data(contentsOf: folder.appending(path: "transcript.json")))
    #expect(t.lines.map(\.side) == [.me, .them])
}

@Test("Running the import twice adds nothing the second time")
func idempotent() throws {
    let lib = library(scratch())
    _ = GranolaImport.run(archive: archive, library: lib)
    // A fresh library on the same folder, like a new launch.
    let again = GranolaImport.run(archive: archive, library: library(lib.root))
    #expect(again == GranolaImportResult(imported: 0, skipped: 4))
    #expect(lib.loadAll().meetings.count == 4)
}

@Test("A file that isn't a note is reported by name and the rest still import")
func failuresAreReported() throws {
    let dir = scratch()
    let raw = dir.appending(path: "raw")
    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: archive.appending(path: "raw/not_AcmeKickoff0001.json"),
                                     to: raw.appending(path: "not_AcmeKickoff0001.json"))
    try Data("not json".utf8).write(to: raw.appending(path: "not_Broken.json"))
    try Data("{}".utf8).write(to: raw.appending(path: "not_Empty.json"))
    let result = GranolaImport.run(archive: dir, library: library(scratch()))
    #expect(result.imported == 1)
    #expect(result.failed == ["not_Broken.json", "not_Empty.json"])
    #expect(result.failures.map(\.reason) == ["not a JSON object", "no note in the file"])
    #expect(result.summary == "imported 1, skipped 0, failed 2")
}

@Test("A note with no usable start time fails with a reason")
func noStartFails() throws {
    let dir = scratch()
    let raw = dir.appending(path: "raw")
    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
    try Data(#"{"note": {"id": "not_NoStart", "title": "Floating"}, "transcript": []}"#.utf8)
        .write(to: raw.appending(path: "not_NoStart.json"))
    let lib = library(scratch())
    let result = GranolaImport.run(archive: dir, library: lib)
    #expect(result.imported == 0)
    #expect(result.failures.count == 1 && result.failures[0].file == "not_NoStart.json")
    #expect(result.failures[0].reason.hasPrefix("no start time"))
    #expect(lib.loadAll().meetings.isEmpty)
}

@Test("MCP field names map: meeting_at, known_participants, string speakers, start and end")
func mcpFieldNames() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Hooli planning"])
    #expect(m.info.start == Date(timeIntervalSince1970: 1_772_989_200))  // 2026-03-08 17:00 UTC
    #expect(m.info.attendees == ["Jordan Lee", "Priya Natarajan", "casey.ng@example.com"])
    #expect(m.notes == "Budget first\n")
    #expect(m.summary.hasPrefix("## Imported summary\n\nBudget approved"))
    let folder = try #require(lib.folderURL(for: m.id))
    let t = try MeetingInfo.decoder().decode(
        Transcript.self, from: Data(contentsOf: folder.appending(path: "transcript.json")))
    #expect(t.lines.map(\.side) == [.me, .them])
    #expect(t.lines[1].start == 5)
}

private struct Boom: Error {}

@Test("A failed transcript write leaves no folder, and a re-run imports the meeting")
func allOrNothing() throws {
    let root = scratch()
    let lib = library(root)
    let failed = GranolaImport.run(archive: archive, library: lib, writeTranscript: { _, _ in throw Boom() })
    // Only Globex weekly has no transcript to write; the other three fail whole.
    #expect(failed.imported == 1)
    #expect(failed.failures.count == 3)
    // No half-written folder remains.
    let series = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "meetings").path).sorted()
    #expect(series == ["Globex weekly"])
    let again = GranolaImport.run(archive: archive, library: library(root))
    #expect(again == GranolaImportResult(imported: 3, skipped: 1))
}

private func writeNote(_ dir: URL, file: String, id: String, title: String, created: String) throws {
    let raw = dir.appending(path: "raw")
    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
    let json = #"{"note": {"id": "\#(id)", "title": "\#(title)", "created_at": "\#(created)"}, "transcript": []}"#
    try Data(json.utf8).write(to: raw.appending(path: file))
}

@Test("Two notes with the same title in the same minute both import")
func sameTitleSameMinute() throws {
    let dir = scratch()
    try writeNote(dir, file: "not_A.json", id: "not_A", title: "Acme sync", created: "2026-03-10T15:00:05Z")
    try writeNote(dir, file: "not_B.json", id: "not_B", title: "Acme sync", created: "2026-03-10T15:00:40Z")
    let lib = library(scratch())
    let result = GranolaImport.run(archive: dir, library: lib)
    #expect(result == GranolaImportResult(imported: 2, skipped: 0))
    let all = lib.loadAll().meetings
    #expect(all.count == 2)
    #expect(Set(all.compactMap { lib.folderURL(for: $0.id) }).count == 2)
}

@Test("The same granola_id as an API note and an MCP file imports once, API first")
func apiWinsOverMCP() throws {
    let dir = scratch()
    try writeNote(dir, file: "not_X.mcp.json", id: "not_X", title: "From MCP", created: "2026-03-10T15:00:00Z")
    try writeNote(dir, file: "not_X.json", id: "not_X", title: "From API", created: "2026-03-10T15:00:00Z")
    let lib = library(scratch())
    let result = GranolaImport.run(archive: dir, library: lib)
    #expect(result == GranolaImportResult(imported: 1, skipped: 1))
    #expect(lib.loadAll().meetings.map(\.info.title) == ["From API"])
}

@Test("Lines with equal start times keep their original order")
func stableOrder() throws {
    let dir = scratch()
    let raw = dir.appending(path: "raw")
    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
    let seg = { (who: String, text: String) in
        #"{"text": "\#(text)", "start_time": "2026-03-10T15:00:00Z", "end_time": "2026-03-10T15:00:04Z", "speaker": {"source": "\#(who)"}}"#
    }
    let json = #"{"note": {"id": "not_S", "title": "Tie", "created_at": "2026-03-10T15:00:00Z"}, "transcript": ["#
        + [seg("system", "one"), seg("microphone", "two"), seg("system", "three")].joined(separator: ",") + "]}"
    try Data(json.utf8).write(to: raw.appending(path: "not_S.json"))
    let lib = library(scratch())
    _ = GranolaImport.run(archive: dir, library: lib)
    let m = try #require(lib.loadAll().meetings.first)
    let folder = try #require(lib.folderURL(for: m.id))
    let t = try MeetingInfo.decoder().decode(
        Transcript.self, from: Data(contentsOf: folder.appending(path: "transcript.json")))
    #expect(t.lines.map(\.text) == ["one", "two", "three"])
}
