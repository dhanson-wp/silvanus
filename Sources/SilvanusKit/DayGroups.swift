import Foundation

/// One day's meetings in the sidebar, under its heading.
public struct DayGroup: Equatable, Sendable {
    /// The day's first moment in the calendar used to group; a stable id for the heading.
    public let day: Date
    public let title: String
    public let meetings: [Meeting]
}

/// The sidebar's day headings: meetings grouped by the calendar day they start on.
public enum DayGroups {
    /// Groups meetings by the day they start in `calendar`'s time zone, newest day first and
    /// newest meeting first inside a day. Titles: "Today", "Yesterday", the weekday for the
    /// rest of the past week ("Tuesday"), then the date ("Mon, Nov 2"), with the year when it
    /// isn't this year ("Mon, Nov 3, 2025"). A meeting at midnight belongs to the day it starts.
    public static func group(_ meetings: [Meeting], now: Date, calendar: Calendar) -> [(title: String, meetings: [Meeting])] {
        days(meetings, now: now, calendar: calendar).map { ($0.title, $0.meetings) }
    }

    /// The same groups, each with its day.
    public static func days(_ meetings: [Meeting], now: Date, calendar: Calendar) -> [DayGroup] {
        let byDay = Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.info.start) }
        let today = calendar.startOfDay(for: now)
        return byDay.keys.sorted(by: >).map { day in
            let sorted = byDay[day, default: []].sorted { $0.info.start > $1.info.start }
            return DayGroup(day: day, title: title(for: day, today: today, calendar: calendar), meetings: sorted)
        }
    }

    static func title(for day: Date, today: Date, calendar: Calendar) -> String {
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        // Format styles, not a DateFormatter per heading: Foundation caches their formatters.
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        switch daysAgo {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        // Seven days back is today's weekday again, so it takes the date.
        case 2...6: return day.formatted(style.weekday(.wide))
        default:
            let date = style.weekday(.abbreviated).month(.abbreviated).day()
            let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
            return day.formatted(sameYear ? date : date.year())
        }
    }
}

/// The sidebar's folders: the names people filed meetings under (`MeetingInfo.folder`).
public enum SidebarFolders {
    /// Each folder name once, with how many meetings it holds, in Finder's name order.
    /// Blank names don't count as folders.
    public static func list(_ meetings: [Meeting]) -> [(name: String, count: Int)] {
        let names = meetings.compactMap { name(of: $0) }
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ($0, counts[$0, default: 0]) }
    }

    /// The meetings in `folder`, in their order; nil is every meeting.
    public static func filter(_ meetings: [Meeting], folder: String?) -> [Meeting] {
        guard let folder else { return meetings }
        return meetings.filter { name(of: $0) == folder }
    }

    private static func name(of meeting: Meeting) -> String? {
        guard let folder = meeting.info.folder?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty
        else { return nil }
        return folder
    }
}

/// The sidebar's arrow keys.
public enum SidebarSelection {
    /// The id `by` places from `from` in `ids`, held at the ends. With nothing selected (or a
    /// selection no longer in the list), down picks the first and up the last.
    public static func step(_ ids: [String], from: String?, by: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let from, let index = ids.firstIndex(of: from) else { return by < 0 ? ids.last : ids.first }
        return ids[min(max(index + by, 0), ids.count - 1)]
    }
}
