import Foundation
import Testing
@testable import SilvanusKit

@Suite("Calendar rules") struct CalendarRulesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-11-10 10:00 UTC.
    private let ten = Date(timeIntervalSince1970: 1_794_304_800)

    private func event(_ title: String, at offset: TimeInterval, minutes: Double = 30, link: String? = nil,
                       allDay: Bool = false, declined: Bool = false) -> CalendarEvent {
        CalendarEvent(id: title, title: title, start: ten.addingTimeInterval(offset), end: ten.addingTimeInterval(offset + minutes * 60),
                      isAllDay: allDay, declined: declined, link: link.flatMap(URL.init(string:)))
    }

    @Test("A recording belongs to the event that's on when it starts, or starts within 10 minutes")
    func eventAtStart() {
        let events = [event("Acme kickoff", at: 0), event("Design review", at: 3_600)]
        #expect(CalendarRules.event(at: ten.addingTimeInterval(120), in: events)?.title == "Acme kickoff")
        #expect(CalendarRules.event(at: ten.addingTimeInterval(3_600 - 300), in: events)?.title == "Design review")
        #expect(CalendarRules.event(at: ten.addingTimeInterval(1_800), in: events) == nil)
        #expect(CalendarRules.event(at: ten.addingTimeInterval(-900), in: events) == nil)
    }

    @Test("With two events at once, the one with a call link wins")
    func linkWins() {
        let events = [event("Focus time", at: 0, minutes: 120), event("Acme kickoff", at: -600, minutes: 60, link: "https://meet.google.com/abc-defg-hij")]
        #expect(CalendarRules.event(at: ten.addingTimeInterval(60), in: events)?.title == "Acme kickoff")
    }

    @Test("All-day and declined events never name a recording")
    func skipped() {
        let events = [event("Company holiday", at: -36_000, minutes: 1_440, allDay: true), event("Optional sync", at: 0, declined: true)]
        #expect(CalendarRules.event(at: ten, in: events) == nil)
    }

    @Test("Coming up is today and tomorrow, in time order, without declined, all-day, or finished events")
    func comingUp() {
        let events = [
            event("Earlier standup", at: -7_200),
            event("Design review", at: 3_600),
            event("Acme kickoff", at: -600, minutes: 60),
            event("Declined", at: 7_200, declined: true),
            event("Holiday", at: 0, minutes: 1_440, allDay: true),
            event("Tomorrow sync", at: 86_400),
            event("Next week", at: 86_400 * 3),
        ]
        let days = CalendarRules.comingUp(events, now: ten, calendar: calendar)
        #expect(days.count == 2)
        #expect(days[0].isToday && !days[1].isToday)
        #expect(days[0].events.map(\.title) == ["Acme kickoff", "Design review"])
        #expect(days[1].events.map(\.title) == ["Tomorrow sync"])
        #expect(CalendarRules.isNow(days[0].events[0], now: ten))
        #expect(!CalendarRules.isNow(days[0].events[1], now: ten))
    }

    @Test("Join links are found in the event's text, on the call services' own domains only")
    func joinLinks() {
        #expect(CalendarRules.joinLink(in: [nil, "Room 4", "Join: https://acme.zoom.us/j/123456789?pwd=abc"])?.host() == "acme.zoom.us")
        #expect(CalendarRules.joinLink(in: ["https://example.com/agenda and https://meet.google.com/abc-defg-hij"])?.host() == "meet.google.com")
        #expect(CalendarRules.joinLink(in: ["https://zoom.us.example.com/j/1", "http://zoom.us/j/1", "https://notzoom.us/j/1"]) == nil)
        #expect(CalendarRules.isCallLink(URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!))
    }

    @Test("An event's meeting is the one with its title that started during it")
    func meetingForEvent() {
        let kickoff = event("Acme kickoff", at: 0)
        let made = Meeting(info: MeetingInfo(id: "made", title: "Acme kickoff", start: ten.addingTimeInterval(-120)))
        let old = Meeting(info: MeetingInfo(id: "old", title: "Acme kickoff", start: ten.addingTimeInterval(-86_400 * 7)))
        #expect(CalendarRules.meeting(for: kickoff, in: [old, made])?.id == "made")
        #expect(CalendarRules.meeting(for: kickoff, in: [old]) == nil)
    }
}
