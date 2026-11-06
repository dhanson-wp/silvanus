import Foundation
import SilvanusKit

/// Fictional meetings for snapshots and experiments. Written only when
/// APP_SEED=1 and APP_STORE is a folder under /tmp, and only into an empty store.
enum SeedData {
    static func seedIfRequested(library: MeetingLibrary) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isScratch else { return }
        guard library.loadAll().meetings.isEmpty else { return }
        for meeting in meetings() { _ = try? library.save(meeting) }
    }

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
                todo: "- [ ] Sam sends the project plan\n"),
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
