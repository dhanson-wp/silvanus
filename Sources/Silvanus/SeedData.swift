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
                summary: "Agreed on scope and a first milestone.",
                todo: "- [ ] Sam sends the project plan\n",
                transcriptMarkdown: kickoffTranscript.markdown(me: "Sam Rivera")),
            Meeting(
                info: MeetingInfo(
                    id: "seed-weekly-sync", title: "Weekly sync", series: "Weekly sync",
                    start: base.addingTimeInterval(-day), end: base.addingTimeInterval(-day + 1_800),
                    attendees: ["Sam Rivera", "Jordan Lee"], folder: "Team"),
                notes: "Status\n- On track\n"),
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
}
