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

@Test("The three fixture notes import with no failures")
func countsImported() throws {
    let (_, result, byTitle) = try imported()
    #expect(result == GranolaImportResult(imported: 3, skipped: 0, failed: []))
    #expect(result.summary == "imported 3, skipped 0, failed 0")
    #expect(Set(byTitle.keys) == ["Acme kickoff", "Globex weekly", "Initech retro"])
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
    #expect(again == GranolaImportResult(imported: 0, skipped: 3, failed: []))
    #expect(lib.loadAll().meetings.count == 3)
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
    #expect(result.summary == "imported 1, skipped 0, failed 2")
}
