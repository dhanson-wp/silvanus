import Foundation
import SilvanusKit

/// Fictional meetings for snapshots and experiments. Written only when
/// APP_SEED=1 and APP_STORE is a folder under /tmp, and only into an empty store.
enum SeedData {
    static func seedIfRequested(library: MeetingLibrary) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isScratch else { return }
        guard library.loadAll().meetings.isEmpty else { return }
        for meeting in meetings() { _ = try? library.save(meeting) }
        try? library.saveTranscript(kickoffTranscript, for: recordedID)
    }

    /// The seeded meeting that was recorded here, with a transcript.
    static let recordedID = "seed-acme-kickoff"

    /// The recorded meeting's transcript: fictional, with a few words the recognizer wasn't
    /// sure of (marked `~`, confidence 0.4) so the Transcript view shows its underlines.
    static let kickoffTranscript: Transcript = {
        let turns: [(Side, TimeInterval, String)] = [
            (.me, 2, "Thanks for making the time, everyone. I'd like to start with scope, then dates, then who owns what."),
            (.me, 9, "Priya, do you want to walk us through the ~integration first?"),
            (.them, 14, "Sure. The short version is we connect to the ~Acme ledger through their export, not the live API."),
            (.them, 22, "That keeps the first milestone small, and we can add the live sync once the export is stable."),
            (.me, 30, "That works for me. What does the export give us today?"),
            (.them, 34, "Invoices and payments, daily. Refunds come later, maybe in ~March."),
            (.them, 41, "Jordan has the field list, so I'll let him cover the ~mapping."),
            (.me, 47, "Great. Jordan, how many fields are we talking about?"),
            (.them, 51, "About forty. Most of them map one to one. Three need a lookup table, and the ~currency codes need cleaning."),
            (.me, 60, "Let's put the lookup tables in the staging checklist, so nobody forgets them before launch."),
            (.them, 67, "Agreed. I'll share the checklist by Friday."),
            (.me, 71, "Perfect. On dates, the launch target is March, with one buffer week."),
            (.them, 77, "One week feels tight if the ~refunds slip, but it's fine for the export."),
            (.me, 84, "Then let's call refunds out of scope for the first milestone and review it at the next sync."),
            (.them, 91, "Sounds good. I'll update the plan and send it around tonight."),
            (.me, 96, "Thank you both. I'll send the deck to Priya and book the room for the review."),
        ]
        var lines: [TranscriptLine] = []
        for (side, start, text) in turns {
            let words = text.split(separator: " ").enumerated().map { i, raw in
                let unsure = raw.hasPrefix("~")
                let at = start + Double(i) * 0.36
                return Word(text: String(unsure ? raw.dropFirst() : raw), start: at, end: at + 0.3,
                            confidence: unsure ? 0.4 : 0.93)
            }
            lines.append(TranscriptLine(side: side, words: words))
        }
        return Transcript(lines: lines, engine: "parakeet-tdt-v2", processedAt: Date(timeIntervalSince1970: 1_793_975_400))
    }()

    static func meetings(now: Date = Date()) -> [Meeting] {
        let day: TimeInterval = 86_400
        // Whole seconds, so dates survive the JSON round trip.
        let base = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return [
            Meeting(
                info: MeetingInfo(
                    id: "seed-hiring-plan", title: "Hiring plan", series: "Hiring plan",
                    start: base.addingTimeInterval(-3_600), end: base.addingTimeInterval(-1_800),
                    attendees: ["Sam Rivera", "Jordan Lee"]),
                notes: "Two roles this quarter.\n"),
            Meeting(
                info: MeetingInfo(
                    id: "seed-acme-kickoff", title: "Acme kickoff", series: "Acme kickoff",
                    start: base.addingTimeInterval(-2 * 3_600), end: base.addingTimeInterval(-3_600),
                    attendees: ["Sam Rivera", "Priya Natarajan", "Jordan Lee"], folder: "Clients"),
                notes: """
                    Thursday with Sam Rivera, Priya Natarajan, and Jordan Lee.

                    ## Agenda
                    - Scope
                    - Dates
                    - Who owns what

                    ## Notes
                    - Priya owns the integration plan
                    - Sam shares the `staging` checklist by Friday
                    - Launch target is **March**, with _one_ buffer week

                    ### To-dos
                    [ ] Send the deck to Priya
                    [x] Book the room for the review

                    """,
                summary: """
                    ## Overview
                    Agreed on scope and a first milestone for the **Acme** launch.

                    ## Decisions
                    - Launch target is **March**, with _one_ buffer week
                    - Priya owns the integration plan
                    - Sam shares the `staging` checklist by Friday

                    ### Open questions
                    - Who books the review room?
                    - Does the buffer week move if the deck slips?

                    ## Imported summary

                    A short recap kept as it came in: scope, dates, and who owns what.
                    - **Scope** is the integration plan and the staging checklist
                    - **Dates** hold at March unless the deck slips

                    """,
                todo: "- [ ] Sam sends the project plan\n",
                transcriptMarkdown: kickoffTranscript.markdown(me: "Sam Rivera")),
            Meeting(
                info: MeetingInfo(
                    id: "seed-weekly-sync", title: "Weekly sync", series: "Weekly sync",
                    start: base.addingTimeInterval(-day), end: base.addingTimeInterval(-day + 1_800),
                    attendees: ["Sam Rivera", "Jordan Lee"], folder: "Team"),
                notes: "Status\n- On track\n",
                todo: "- [x] Jordan Lee: share the hiring deck\n- [ ] Sam Rivera: confirm the offsite dates by Thursday\n- [ ] Jordan Lee: book the review room\n"),
            Meeting(
                info: MeetingInfo(
                    id: "seed-design-review", title: "Design review", series: "Design review",
                    start: base.addingTimeInterval(-3 * day), end: base.addingTimeInterval(-3 * day + 3_600),
                    attendees: ["Priya Natarajan", "Sam Rivera"]),
                notes: "Looked at the sidebar and the empty states.\n"),
            Meeting(
                info: MeetingInfo(
                    id: "seed-budget-review", title: "Budget review", series: "Budget review",
                    start: base.addingTimeInterval(-9 * day), end: base.addingTimeInterval(-9 * day + 2_700),
                    attendees: ["Sam Rivera", "Priya Natarajan"], folder: "Team"),
                notes: "Kept the travel line flat.\n"),
        ]
    }

    /// The reference-main snapshot page (Snapshot.captureReferenceMain): fictional meetings
    /// laid out like the reference capture design/KIT.md was measured from, so the two can be
    /// compared pixel for pixel. Seven meetings yesterday, newest first; the first and the
    /// sixth have a folder line; the fifth title is long enough to truncate. The sixth is
    /// the open one, and its notes are a paragraph, a heading, two bullets (the first wraps),
    /// and an empty bullet. The words are ours, picked only to be about as long.
    static let referenceSelectedID = "reference-orbit-review"

    static func referenceMain(now: Date = Date()) -> [Meeting] {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: yesterday) ?? yesterday
        }
        let rows: [(id: String, title: String, hour: Int, minute: Int, folder: String?)] = [
            ("reference-briefing-1", "Briefing", 21, 51, "Orbit"),
            ("reference-briefing-2", "Briefing", 20, 14, nil),
            ("reference-briefing-3", "Briefing", 19, 42, nil),
            ("reference-briefing-4", "Briefing", 12, 5, nil),
            ("reference-roadmap", "Roadmap questions and open items", 11, 38, nil),
            (referenceSelectedID, "Orbit design review", 9, 36, "Orbit"),
            ("reference-budget", "Weekly budget check", 9, 8, nil),
        ]
        return rows.map { row in
            let start = at(row.hour, row.minute)
            return Meeting(
                info: MeetingInfo(id: row.id, title: row.title, series: row.title,
                                  start: start, end: start.addingTimeInterval(1_200),
                                  attendees: ["Sam Rivera"], folder: row.folder),
                notes: row.id == referenceSelectedID ? referenceNotes : "")
        }
    }

    /// The open meeting's notes. The last line is an empty bullet ("- ").
    private static let referenceNotes = "Checking that the room mic picks up the people at the table.\n\n"
        + "### My asks\n"
        + "- Should we move the onboarding checklist into the help center and/or offer it as a guided flow?\n"
        + "- Can the export run nightly so finance can review it every morning?\n"
        + "- \n"
}
