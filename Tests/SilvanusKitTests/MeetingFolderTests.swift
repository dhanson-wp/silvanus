import Foundation
import Testing
@testable import SilvanusKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

// 2026-11-06 14:30:00 UTC
private let start = Date(timeIntervalSince1970: 1_793_975_400)

@Test func relativePathUsesSeriesAndMinute() {
    #expect(MeetingFolder.relativePath(series: "Acme kickoff", start: start, calendar: utc)
            == "meetings/Acme kickoff/2026-11-06 1430")
}

@Test func relativePathUsesTheCalendarTimeZone() {
    var c = utc
    c.timeZone = TimeZone(identifier: "America/New_York")!
    #expect(MeetingFolder.relativePath(series: "Acme kickoff", start: start, calendar: c)
            == "meetings/Acme kickoff/2026-11-06 0930")
}

@Test func seriesNameIsSafe() {
    #expect(MeetingFolder.safeSeries("a/b: c") == "a-b- c")
    #expect(MeetingFolder.safeSeries(".hidden") == "-hidden")
    #expect(MeetingFolder.safeSeries("..") == "-.")
    #expect(MeetingFolder.safeSeries(String(repeating: "x", count: 200)).count == 80)
    #expect(MeetingFolder.safeSeries("   ") == "Untitled meeting")
    let path = MeetingFolder.relativePath(series: "a/b: c", start: start, calendar: utc)
    #expect(path.split(separator: "/").count == 3)
}
