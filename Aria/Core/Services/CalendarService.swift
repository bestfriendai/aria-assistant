import Foundation
import EventKit

/// Unified calendar service supporting Apple Calendar, Google, and Outlook
actor CalendarService {
    // MARK: - EventKit

    private let eventStore = EKEventStore()
    private var hasCalendarAccess = false

    // MARK: - External Providers

    private var googleClient: GoogleCalendarClient?
    private var outlookClient: OutlookCalendarClient?

    // MARK: - Permissions

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                hasCalendarAccess = try await eventStore.requestFullAccessToEvents()
            } else {
                hasCalendarAccess = try await eventStore.requestAccess(to: .event)
            }
            return hasCalendarAccess
        } catch {
            return false
        }
    }

    // MARK: - Provider Configuration

    func configureGoogle(credentials: OAuthCredentials) async throws {
        googleClient = GoogleCalendarClient(credentials: credentials)
        try await googleClient?.authenticate()
    }

    func configureOutlook(credentials: OAuthCredentials) async throws {
        outlookClient = OutlookCalendarClient(credentials: credentials)
        try await outlookClient?.authenticate()
    }

    // MARK: - Fetch Events

    func getEvents(
        from startDate: Date,
        to endDate: Date,
        calendars: [String]? = nil
    ) async throws -> [CalendarEvent] {
        var allEvents: [CalendarEvent] = []

        // Fetch from EventKit
        if hasCalendarAccess {
            let ekEvents = try await fetchEventKitEvents(from: startDate, to: endDate)
            allEvents.append(contentsOf: ekEvents)
        }

        // Fetch from Google
        if let googleClient = googleClient {
            let googleEvents = try await googleClient.fetchEvents(from: startDate, to: endDate)
            allEvents.append(contentsOf: googleEvents)
        }

        // Fetch from Outlook
        if let outlookClient = outlookClient {
            let outlookEvents = try await outlookClient.fetchEvents(from: startDate, to: endDate)
            allEvents.append(contentsOf: outlookEvents)
        }

        // Sort by start date
        allEvents.sort { $0.startDate < $1.startDate }

        return allEvents
    }

    func getTodayEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await getEvents(from: startOfDay, to: endOfDay)
    }

    func getUpcomingEvents(hours: Int = 24) async throws -> [CalendarEvent] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: hours, to: now)!

        return try await getEvents(from: now, to: endDate)
    }

    func getNextEvent() async throws -> CalendarEvent? {
        let events = try await getUpcomingEvents(hours: 24)
        return events.first { $0.startDate > Date() }
    }

    // MARK: - EventKit Fetch

    private func fetchEventKitEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                provider: .apple,
                providerEventId: event.eventIdentifier,
                calendarId: event.calendar.calendarIdentifier,
                title: event.title ?? "Untitled",
                notes: event.notes,
                location: event.location,
                url: event.url,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                attendees: event.attendees?.map { attendee in
                    Attendee(
                        email: attendee.url?.absoluteString.replacingOccurrences(of: "mailto:", with: "") ?? "",
                        name: attendee.name,
                        status: mapAttendeeStatus(attendee.participantStatus),
                        isOptional: attendee.participantRole == .optional
                    )
                } ?? [],
                status: event.status == .canceled ? .cancelled : .confirmed
            )
        }
    }

    private func mapAttendeeStatus(_ status: EKParticipantStatus) -> AttendeeStatus {
        switch status {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        default: return .pending
        }
    }

    // MARK: - Create Event

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        location: String? = nil,
        calendar: String? = nil,
        provider: CalendarProvider = .apple
    ) async throws -> CalendarEvent {
        switch provider {
        case .apple:
            return try await createEventKitEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes,
                location: location
            )
        case .google:
            guard let googleClient = googleClient else {
                throw CalendarServiceError.providerNotConfigured
            }
            return try await googleClient.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes,
                location: location
            )
        case .outlook:
            guard let outlookClient = outlookClient else {
                throw CalendarServiceError.providerNotConfigured
            }
            return try await outlookClient.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes,
                location: location
            )
        }
    }

    private func createEventKitEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String?
    ) async throws -> CalendarEvent {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)

        return CalendarEvent(
            provider: .apple,
            providerEventId: event.eventIdentifier,
            calendarId: event.calendar.calendarIdentifier,
            title: title,
            notes: notes,
            location: location,
            startDate: startDate,
            endDate: endDate
        )
    }

    // MARK: - Delete Event

    func deleteEvent(_ eventId: String, provider: CalendarProvider) async throws {
        switch provider {
        case .apple:
            guard let event = eventStore.event(withIdentifier: eventId) else {
                throw CalendarServiceError.eventNotFound
            }
            try eventStore.remove(event, span: .thisEvent)

        case .google:
            try await googleClient?.deleteEvent(eventId)

        case .outlook:
            try await outlookClient?.deleteEvent(eventId)
        }
    }

    // MARK: - Conflict Detection

    func findConflicts(for event: CalendarEvent) async throws -> [CalendarEvent] {
        let buffer: TimeInterval = 15 * 60 // 15 minutes buffer

        let events = try await getEvents(
            from: event.startDate.addingTimeInterval(-buffer),
            to: event.endDate.addingTimeInterval(buffer)
        )

        return events.filter { $0.id != event.id && $0.conflicts(with: event) }
    }

    func findFreeSlots(
        duration: TimeInterval,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [DateInterval] {
        let events = try await getEvents(from: startDate, to: endDate)
            .filter { $0.availability == .busy }
            .sorted { $0.startDate < $1.startDate }

        var freeSlots: [DateInterval] = []
        var currentStart = startDate

        for event in events {
            if currentStart.addingTimeInterval(duration) <= event.startDate {
                freeSlots.append(DateInterval(start: currentStart, end: event.startDate))
            }
            currentStart = max(currentStart, event.endDate)
        }

        // Check remaining time
        if currentStart.addingTimeInterval(duration) <= endDate {
            freeSlots.append(DateInterval(start: currentStart, end: endDate))
        }

        return freeSlots
    }
}

// MARK: - Google Calendar Client

class GoogleCalendarClient {
    private let credentials: OAuthCredentials

    init(credentials: OAuthCredentials) {
        self.credentials = credentials
    }

    func authenticate() async throws {}

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        // Google Calendar API call
        return []
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String?
    ) async throws -> CalendarEvent {
        // Google Calendar API call
        return CalendarEvent(
            provider: .google,
            providerEventId: UUID().uuidString,
            calendarId: "primary",
            title: title,
            startDate: startDate,
            endDate: endDate
        )
    }

    func deleteEvent(_ eventId: String) async throws {}
}

// MARK: - Outlook Calendar Client

class OutlookCalendarClient {
    private let credentials: OAuthCredentials

    init(credentials: OAuthCredentials) {
        self.credentials = credentials
    }

    func authenticate() async throws {}

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        return []
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String?
    ) async throws -> CalendarEvent {
        return CalendarEvent(
            provider: .outlook,
            providerEventId: UUID().uuidString,
            calendarId: "default",
            title: title,
            startDate: startDate,
            endDate: endDate
        )
    }

    func deleteEvent(_ eventId: String) async throws {}
}

// MARK: - Errors

enum CalendarServiceError: Error {
    case accessDenied
    case providerNotConfigured
    case eventNotFound
    case createFailed
}
