import Foundation

/// What an import run did.
public struct GranolaImportResult: Equatable, Sendable {
    public var imported = 0
    public var skipped = 0
    /// The notes that could not be imported, each with the reason.
    public var failures: [Failure] = []

    public struct Failure: Equatable, Sendable {
        /// The file's name (not its path).
        public var file: String
        public var reason: String
    }

    public var failed: [String] { failures.map(\.file) }
    public var summary: String { "imported \(imported), skipped \(skipped), failed \(failures.count)" }
}

/// Imports the Granola archive (see docs/MIGRATION.md) into meeting folders.
///
/// The archive is `<dir>/raw/*.json` (one lossless API note per file, or an
/// `*.mcp.json` file written by the reconcile pass), `<dir>/mcp-gaps/<uuid>.json`
/// (notes the API skipped), and optional `<dir>/folders.json` and `<dir>/mcp-folders.json`. Each note becomes a meeting with `source: granola`
/// and its `granola_id`; a note whose id is already in the library is skipped,
/// so a re-run adds only what is new.
public enum GranolaImport {
    public static let importedSummaryHeading = "## Imported summary"

    /// Imports every note in `archive` that the library doesn't have yet.
    /// `me` names the microphone side in the readable transcript. Each meeting
    /// is written whole or not at all: if any file fails, the folder is removed.
    /// `writeTranscript` is the seam tests use to force a failure.
    public static func run(archive: URL, library: MeetingLibrary, me: String = "Me", now: Date = .now,
                           writeTranscript: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) })
        -> GranolaImportResult {
        var result = GranolaImportResult()
        // Both a note's own id and its UUID, so a gap note and the API note for the
        // same meeting are never imported twice, in either order or across runs.
        var known = Set(library.loadAll().meetings.flatMap { [$0.info.granolaID, $0.info.granolaUUID] }
            .compactMap { $0?.lowercased() })
        let folders = FolderIndex(files: [archive.appending(path: "folders.json"),
                                          archive.appending(path: "mcp-folders.json")])
        func jsonFiles(_ sub: String) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(
                at: archive.appending(path: sub), includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
        }
        // API notes first, then .mcp.json files, then the gap notes, so when
        // two exports have a note the earlier one wins.
        let raw = jsonFiles("raw").sorted {
            let a = $0.lastPathComponent.hasSuffix(".mcp.json"), b = $1.lastPathComponent.hasSuffix(".mcp.json")
            return a != b ? !a : $0.lastPathComponent < $1.lastPathComponent
        }
        let gaps = jsonFiles("mcp-gaps").sorted { $0.lastPathComponent < $1.lastPathComponent }
        let files = raw.map { ($0, false) } + gaps.map { ($0, true) }

        for (file, isGap) in files {
            let name = file.lastPathComponent
            let note: RawNote
            do { note = try isGap ? RawNote(gapFile: file) : RawNote(file: file) } catch {
                result.failures.append(.init(file: name, reason: describe(error)))
                continue
            }
            let keys = [note.id.lowercased(), note.uuid?.lowercased()].compactMap { $0 }
            if keys.contains(where: known.contains) {
                result.skipped += 1
                continue
            }
            let (meeting, transcript) = note.meeting(me: me, folder: folders.name(for: note), now: now)
            do {
                let folder = try library.save(meeting)
                if let transcript {
                    try writeTranscript(try MeetingInfo.encoder().encode(transcript),
                                        folder.appending(path: MeetingFolder.transcriptJSON))
                }
                known.formUnion(keys)
                result.imported += 1
            } catch {
                // Leave nothing behind, so a re-run imports it fresh.
                if let folder = library.folderURL(for: meeting.id) {
                    try? FileManager.default.removeItem(at: folder)
                    let series = folder.deletingLastPathComponent()
                    if (try? FileManager.default.contentsOfDirectory(atPath: series.path))?.isEmpty == true {
                        try? FileManager.default.removeItem(at: series)
                    }
                }
                result.failures.append(.init(file: name, reason: describe(error)))
            }
        }
        return result
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? RawNote.ReadError { return e.reason }
        return error.localizedDescription
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
    enum ReadError: Error {
        case notJSON, noNote, noStart, noUUID
        var reason: String {
            switch self {
            case .noUUID: "no uuid in the gap note"
            case .notJSON: "not a JSON object"
            case .noNote: "no note in the file"
            case .noStart: "no start time (no scheduled start, meeting_at, created_at, or transcript)"
            }
        }
    }

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
    /// Gap notes carry their transcript as parsed lines (times from the start), sorted by time.
    var gapLines: [GapLine]?

    struct GapLine {
        var stamp: TimeInterval
        var speaker: String
        var text: String
    }

    struct Segment {
        var text: String
        var start: Date?
        var end: Date?
        var isMe: Bool
    }

    init(file: URL) throws {
        let data = try Data(contentsOf: file)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ReadError.notJSON }
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
            // API: speaker is {source, attribution}. MCP: speaker is "Microphone" or "System audio".
            let speaker = seg["speaker"] as? [String: Any]
            let source = (speaker?["source"] as? String ?? seg["speaker"] as? String ?? "").lowercased()
            let me = source.contains("mic") || (speaker?["attribution"] as? String) == "me"
            return Segment(text: text, start: Self.date(str(seg, "start_time") ?? str(seg, "start")),
                           end: Self.date(str(seg, "end_time") ?? str(seg, "end")), isMe: me)
        }

        let firstStart = segments.compactMap(\.start).min()
        guard let start = Self.date(str(event, "scheduled_start_time")) ?? Self.date(str(note, "meeting_at"))
                ?? Self.date(str(note, "created_at")) ?? firstStart else { throw ReadError.noStart }
        self.start = start
        end = Self.date(str(event, "scheduled_end_time")) ?? segments.compactMap(\.end).max()

        let ownerEmail = ((note["owner"] as? [String: Any])?["email"] as? String ?? "").lowercased()
        // API: attendees [{name, email}]. MCP: known_participants, objects or plain strings.
        let people = (note["attendees"] ?? note["known_participants"]) as? [Any] ?? []
        attendees = people.compactMap { person in
            if let text = person as? String { return text.isEmpty ? nil : text }
            guard let a = person as? [String: Any] else { return nil }
            if let email = str(a, "email"), email.lowercased() == ownerEmail { return nil }
            return str(a, "name") ?? str(a, "email")
        }
        folderNames = (note["folder_membership"] as? [[String: Any]] ?? []).compactMap { str($0, "name") }
        privateNotes = note["private_notes_markdown"] as? String ?? note["private_notes"] as? String ?? ""
        summary = (note["summary_markdown"] as? String ?? note["summary_text"] as? String ?? note["summary"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A note the API skipped: `mcp-gaps/<uuid>.json`.
    init(gapFile file: URL) throws {
        let data = try Data(contentsOf: file)
        guard let note = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ReadError.notJSON }
        func str(_ key: String) -> String? { (note[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        guard let uuid = str("uuid") else { throw ReadError.noUUID }
        guard let start = Self.date(str("meeting_at")) else { throw ReadError.noStart }
        id = uuid
        self.uuid = uuid.lowercased()
        title = MeetingTitle.clean(str("title") ?? "")
        self.start = start
        if let text = note["attendees"] as? String {
            attendees = Self.splitNames(text)
        } else {
            attendees = (note["attendees"] as? [Any] ?? []).compactMap { ($0 as? String).flatMap { $0.isEmpty ? nil : $0 } }
        }
        folderNames = []
        privateNotes = note["private_notes"] as? String ?? ""
        summary = (note["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        segments = []
        let parsed = Self.parseTranscript(note["transcript"] as? String ?? "")
        gapLines = parsed
        end = parsed.last.map { start.addingTimeInterval($0.stamp) }
    }

    /// "Sam Rivera, Priya Natarajan and Jordan Lee" to three names.
    static func splitNames(_ text: String) -> [String] {
        text.replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let genericSpeakers: Set<String> = ["them", "system audio", "system", "speaker", "unknown", "remote", "other"]
    private static let stampPattern = try! NSRegularExpression(pattern: #"^\[(\d+):(\d{2})(?::(\d{2}))?\]\s*(.*)$"#)

    /// Splits "Speaker: text" at the first ": " outside parentheses. A bare
    /// "Me:" or "Microphone:" with nothing after it is a speaker with no text yet.
    static func splitSpeaker(_ rest: String) -> (speaker: String, text: String) {
        var depth = 0
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c == "(" || c == "[" { depth += 1 } else if c == ")" || c == "]" { depth = max(0, depth - 1) }
            else if c == ":", depth == 0 {
                let next = rest.index(after: i)
                if next == rest.endIndex || rest[next] == " " {
                    return (String(rest[..<i]).trimmingCharacters(in: .whitespaces),
                            String(rest[next...]).trimmingCharacters(in: .whitespaces))
                }
            }
            i = rest.index(after: i)
        }
        return ("", rest)
    }

    /// Reads `[m:ss] Speaker: text` lines (`[h:mm:ss]` past an hour), sorted by
    /// time (ties keep their order). A line with no timestamp continues the one
    /// before it; before any timestamp it becomes a speakerless line at 0.
    static func parseTranscript(_ text: String) -> [GapLine] {
        var raws: [GapLine] = []
        for lineText in text.split(whereSeparator: \.isNewline) {
            let line = lineText.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            guard let m = stampPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                if raws.isEmpty { raws.append(GapLine(stamp: 0, speaker: "", text: line)) }
                else { raws[raws.count - 1].text += raws[raws.count - 1].text.isEmpty ? line : " " + line }
                continue
            }
            func group(_ i: Int) -> String? {
                m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
            }
            let a = Double(group(1) ?? "") ?? 0, b = Double(group(2) ?? "") ?? 0
            let stamp = group(3).map { a * 3600 + b * 60 + (Double($0) ?? 0) } ?? (a * 60 + b)
            let (speaker, body) = splitSpeaker(group(4) ?? "")
            raws.append(GapLine(stamp: stamp, speaker: speaker, text: body))
        }
        return raws.enumerated()
            .sorted { $0.element.stamp != $1.element.stamp ? $0.element.stamp < $1.element.stamp : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Turns parsed gap lines into transcript lines. The mic side is "Microphone",
    /// "Me", or the user's own name (`me`). The other side's name is kept only
    /// when every line from it has the same single, non-generic name.
    static func transcriptLines(_ raws: [GapLine], me: String) -> (lines: [TranscriptLine], themName: String?) {
        let mine = me.trimmingCharacters(in: .whitespaces).lowercased()
        var lines: [TranscriptLine] = []
        var themNames = Set<String>()
        for (i, r) in raws.enumerated() {
            let speaker = r.speaker.lowercased()
            let isMe = speaker == "microphone" || speaker == "me" || (!mine.isEmpty && speaker == mine)
            let count = r.text.split(whereSeparator: \.isWhitespace).count
            guard count > 0 else { continue }
            let end = max(i + 1 < raws.count ? raws[i + 1].stamp : r.stamp + Double(count) / 8 * 3, r.stamp)
            lines.append(TranscriptLine(side: isMe ? .me : .them,
                                        words: GranolaImport.words(r.text, start: r.stamp, end: end)))
            if !isMe { themNames.insert(r.speaker) }
        }
        var themName: String?
        if themNames.count == 1, let n = themNames.first, !n.isEmpty, !genericSpeakers.contains(n.lowercased()) {
            themName = n
        }
        return (lines, themName)
    }

    /// The meeting, and its transcript when there is anything to say.
    func meeting(me: String, folder: String?, now: Date) -> (Meeting, Transcript?) {
        if let gapLines {
            let (lines, themName) = Self.transcriptLines(gapLines, me: me)
            let transcript = lines.isEmpty ? nil : Transcript(lines: lines, engine: "granola", processedAt: now)
            return (build(me: me, them: themName, folder: folder, transcript: transcript), transcript)
        }
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
        lines = lines.enumerated().sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }.map(\.element)
        let transcript = lines.isEmpty ? nil : Transcript(lines: lines, engine: "granola", processedAt: now)
        return (build(me: me, them: nil, folder: folder, transcript: transcript), transcript)
    }

    private func build(me: String, them themName: String?, folder: String?, transcript: Transcript?) -> Meeting {
        let them = themName ?? "Them"
        let info = MeetingInfo(
            title: title, start: start, end: end, attendees: attendees,
            folder: folderNames.first ?? folder, source: "granola", granolaID: id, granolaUUID: uuid?.lowercased(),
            speakers: ["me": me, "them": them])
        let summaryText = summary.isEmpty ? "" : "\(GranolaImport.importedSummaryHeading)\n\n\(summary)\n"
        return Meeting(info: info, notes: privateNotes, summary: summaryText,
                       transcriptMarkdown: transcript.map { $0.markdown(me: me, them: them) + "\n" } ?? "")
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}

/// `folders.json` and `mcp-folders.json`: folder name to meeting ids, either as a list or as
/// `{"meeting_ids": [...]}` (the shape reconcile.py reads). Ids are Granola
/// `not_` ids or the UUIDs from the note's `web_url`.
struct FolderIndex {
    private var byID: [String: String] = [:]

    /// Earlier files win when two name the same meeting.
    init(files: [URL]) {
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (name, value) in root.sorted(by: { $0.key < $1.key }) {
                let ids = (value as? [String]) ?? ((value as? [String: Any])?["meeting_ids"] as? [String]) ?? []
                for id in ids where byID[id.lowercased()] == nil { byID[id.lowercased()] = name }
            }
        }
    }

    func name(for note: RawNote) -> String? {
        byID[note.id.lowercased()] ?? note.uuid.flatMap { byID[$0] }
    }
}
