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
    /// The accounts whose calendars the Mac has ("Google", "iCloud"), for Settings > Calendar.
    var accounts: () -> [String] = { [] }
    /// The user's own email addresses: the accounts named by an address, as Google's are.
    var ownAddresses: () -> Set<String> = { [] }
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
                let own = ownAddresses(store)
                return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil)).map { event($0, own: own) }
            },
            accounts: {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
                // Accounts only: not the Mac's own Birthdays, holidays, or subscribed calendars.
                return Array(accountTitles(store)).sorted()
            },
            ownAddresses: {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
                return ownAddresses(store)
            },
            onChange: { changed in
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                    MainActor.assumeIsolated { changed() }
                }
            })
    }()

    /// No calendar at all: test runs, until they set their own events.
    static func fixed(_ events: [CalendarEvent], access: CalendarAccess = .allowed, accounts: [String] = []) -> CalendarSource {
        CalendarSource(access: { access }, request: { access },
                       events: { from, to in events.filter { $0.end > from && $0.start < to } },
                       accounts: { accounts },
                       onChange: { _ in })
    }

    private static func access(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// The titles of the accounts whose calendars the Mac has. Not the Mac's own Birthdays,
    /// holidays, or subscribed calendars.
    private static func accountTitles(_ store: EKEventStore) -> Set<String> {
        Set(store.calendars(for: .event).compactMap { calendar -> String? in
            guard let source = calendar.source, [.calDAV, .exchange, .local, .mobileMe].contains(source.sourceType) else { return nil }
            return source.title
        })
    }

    /// The user's own addresses: accounts named by an address, and the address on nearly
    /// every meeting of the last four weeks (`CalendarRules.ownAddress`), since attendee
    /// lists don't always mark the current user.
    private static func ownAddresses(_ store: EKEventStore) -> Set<String> {
        var own = Set(accountTitles(store).filter { $0.contains("@") }.map { $0.lowercased() })
        let now = Date()
        let recent = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-28 * 86_400), end: now, calendars: nil))
        if let guess = CalendarRules.ownAddress(attendeesByEvent: recent.map { ($0.attendees ?? []).compactMap(address) }) {
            own.insert(guess)
        }
        return own
    }

    /// A participant's email address, from its mailto: link or, failing that, its name.
    private static func address(_ person: EKParticipant) -> String? {
        if person.url.scheme?.lowercased() == "mailto" {
            let value = person.url.absoluteString.dropFirst("mailto:".count).removingPercentEncoding ?? ""
            if value.contains("@") { return value }
        }
        // Google calendars often have no mailto: link and put the address in the name.
        let name = person.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.contains("@") && !name.contains(" ") ? name : nil
    }

    /// Each attendee other than the user, by name, or by address when the calendar has no name.
    /// The user is the calendar's current user, or one of their own accounts' addresses.
    private static func event(_ event: EKEvent, own: Set<String>) -> CalendarEvent {
        let people = (event.attendees ?? []).filter { person in
            !person.isCurrentUser && !own.contains(address(person)?.lowercased() ?? "")
        }
        return CalendarEvent(
            id: "\(event.calendarItemIdentifier)-\(Int(event.startDate.timeIntervalSince1970))",
            title: (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            start: event.startDate, end: event.endDate,
            attendees: people.compactMap { person in
                let name = person.name?.trimmingCharacters(in: .whitespaces) ?? ""
                return name.isEmpty ? address(person) : name
            },
            isAllDay: event.isAllDay,
            declined: (event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined },
            link: CalendarRules.joinLink(in: [event.url?.absoluteString, event.location, event.notes]))
    }
}
