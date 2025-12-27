import Foundation

/// Unified calendar event model
struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: CalendarProvider
    let providerEventId: String
    let calendarId: String

    var title: String
    var notes: String?
    var location: String?
    var url: URL?

    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var timeZone: String?

    var attendees: [Attendee]
    var organizer: Attendee?

    var recurrenceRule: String? // iCal RRULE format
    var isRecurring: Bool

    var alerts: [EventAlert]

    var status: EventStatus
    var availability: Availability

    // AI-computed
    var embedding: [Float]?
    var prepTasks: [String] // Suggested preparation tasks
    var relatedEmails: [UUID]

    init(
        id: UUID = UUID(),
        provider: CalendarProvider,
        providerEventId: String,
        calendarId: String,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        url: URL? = nil,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        timeZone: String? = nil,
        attendees: [Attendee] = [],
        organizer: Attendee? = nil,
        recurrenceRule: String? = nil,
        isRecurring: Bool = false,
        alerts: [EventAlert] = [],
        status: EventStatus = .confirmed,
        availability: Availability = .busy,
        embedding: [Float]? = nil,
        prepTasks: [String] = [],
        relatedEmails: [UUID] = []
    ) {
        self.id = id
        self.provider = provider
        self.providerEventId = providerEventId
        self.calendarId = calendarId
        self.title = title
        self.notes = notes
        self.location = location
        self.url = url
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.attendees = attendees
        self.organizer = organizer
        self.recurrenceRule = recurrenceRule
        self.isRecurring = isRecurring
        self.alerts = alerts
        self.status = status
        self.availability = availability
        self.embedding = embedding
        self.prepTasks = prepTasks
        self.relatedEmails = relatedEmails
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }

    var isUpcoming: Bool {
        startDate > Date()
    }

    var isHappeningNow: Bool {
        let now = Date()
        return startDate <= now && endDate >= now
    }

    var minutesUntilStart: Int? {
        guard isUpcoming else { return nil }
        return Int(startDate.timeIntervalSinceNow / 60)
    }
}

enum CalendarProvider: String, Codable, Hashable {
    case apple // EventKit
    case google
    case outlook
}

struct Attendee: Codable, Hashable {
    let email: String
    let name: String?
    var status: AttendeeStatus
    var isOptional: Bool

    var displayName: String {
        name ?? email
    }
}

enum AttendeeStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
    case tentative
}

struct EventAlert: Codable, Hashable {
    let minutesBefore: Int
    let type: AlertType

    enum AlertType: String, Codable, Hashable {
        case notification
        case email
        case sms
    }
}

enum EventStatus: String, Codable, Hashable {
    case confirmed
    case tentative
    case cancelled
}

enum Availability: String, Codable, Hashable {
    case busy
    case free
    case tentative
}

// MARK: - Conflict Detection
extension CalendarEvent {
    func conflicts(with other: CalendarEvent) -> Bool {
        guard status != .cancelled && other.status != .cancelled else { return false }
        guard availability == .busy && other.availability == .busy else { return false }

        // Check for overlap
        return startDate < other.endDate && endDate > other.startDate
    }
}

// MARK: - Travel Time
extension CalendarEvent {
    /// Estimated travel time to location (placeholder - would use MapKit)
    func estimatedTravelTime(from currentLocation: String?) -> TimeInterval? {
        guard location != nil else { return nil }
        // Would integrate with MapKit for real travel time
        return 30 * 60 // Default 30 minutes
    }
}
