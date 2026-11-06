import Foundation

/// What an import run did.
public struct GranolaImportResult: Equatable, Sendable {
    public var imported = 0
    public var skipped = 0
    /// File names (not paths) of the notes that could not be read.
    public var failed: [String] = []

    public var summary: String { "imported \(imported), skipped \(skipped), failed \(failed.count)" }
}

/// Imports the Granola archive (see docs/MIGRATION.md) into meeting folders.
///
/// The archive is `<dir>/raw/*.json` (one lossless API note per file, or an
/// `*.mcp.json` file written by the reconcile pass) and an optional
/// `<dir>/folders.json`. Each note becomes a meeting with `source: granola`
/// and its `granola_id`; a note whose id is already in the library is skipped,
/// so a re-run adds only what is new.
public enum GranolaImport {
    public static let importedSummaryHeading = "## Imported summary"

    /// Imports every note in `archive` that the library doesn't have yet.
    /// `me` names the microphone side in the readable transcript.
    public static func run(archive: URL, library: MeetingLibrary, me: String = "Me",
                           now: Date = .now) -> GranolaImportResult {
        var result = GranolaImportResult()
        var known = Set(library.loadAll().meetings.compactMap(\.info.granolaID))
        let folders = FolderIndex(file: archive.appending(path: "folders.json"))
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: archive.appending(path: "raw"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in files {
            guard let note = try? RawNote(file: file) else {
                result.failed.append(file.lastPathComponent)
                continue
            }
            if known.contains(note.id) {
                result.skipped += 1
                continue
            }
            do {
                let (meeting, transcript) = note.meeting(me: me, folder: folders.name(for: note), now: now)
                let folder = try library.save(meeting)
                if let transcript {
                    try MeetingInfo.encoder().encode(transcript)
                        .write(to: folder.appending(path: MeetingFolder.transcriptJSON), options: .atomic)
                }
                known.insert(note.id)
                result.imported += 1
            } catch {
                result.failed.append(file.lastPathComponent)
            }
        }
        return result
    }

    /// Splits a segment's text on whitespace and spreads the words evenly
    /// across `start...end`. Confidence is 1: Granola gives none.
    static func words(_ text: String, start: TimeInterval, end: TimeInterval) -> [Word] {
        let pieces = text.split(whereSeparator: \.isWhitespace)
        guard !pieces.isEmpty else { return [] }
        let step = max(end - start, 0) / Double(pieces.count)
        return pieces.enumerated().map { i, w in
            Word(text: String(w), start: start + Double(i) * step, end: start + Double(i + 1) * step)
        }
    }
}

// MARK: - Reading the archive

/// One raw note: the envelope `{note, transcript}` the exporter writes.
struct RawNote {
    enum ReadError: Error { case notJSON, noNote }

    let id: String
    let uuid: String?
    let title: String
    let start: Date
    let end: Date?
    let attendees: [String]
    let folderNames: [String]
    let privateNotes: String
    let summary: String
    let segments: [Segment]

    struct Segment {
        var text: String
        var start: Date?
        var end: Date?
        var isMe: Bool
    }

    init(file: URL) throws {
        let data = try Data(contentsOf: file)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.notJSON }
        // The envelope has "note"; a bare note (the MCP variant may be one) is the root itself.
        let note = (root["note"] as? [String: Any]) ?? root
        var stem = file.deletingPathExtension().lastPathComponent
        if stem.hasSuffix(".mcp") { stem.removeLast(4) }
        // A note has an id, a title, or a creation time; a stray JSON object has none of them.
        guard note["id"] != nil || note["title"] != nil || note["created_at"] != nil else { throw ReadError.noNote }
        let id = (note["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? stem
        self.id = id

        let webURL = note["web_url"] as? String ?? ""
        uuid = webURL.range(of: "/d/[0-9a-fA-F-]{36}", options: .regularExpression)
            .map { String(webURL[$0].dropFirst(3)).lowercased() }

        let event = note["calendar_event"] as? [String: Any]
        func str(_ d: [String: Any]?, _ key: String) -> String? {
            (d?[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let rawTitle = str(note, "title") ?? str(event, "event_title") ?? ""
        title = MeetingTitle.clean(rawTitle)

        segments = ((root["transcript"] ?? note["transcript"]) as? [[String: Any]] ?? []).compactMap { seg in
            let text = (seg["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let speaker = seg["speaker"] as? [String: Any]
            let source = (speaker?["source"] as? String ?? "").lowercased()
            let me = source.contains("mic") || (speaker?["attribution"] as? String) == "me"
            return Segment(text: text, start: Self.date(str(seg, "start_time")),
                           end: Self.date(str(seg, "end_time")), isMe: me)
        }

        let firstStart = segments.compactMap(\.start).min()
        start = Self.date(str(event, "scheduled_start_time")) ?? Self.date(str(note, "created_at"))
            ?? firstStart ?? Date(timeIntervalSince1970: 0)
        end = Self.date(str(event, "scheduled_end_time")) ?? segments.compactMap(\.end).max()

        let ownerEmail = ((note["owner"] as? [String: Any])?["email"] as? String ?? "").lowercased()
        attendees = (note["attendees"] as? [[String: Any]] ?? []).compactMap { a in
            if let email = str(a, "email"), email.lowercased() == ownerEmail { return nil }
            return str(a, "name") ?? str(a, "email")
        }
        folderNames = (note["folder_membership"] as? [[String: Any]] ?? []).compactMap { str($0, "name") }
        privateNotes = note["private_notes_markdown"] as? String ?? ""
        summary = (note["summary_markdown"] as? String ?? note["summary_text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The meeting, and its transcript when there is anything to say.
    func meeting(me: String, folder: String?, now: Date) -> (Meeting, Transcript?) {
        // Segment times are absolute; the transcript counts from the first one.
        let t0 = segments.compactMap(\.start).min()
        var lines: [TranscriptLine] = []
        var cursor: TimeInterval = 0
        for seg in segments {
            let s = seg.start.flatMap { t0.map($0.timeIntervalSince) } ?? cursor
            let e = max(seg.end.flatMap { t0.map($0.timeIntervalSince) } ?? s, s)
            let words = GranolaImport.words(seg.text, start: s, end: e)
            guard !words.isEmpty else { continue }
            lines.append(TranscriptLine(side: seg.isMe ? .me : .them, words: words))
            cursor = e
        }
        lines.sort { $0.start < $1.start }
        let transcript = lines.isEmpty ? nil : Transcript(lines: lines, engine: "granola", processedAt: now)

        let info = MeetingInfo(
            title: title, start: start, end: end, attendees: attendees,
            folder: folderNames.first ?? folder, source: "granola", granolaID: id,
            speakers: ["me": me, "them": "Them"])
        let summaryText = summary.isEmpty ? "" : "\(GranolaImport.importedSummaryHeading)\n\n\(summary)\n"
        return (Meeting(info: info, notes: privateNotes, summary: summaryText,
                        transcriptMarkdown: transcript.map { $0.markdown(me: me) + "\n" } ?? ""),
                transcript)
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}

/// `folders.json`: folder name to meeting ids, either as a list or as
/// `{"meeting_ids": [...]}` (the shape reconcile.py reads). Ids are Granola
/// `not_` ids or the UUIDs from the note's `web_url`.
struct FolderIndex {
    private var byID: [String: String] = [:]

    init(file: URL) {
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            let ids = (value as? [String]) ?? ((value as? [String: Any])?["meeting_ids"] as? [String]) ?? []
            for id in ids where byID[id.lowercased()] == nil { byID[id.lowercased()] = name }
        }
    }

    func name(for note: RawNote) -> String? {
        byID[note.id.lowercased()] ?? note.uuid.flatMap { byID[$0] }
    }
}
