import AppKit
import Combine
import EventKit
import Foundation

struct CalendarEventItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: CalendarEventColor
}

struct CalendarEventColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let fallback = CalendarEventColor(red: 0.16, green: 0.62, blue: 1)
}

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var selectedDate: Date
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var isRequestingAccess = false

    private let eventStore: EKEventStore
    private var calendar: Calendar
    private var eventStoreObserver: NSObjectProtocol?
    private var hasStarted = false

    init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
        selectedDate = calendar.startOfDay(for: now)
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var visibleDates: [Date] {
        Self.centeredDates(containing: selectedDate, calendar: calendar)
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    func start() {
        guard !hasStarted else {
            refreshAuthorizationAndEvents()
            return
        }
        hasStarted = true

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthorizationAndEvents()
            }
        }

        refreshAuthorizationAndEvents()
    }

    func select(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        guard !calendar.isDate(normalized, inSameDayAs: selectedDate) else { return }
        selectedDate = normalized
        refreshEvents()
    }

    func requestAccess() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard authorizationStatus == .notDetermined,
              !isRequestingAccess else {
            return
        }

        isRequestingAccess = true
        NSApp.activate(ignoringOtherApps: true)
        Task { [weak self] in
            guard let self else { return }
            _ = try? await eventStore.requestFullAccessToEvents()
            isRequestingAccess = false
            refreshAuthorizationAndEvents()
        }
    }

    static func centeredDates(
        containing date: Date,
        calendar: Calendar
    ) -> [Date] {
        let day = calendar.startOfDay(for: date)
        return (-3...3).compactMap {
            calendar.date(byAdding: .day, value: $0, to: day)
        }
    }

    private func refreshAuthorizationAndEvents() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        refreshEvents()
    }

    private func refreshEvents() {
        guard hasFullAccess else {
            events = []
            return
        }

        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            events = []
            return
        }

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        events = eventStore.events(matching: predicate)
            .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
            .map(Self.eventItem)
    }

    private static func eventItem(from event: EKEvent) -> CalendarEventItem {
        CalendarEventItem(
            id: event.eventIdentifier ?? event.calendarItemIdentifier,
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Wydarzenie",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            color: eventColor(from: event)
        )
    }

    private static func eventColor(from event: EKEvent) -> CalendarEventColor {
        guard let color = NSColor(cgColor: event.calendar.cgColor)?.usingColorSpace(.deviceRGB) else {
            return .fallback
        }
        return CalendarEventColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
