import EventKit
import Foundation
import SilvanusKit

/// Whether Silvanus may read the Mac's calendars.
enum CalendarAccess: Equatable {
    case notAsked, allowed, denied
}

/// Where calendar events come from. The live one reads the Mac's calendars through
/// EventKit, read-only; snapshots and the self-test use made-up events and never ask.
struct CalendarSource {
    var access: () -> CalendarAccess
    /// Asks macOS for access (once; later calls return the answer already given).
    var request: () async -> CalendarAccess
    var events: (_ from: Date, _ to: Date) -> [CalendarEvent]
    /// Calls back when the calendars change. The self-test's never does.
    var onChange: (@escaping @MainActor () -> Void) -> Void

    static let live: CalendarSource = {
        let store = EKEventStore()
        return CalendarSource(
            access: { access(EKEventStore.authorizationStatus(for: .event)) },
            request: {
                _ = try? await store.requestFullAccessToEvents()
                return access(EKEventStore.authorizationStatus(for: .event))
            },
            events: { from, to in
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
                return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil)).map { event($0) }
            },
            onChange: { changed in
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                    MainActor.assumeIsolated { changed() }
                }
            })
    }()

    /// No calendar at all: test runs, until they set their own events.
    static func fixed(_ events: [CalendarEvent], access: CalendarAccess = .allowed) -> CalendarSource {
        CalendarSource(access: { access }, request: { access },
                       events: { from, to in events.filter { $0.end > from && $0.start < to } },
                       onChange: { _ in })
    }

    private static func access(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    private static func event(_ event: EKEvent) -> CalendarEvent {
        let people = event.attendees ?? []
        return CalendarEvent(
            id: "\(event.calendarItemIdentifier)-\(Int(event.startDate.timeIntervalSince1970))",
            title: (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            start: event.startDate, end: event.endDate,
            attendees: people.filter { !$0.isCurrentUser }.compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            isAllDay: event.isAllDay,
            declined: people.contains { $0.isCurrentUser && $0.participantStatus == .declined },
            link: CalendarRules.joinLink(in: [event.url?.absoluteString, event.location, event.notes]))
    }
}
