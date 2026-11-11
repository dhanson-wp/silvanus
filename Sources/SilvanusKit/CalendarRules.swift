import Foundation

/// One event from the Mac's calendars, as much of it as Silvanus uses. Read-only.
public struct CalendarEvent: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    /// The other people invited, by name.
    public var attendees: [String]
    public var isAllDay: Bool
    /// True when I declined it.
    public var declined: Bool
    /// The call's link, when it's a Zoom, Meet, or Teams link.
    public var link: URL?

    public init(id: String, title: String, start: Date, end: Date, attendees: [String] = [],
                isAllDay: Bool = false, declined: Bool = false, link: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.isAllDay = isAllDay
        self.declined = declined
        self.link = link
    }
}

/// The rules for the calendar connection: which event a recording belongs to, what
/// Coming up shows, and which links Join may open.
public enum CalendarRules {
    /// A recording may start this long before its event does.
    public static let early: TimeInterval = 10 * 60

    /// The hosts Join opens: the call services' own domains, and nothing else.
    static let callHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com"]

    /// The first Zoom, Meet, or Teams link in an event's URL, location, or notes.
    public static func joinLink(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, isCallLink(url) { return url }
            }
        }
        return nil
    }

    /// True for an https link on one of the call services' own domains.
    public static func isCallLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return callHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The event a recording that starts at `date` belongs to: one that's on then, or
    /// starts within 10 minutes. All-day and declined events never match. With several,
    /// one with a call link wins, then the one that started last.
    public static func event(at date: Date, in events: [CalendarEvent]) -> CalendarEvent? {
        events.filter { !$0.isAllDay && !$0.declined && $0.start.addingTimeInterval(-early) <= date && date < $0.end }
            .sorted { a, b in
                if (a.link != nil) != (b.link != nil) { return a.link != nil }
                return a.start > b.start
            }
            .first
    }

    /// A day on the Coming up card.
    public struct Day: Equatable, Identifiable, Sendable {
        public var date: Date
        public var isToday: Bool
        public var events: [CalendarEvent]

        public var id: Date { date }
    }

    /// Today and tomorrow, each with its events in time order. Declined and all-day
    /// events are left out, and so are today's events that have already ended.
    public static func comingUp(_ events: [CalendarEvent], now: Date, calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        return (0...1).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let shown = events.filter { !$0.isAllDay && !$0.declined && $0.start >= day && $0.start < next && $0.end > now }
                .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            return Day(date: day, isToday: offset == 0, events: shown)
        }
    }

    /// True while the event is on.
    public static func isNow(_ event: CalendarEvent, now: Date) -> Bool {
        event.start <= now && now < event.end
    }

    /// The meeting already made for this event, if any: same title, started from 10
    /// minutes before the event until its end.
    public static func meeting(for event: CalendarEvent, in meetings: [Meeting]) -> Meeting? {
        meetings.first {
            $0.info.title == event.title && $0.info.start >= event.start.addingTimeInterval(-early) && $0.info.start < event.end
        }
    }
}
