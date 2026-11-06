import Foundation
import Testing
@testable import SilvanusKit

private func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}

private let utc = calendar("UTC")

/// A moment in `cal`'s time zone.
private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0, in cal: Calendar = utc) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

private func meeting(_ id: String, _ start: Date, folder: String? = nil) -> Meeting {
    Meeting(info: MeetingInfo(id: id, title: "Acme kickoff", start: start, folder: folder))
}

// Friday, November 6, 2026, 14:30 UTC.
private let now = at(2026, 11, 6, 14, 30)

private func titles(_ groups: [(title: String, meetings: [Meeting])]) -> [String] { groups.map(\.title) }
private func ids(_ groups: [(title: String, meetings: [Meeting])]) -> [[String]] { groups.map { $0.meetings.map(\.id) } }

@Test func todayAndYesterday() {
    let groups = DayGroups.group([
        meeting("a", at(2026, 11, 6, 9)),
        meeting("b", at(2026, 11, 5, 16)),
        meeting("c", at(2026, 11, 6, 13)),
    ], now: now, calendar: utc)
    #expect(titles(groups) == ["Today", "Yesterday"])
    // Newest first inside a day.
    #expect(ids(groups) == [["c", "a"], ["b"]])
}

@Test func olderDaysThisWeekShowTheWeekday() {
    let groups = DayGroups.group([
        meeting("tue", at(2026, 11, 3)),
        meeting("sat", at(2026, 10, 31)),
    ], now: now, calendar: utc)
    #expect(titles(groups) == ["Tuesday", "Saturday"])
}

@Test func olderThanAWeekShowsTheDate() {
    // Seven days back is the same weekday as today, so it gets the date.
    let groups = DayGroups.group([
        meeting("a", at(2026, 11, 2)),
        meeting("b", at(2026, 10, 30)),
        meeting("c", at(2026, 10, 12)),
    ], now: at(2026, 11, 10, 9), calendar: utc)
    #expect(titles(groups) == ["Mon, Nov 2", "Fri, Oct 30", "Mon, Oct 12"])
}

@Test func anotherYearShowsTheYear() {
    let groups = DayGroups.group([meeting("a", at(2025, 11, 3))], now: now, calendar: utc)
    #expect(titles(groups) == ["Mon, Nov 3, 2025"])
}

@Test func midnightBelongsToTheDayItStarts() {
    let groups = DayGroups.group([
        meeting("today", at(2026, 11, 6, 0, 0, 0)),
        meeting("yesterday", at(2026, 11, 5, 23, 59, 59)),
    ], now: now, calendar: utc)
    #expect(titles(groups) == ["Today", "Yesterday"])
    #expect(ids(groups) == [["today"], ["yesterday"]])
}

@Test func daysFollowTheCalendarsTimeZone() {
    let la = calendar("America/Los_Angeles")
    // 06:00 UTC on Nov 6 is 22:00 on Nov 5 in Los Angeles.
    let lateEvening = at(2026, 11, 6, 6)
    let meetings = [
        meeting("evening", at(2026, 11, 5, 20, in: la)),  // 04:00 UTC on Nov 6
        meeting("morning", at(2026, 11, 5, 8, in: la)),   // 16:00 UTC on Nov 5
        meeting("before", at(2026, 11, 4, 23, in: la)),   // 07:00 UTC on Nov 5
    ]
    let local = DayGroups.group(meetings, now: lateEvening, calendar: la)
    #expect(titles(local) == ["Today", "Yesterday"])
    #expect(ids(local) == [["evening", "morning"], ["before"]])
    // The same moments, read in UTC, split differently.
    let inUTC = DayGroups.group(meetings, now: lateEvening, calendar: utc)
    #expect(ids(inUTC) == [["evening"], ["morning", "before"]])
}

@Test func emptyHasNoGroups() {
    #expect(DayGroups.group([], now: now, calendar: utc).isEmpty)
}

@Test func foldersAreDistinctSortedAndCounted() {
    let meetings = [
        meeting("a", now, folder: "Team"),
        meeting("b", now, folder: "clients"),
        meeting("c", now, folder: "Team"),
        meeting("d", now),
        meeting("e", now, folder: "  "),
    ]
    let folders = SidebarFolders.list(meetings)
    #expect(folders.map(\.name) == ["clients", "Team"])
    #expect(folders.map(\.count) == [1, 2])
    #expect(SidebarFolders.filter(meetings, folder: "Team").map(\.id) == ["a", "c"])
    #expect(SidebarFolders.filter(meetings, folder: nil).map(\.id) == ["a", "b", "c", "d", "e"])
}

@Test func arrowKeysStepThroughTheList() {
    let ids = ["a", "b", "c"]
    #expect(SidebarSelection.step(ids, from: "b", by: 1) == "c")
    #expect(SidebarSelection.step(ids, from: "b", by: -1) == "a")
    // The ends hold.
    #expect(SidebarSelection.step(ids, from: "c", by: 1) == "c")
    #expect(SidebarSelection.step(ids, from: "a", by: -1) == "a")
    // Nothing selected, or a selection that's not in the list: down takes the first, up the last.
    #expect(SidebarSelection.step(ids, from: nil, by: 1) == "a")
    #expect(SidebarSelection.step(ids, from: "gone", by: -1) == "c")
    #expect(SidebarSelection.step([], from: "a", by: 1) == nil)
}
