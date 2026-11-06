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

@Test("The six fixture notes import with no failures")
func countsImported() throws {
    let (_, result, byTitle) = try imported()
    #expect(result == GranolaImportResult(imported: 6, skipped: 0))
    #expect(result.summary == "imported 6, skipped 0, failed 0")
    #expect(Set(byTitle.keys) == ["Acme kickoff", "Globex weekly", "Initech retro", "Hooli planning",
                                    "Acme renewal call", "Globex intro"])
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
    #expect(again == GranolaImportResult(imported: 0, skipped: 6))
    #expect(lib.loadAll().meetings.count == 6)
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
    // Globex weekly and Globex intro have no transcript to write; the other four fail whole.
    #expect(failed.imported == 2)
    #expect(failed.failures.count == 4)
    // No half-written folder remains.
    let series = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "meetings").path).sorted()
    #expect(series == ["Globex intro", "Globex weekly"])
    let again = GranolaImport.run(archive: archive, library: library(root))
    #expect(again == GranolaImportResult(imported: 4, skipped: 2))
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

// MARK: - Gap notes (mcp-gaps/) and mcp-folders.json

private func transcript(of m: Meeting, in lib: MeetingLibrary) throws -> Transcript {
    let folder = try #require(lib.folderURL(for: m.id))
    return try MeetingInfo.decoder().decode(Transcript.self, from: Data(contentsOf: folder.appending(path: "transcript.json")))
}

@Test("A gap note maps uuid, start with milliseconds and offset, end, notes, and summary")
func gapFields() throws {
    let (_, _, byTitle) = try imported()
    let m = try #require(byTitle["Acme renewal call"])
    #expect(m.info.granolaID == "aaaaaaaa-1111-4222-8333-444444444441")
    #expect(m.info.source == "granola")
    #expect(m.info.start == Date(timeIntervalSince1970: 1_772_641_800))  // 2026-03-04 16:30 UTC
    #expect(m.info.end == m.info.start.addingTimeInterval(3740))         // last line is [1:02:20]
    #expect(m.info.attendees == ["Sam Rivera", "Jordan Lee"])
    #expect(m.notes == "Renewal terms\n")
    #expect(m.summary == "## Imported summary\n\nAcme will renew for a year.\n")
}

@Test("Gap transcript lines: mic and Me are me, the rest Them; times spread to the next line")
func gapTranscript() throws {
    let (lib, _, byTitle) = try imported()
    let t = try transcript(of: try #require(byTitle["Acme renewal call"]), in: lib)
    #expect(t.lines.map(\.side) == [.me, .them, .them, .me])
    #expect(t.lines[0].start == 5)
    #expect(abs(t.lines[0].end - 13) < 1e-9)
    #expect(t.lines[0].words.count == 5)
    #expect(t.lines[0].words.allSatisfy { $0.confidence == 1 })
    #expect(abs(t.lines[0].words[0].end - (5 + 8.0 / 5)) < 1e-9)
    #expect(t.lines[2].start == 3730)  // [1:02:10]
    // Last line: 3 s per 8 words (6 words here).
    #expect(abs(t.lines[3].end - (3740 + 6.0 / 8 * 3)) < 1e-9)
    #expect(t.lines[3].text == "Understood, I will send a quote.")
}

@Test("A named 1:1 keeps the other person's name as the them speaker")
func gapNamedOneToOne() throws {
    let (_, _, byTitle) = try imported()
    let m = try #require(byTitle["Acme renewal call"])
    #expect(m.info.speakers == ["me": "Sam Rivera", "them": "Jordan Lee"])
    #expect(m.transcriptMarkdown.contains("**Jordan Lee:** Glad to."))
    #expect(m.transcriptMarkdown.contains("[1:02:10] **Jordan Lee:** One more thing about pricing"))
}

@Test("Generic or mixed them speakers fall back to Them")
func gapGenericSpeakers() throws {
    let dir = scratch()
    let gaps = dir.appending(path: "mcp-gaps")
    try FileManager.default.createDirectory(at: gaps, withIntermediateDirectories: true)
    func gap(_ uuid: String, _ transcript: String) throws {
        let body = ["uuid": uuid, "title": "T \(uuid)", "meeting_at": "2026-03-04T10:30:00.000-06:00",
                    "attendees": [] as [String], "transcript": transcript, "transcript_status": "x", "source": "mcp"] as [String: Any]
        try JSONSerialization.data(withJSONObject: body).write(to: gaps.appending(path: "\(uuid).json"))
    }
    try gap("g1", "[0:01] System audio: hi there\n[0:04] Microphone: hello")
    try gap("g2", "[0:01] Jordan Lee: hi there\n[0:04] Priya Natarajan: hello")
    let lib = library(scratch())
    let result = GranolaImport.run(archive: dir, library: lib)
    #expect(result == GranolaImportResult(imported: 2, skipped: 0))
    for m in lib.loadAll().meetings { #expect(m.info.speakers["them"] == "Them") }
}

@Test("A gap note with an empty transcript and string attendees imports with no transcript files")
func gapEmptyTranscript() throws {
    let (lib, _, byTitle) = try imported()
    let m = try #require(byTitle["Globex intro"])
    #expect(m.info.attendees == ["Priya Natarajan", "Jordan Lee", "Sam Rivera"])
    #expect(m.info.end == nil)
    #expect(m.notes.isEmpty && m.summary.isEmpty && m.transcriptMarkdown.isEmpty)
    let folder = try #require(lib.folderURL(for: m.id))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "transcript.json").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "transcript.md").path))
}

@Test("Attendee strings split on commas and and")
func attendeeSplitting() {
    #expect(RawNote.splitNames("A One, B Two, and C Three") == ["A One", "B Two", "C Three"])
    #expect(RawNote.splitNames("A One and B Two") == ["A One", "B Two"])
    #expect(RawNote.splitNames("") == [])
}

@Test("mcp-folders.json files gap and API meetings by UUID; a note's own folder wins")
func mcpFolders() throws {
    let (_, _, byTitle) = try imported()
    #expect(byTitle["Acme renewal call"]?.info.folder == "Clients")
    #expect(byTitle["Globex intro"]?.info.folder == "Prospects")
    #expect(byTitle["Hooli planning"]?.info.folder == "Prospects")  // API-side id, found in mcp-folders.json
    #expect(byTitle["Acme kickoff"]?.info.folder == "Clients")      // its own folder_membership
}

@Test("An API note wins over a gap note with the same UUID")
func apiWinsOverGap() throws {
    let dir = scratch()
    try FileManager.default.createDirectory(at: dir.appending(path: "raw"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.appending(path: "mcp-gaps"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: archive.appending(path: "raw/not_GlobexWeekly0002.json"),
                                     to: dir.appending(path: "raw/not_GlobexWeekly0002.json"))
    let uuid = "11111111-2222-4333-8444-555555555552"
    let gap = #"{"uuid": "\#(uuid)", "title": "From gap", "meeting_at": "2026-03-04T10:30:00.000-06:00", "attendees": [], "transcript": ""}"#
    try Data(gap.utf8).write(to: dir.appending(path: "mcp-gaps/\(uuid).json"))
    let lib = library(scratch())
    let result = GranolaImport.run(archive: dir, library: lib)
    #expect(result == GranolaImportResult(imported: 1, skipped: 1))
    #expect(lib.loadAll().meetings.map(\.info.title) == ["Globex weekly"])
}

@Test("A gap note with no uuid or no meeting_at fails with a reason")
func gapFailures() throws {
    let dir = scratch()
    let gaps = dir.appending(path: "mcp-gaps")
    try FileManager.default.createDirectory(at: gaps, withIntermediateDirectories: true)
    try Data(#"{"title": "No id", "meeting_at": "2026-03-04T10:30:00.000-06:00"}"#.utf8).write(to: gaps.appending(path: "a.json"))
    try Data(#"{"uuid": "u2", "title": "No time"}"#.utf8).write(to: gaps.appending(path: "b.json"))
    let result = GranolaImport.run(archive: dir, library: library(scratch()))
    #expect(result.failed == ["a.json", "b.json"])
    #expect(result.failures[0].reason.hasPrefix("no uuid"))
    #expect(result.failures[1].reason.hasPrefix("no start time"))
}

// MARK: - Never import a meeting twice; parser edge cases

private func gapArchive(_ transcripts: [String: String]) throws -> URL {
    let dir = scratch()
    let gaps = dir.appending(path: "mcp-gaps")
    try FileManager.default.createDirectory(at: gaps, withIntermediateDirectories: true)
    for (uuid, transcript) in transcripts {
        let body = ["uuid": uuid, "title": "T \(uuid)", "meeting_at": "2026-03-04T10:30:00.000-06:00",
                    "attendees": [] as [String], "transcript": transcript] as [String: Any]
        try JSONSerialization.data(withJSONObject: body).write(to: gaps.appending(path: "\(uuid).json"))
    }
    return dir
}

private func apiArchive() throws -> URL {
    let dir = scratch()
    try FileManager.default.createDirectory(at: dir.appending(path: "raw"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: archive.appending(path: "raw/not_GlobexWeekly0002.json"),
                                     to: dir.appending(path: "raw/not_GlobexWeekly0002.json"))
    return dir
}

private let globexUUID = "11111111-2222-4333-8444-555555555552"

@Test("A gap imported first, then the API note with the same UUID in a later run, imports once")
func gapThenAPI() throws {
    let lib = library(scratch())
    let gap = try gapArchive([globexUUID.uppercased(): ""])
    #expect(runGranola(gap, lib) == GranolaImportResult(imported: 1, skipped: 0))
    let m = try #require(lib.loadAll().meetings.first)
    #expect(m.info.granolaUUID == globexUUID)
    #expect(runGranola(try apiArchive(), library(lib.root)) == GranolaImportResult(imported: 0, skipped: 1))
    #expect(lib.loadAll().meetings.count == 1)
}

@Test("An API note imported first, then a gap with the same UUID in a later run, imports once")
func apiThenGap() throws {
    let lib = library(scratch())
    #expect(runGranola(try apiArchive(), lib) == GranolaImportResult(imported: 1, skipped: 0))
    #expect(try #require(lib.loadAll().meetings.first).info.granolaUUID == globexUUID)
    #expect(runGranola(try gapArchive([globexUUID: ""]), library(lib.root)) == GranolaImportResult(imported: 0, skipped: 1))
    #expect(lib.loadAll().meetings.count == 1)
}

private func runGranola(_ dir: URL, _ lib: MeetingLibrary, me: String = "Me") -> GranolaImportResult {
    GranolaImport.run(archive: dir, library: lib, me: me)
}

private func gapTranscript(_ text: String, me: String = "Me") throws -> (Meeting, Transcript?) {
    let lib = library(scratch())
    _ = GranolaImport.run(archive: try gapArchive(["g1": text]), library: lib, me: me)
    let m = try #require(lib.loadAll().meetings.first)
    let folder = try #require(lib.folderURL(for: m.id))
    let data = try? Data(contentsOf: folder.appending(path: "transcript.json"))
    return (m, data.flatMap { try? MeetingInfo.decoder().decode(Transcript.self, from: $0) })
}

@Test("The user's own name in a gap transcript is the me side, case-insensitively")
func gapOwnName() throws {
    let (m, t) = try gapTranscript("[0:01] sam rivera: hello there\n[0:04] Jordan Lee: hi", me: "Sam Rivera")
    #expect(try #require(t).lines.map(\.side) == [.me, .them])
    #expect(m.info.speakers == ["me": "Sam Rivera", "them": "Jordan Lee"])
}

@Test("A leading untimestamped line becomes a line at 0 and a continuation joins the line before")
func gapLeadingAndContinuation() throws {
    let (_, t) = try gapTranscript("Preamble words\n[0:05] Jordan Lee: first part\nsecond part\n[0:09] Me: end")
    let lines = try #require(t).lines
    #expect(lines.map(\.text) == ["Preamble words", "first part second part", "end"])
    #expect(lines[0].start == 0 && lines[0].side == .them)
}

@Test("Me: or Microphone: with nothing after it is a speaker line that a continuation fills")
func gapEmptySpeakerText() throws {
    let (_, t) = try gapTranscript("[0:01] Microphone:\nhello from the mic\n[0:05] Jordan Lee: hi")
    let lines = try #require(t).lines
    #expect(lines.map(\.side) == [.me, .them])
    #expect(lines[0].text == "hello from the mic")
}

@Test("Out-of-order stamps are sorted before times are spread")
func gapOutOfOrder() throws {
    let (_, t) = try gapTranscript("[0:10] Jordan Lee: later words\n[0:02] Me: earlier words here")
    let lines = try #require(t).lines
    #expect(lines.map(\.text) == ["earlier words here", "later words"])
    #expect(lines[0].end == 10 && lines.allSatisfy { $0.end >= $0.start })
}

@Test("CRLF line endings, a colon in a speaker name, and a stamp inside the text")
func gapOddText() throws {
    let (m, t) = try gapTranscript("[0:01] Jordan Lee (Acme: Sales): Agenda: see [1:23] on the deck\r\n[0:09] Me: ok\r\n")
    let lines = try #require(t).lines
    #expect(lines.map(\.text) == ["Agenda: see [1:23] on the deck", "ok"])
    #expect(m.info.speakers["them"] == "Jordan Lee (Acme: Sales)")
}
