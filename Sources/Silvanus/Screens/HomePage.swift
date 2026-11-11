import SilvanusKit
import SwiftUI

/// Home (the sidebar's Home row, ⇧⌘H; also the canvas with no meeting open): what's coming
/// up today and tomorrow from the Mac's calendar, in KIT.md's "Coming up card". Click an
/// event to open its meeting page (made the first time, titled after the event, with its
/// attendees), ready to record; Join opens its Zoom, Meet, or Teams link. Until the
/// calendar is connected the card offers Connect Calendar instead.
struct HomePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Coming up")
                    .kitType(.title)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                card
                if model.calendarAccess == .allowed, model.calendarAccounts.isEmpty || model.comingUp.allSatisfy(\.events.isEmpty) {
                    HStack(spacing: Space.sm) {
                        Text(model.calendarAccounts.isEmpty ? "No calendar accounts on this Mac yet." : "Missing your Google Calendar?")
                            .kitType(.label)
                            .foregroundStyle(Ink.textSecondary)
                        Button("Add Google Calendar…", action: model.addCalendarAccount)
                            .buttonStyle(KitButtonStyle())
                            .help("Opens System Settings > Internet Accounts")
                    }
                }
                if model.showsModelSetup, let offer = model.summaryModels.recommended {
                    ModelSetupCard(offer: offer)
                }
            }
            .padding(.horizontal, Metric.contentX - Metric.canvasX)
            .padding(.vertical, Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.refreshCalendar() }
        // Coming back from System Settings (after adding an account) shows the new events.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshCalendar() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.calendarAccess {
            case .notAsked:
                connect("See today's and tomorrow's calls here, and get recordings titled for you.",
                        button: "Connect Calendar", action: model.connectCalendar)
            case .denied:
                connect("Calendar access is off for Silvanus.", button: "Open System Settings…", action: model.openCalendarSettings)
            case .allowed:
                let days = model.comingUp
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 {
                        Line().stroke(Ink.divider, style: StrokeStyle(lineWidth: Metric.comingUpBorder, dash: Metric.comingUpDash))
                            .frame(height: Metric.comingUpBorder)
                    }
                    dayGroup(day)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.comingUpCorner))
        .overlay(RoundedRectangle(cornerRadius: Metric.comingUpCorner).strokeBorder(Ink.divider, lineWidth: Metric.comingUpBorder))
    }

    private func connect(_ message: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.lg) {
            Text(message)
                .kitType(.rowTitle)
                .foregroundStyle(Ink.textSecondary)
            Spacer(minLength: Space.lg)
            Button(button, action: action)
                .buttonStyle(KitButtonStyle())
        }
        .padding(Space.lg)
    }

    private func dayGroup(_ day: CalendarRules.Day) -> some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text(day.date.formatted(.dateTime.day()))
                    .kitType(.dayNumber)
                    .foregroundStyle(Ink.text)
                    .frame(width: Metric.comingUpMonthX - Metric.comingUpDayX, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.xs) {
                        Text(day.date.formatted(.dateTime.month(.wide)))
                            .kitType(.meta)
                            .fontWeight(.medium)
                            .foregroundStyle(Ink.text)
                        if day.isToday {
                            Circle().fill(Ink.accent)
                                .frame(width: Metric.comingUpTodayDot, height: Metric.comingUpTodayDot)
                                .accessibilityLabel("Today")
                        }
                    }
                    Text(day.date.formatted(.dateTime.weekday(.wide)))
                        .kitType(.meta)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
            .frame(width: Metric.comingUpEventsX - Metric.comingUpDayX, alignment: .leading)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 0) {
                if day.events.isEmpty {
                    Text("Nothing on your calendar")
                        .kitType(.rowTitle)
                        .foregroundStyle(Ink.textSecondary)
                        .frame(height: Metric.comingUpRuleHeight)
                }
                ForEach(day.events) { event in
                    EventRow(event: event, now: CalendarRules.isNow(event, now: model.now) || CalendarRules.isNow(event, now: Date()))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Metric.comingUpDayX)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.lg)
    }
}

/// Home's model card, under Coming up until a model is in place: what the model is for,
/// the one recommended for this Mac with its size, Download (then its progress), More
/// Options for Settings > Summaries, and Not Now, which puts the card away.
private struct ModelSetupCard: View {
    @Environment(AppModel.self) private var model
    let offer: CatalogModel

    var body: some View {
        let state = model.summaryModels.state(of: offer)
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(ModelWords.setup)
                    .kitType(.rowTitle)
                    .foregroundStyle(Ink.text)
                Text(detail(state))
                    .kitType(.label)
                    .foregroundStyle(Ink.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.sm) {
                ModelDownloadControl(item: offer, state: state, canRemove: false)
                Button("More Options") { model.openSettings(.summaries) }
                    .buttonStyle(KitButtonStyle())
                    .help("Open Settings > Summaries")
                Spacer(minLength: Space.sm)
                Button("Not Now") { model.modelSetupHidden = true }
                    .buttonStyle(KitButtonStyle())
                    .help("Hide this. Summaries stay off until you download a model in Settings > Summaries.")
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.comingUpCorner))
        .overlay(RoundedRectangle(cornerRadius: Metric.comingUpCorner).strokeBorder(Ink.divider, lineWidth: Metric.comingUpBorder))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set up summaries")
    }

    /// The offer, or why its download stopped.
    private func detail(_ state: SummaryModels.State) -> String {
        if case let .failed(reason) = state { reason } else { ModelWords.offer(offer) }
    }
}

/// One event on the card: the accent rule (the recording color while it's on), the title,
/// and the time under it. The whole row opens the event's meeting; Join sits at its end.
private struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent
    let now: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.sm) {
            Button {
                model.open(event: event)
            } label: {
                HStack(spacing: Metric.comingUpTitleGap) {
                    RoundedRectangle(cornerRadius: Metric.comingUpRuleCorner)
                        .fill(now ? Ink.recording : Ink.accent)
                        .frame(width: Metric.comingUpRuleWidth, height: Metric.comingUpRuleHeight)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(event.title.isEmpty ? Meeting.untitled : event.title)
                            .kitType(.rowTitle)
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                        Text(time)
                            .kitType(.monoTime)
                            .foregroundStyle(Ink.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open a meeting page for this event")
            .accessibilityLabel("\(event.title), \(time)\(now ? ", on now" : "")")
            if event.link != nil {
                Button("Join") { model.join(event) }
                    .buttonStyle(KitButtonStyle())
                    .help("Open the call")
                    .accessibilityLabel("Join \(event.title)")
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(height: Metric.comingUpEventPitch)
        .background(hovering ? Ink.selection : .clear, in: RoundedRectangle(cornerRadius: Space.sm))
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    /// "10:00 – 10:30 AM", then how many others are invited.
    private var time: String {
        let range = (event.start..<event.end).formatted(.interval.hour().minute())
        return event.attendees.isEmpty ? range : "\(range) · \(event.attendees.count) \(event.attendees.count == 1 ? "person" : "people")"
    }
}

/// A horizontal line, for the dashed rule between days.
private nonisolated struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
