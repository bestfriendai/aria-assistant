import Foundation

/// Flight tracking model
struct Flight: Identifiable, Codable, Hashable {
    let id: UUID
    let flightNumber: String
    let airline: Airline

    var departureAirport: Airport
    var arrivalAirport: Airport

    var scheduledDeparture: Date
    var scheduledArrival: Date
    var actualDeparture: Date?
    var actualArrival: Date?
    var estimatedDeparture: Date?
    var estimatedArrival: Date?

    var status: FlightStatus
    var gate: String?
    var terminal: String?
    var boardingTime: Date?

    var aircraft: String?
    var seatNumber: String?
    var confirmationCode: String?

    var baggageClaim: String?

    var delayMinutes: Int?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        flightNumber: String,
        airline: Airline,
        departureAirport: Airport,
        arrivalAirport: Airport,
        scheduledDeparture: Date,
        scheduledArrival: Date,
        actualDeparture: Date? = nil,
        actualArrival: Date? = nil,
        estimatedDeparture: Date? = nil,
        estimatedArrival: Date? = nil,
        status: FlightStatus = .scheduled,
        gate: String? = nil,
        terminal: String? = nil,
        boardingTime: Date? = nil,
        aircraft: String? = nil,
        seatNumber: String? = nil,
        confirmationCode: String? = nil,
        baggageClaim: String? = nil,
        delayMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.flightNumber = flightNumber
        self.airline = airline
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.actualDeparture = actualDeparture
        self.actualArrival = actualArrival
        self.estimatedDeparture = estimatedDeparture
        self.estimatedArrival = estimatedArrival
        self.status = status
        self.gate = gate
        self.terminal = terminal
        self.boardingTime = boardingTime
        self.aircraft = aircraft
        self.seatNumber = seatNumber
        self.confirmationCode = confirmationCode
        self.baggageClaim = baggageClaim
        self.delayMinutes = delayMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayFlightNumber: String {
        "\(airline.iataCode)\(flightNumber)"
    }

    var isDelayed: Bool {
        (delayMinutes ?? 0) > 15
    }

    var effectiveDeparture: Date {
        estimatedDeparture ?? actualDeparture ?? scheduledDeparture
    }

    var effectiveArrival: Date {
        estimatedArrival ?? actualArrival ?? scheduledArrival
    }

    var duration: TimeInterval {
        effectiveArrival.timeIntervalSince(effectiveDeparture)
    }

    var durationFormatted: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }

    var isUpcoming: Bool {
        effectiveDeparture > Date() && status != .cancelled
    }

    var minutesUntilDeparture: Int? {
        guard isUpcoming else { return nil }
        return Int(effectiveDeparture.timeIntervalSinceNow / 60)
    }
}

struct Airline: Codable, Hashable {
    let name: String
    let iataCode: String
    let icaoCode: String?
    let logoUrl: String?
}

struct Airport: Codable, Hashable {
    let code: String // IATA code
    let name: String
    let city: String
    let country: String
    let timezone: String?
    let latitude: Double?
    let longitude: Double?

    var displayName: String {
        "\(city) (\(code))"
    }
}

enum FlightStatus: String, Codable {
    case scheduled
    case boarding
    case departed
    case enRoute = "en_route"
    case landed
    case arrived
    case delayed
    case cancelled
    case diverted

    var displayText: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .boarding: return "Boarding"
        case .departed: return "Departed"
        case .enRoute: return "In Flight"
        case .landed: return "Landed"
        case .arrived: return "Arrived"
        case .delayed: return "Delayed"
        case .cancelled: return "Cancelled"
        case .diverted: return "Diverted"
        }
    }

    var icon: String {
        switch self {
        case .enRoute: return "airplane"
        case .boarding: return "figure.walk"
        case .departed, .landed: return "airplane.departure"
        case .arrived: return "airplane.arrival"
        case .delayed: return "clock.badge.exclamationmark"
        case .cancelled: return "xmark.circle"
        case .diverted: return "arrow.triangle.branch"
        default: return "airplane"
        }
    }
}

/// Trip/Itinerary model
struct Trip: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var destination: String

    var startDate: Date
    var endDate: Date

    var flights: [Flight]
    var hotels: [HotelReservation]
    var carRentals: [CarRental]
    var activities: [TripActivity]

    var notes: String?
    var documents: [TripDocument]

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        flights: [Flight] = [],
        hotels: [HotelReservation] = [],
        carRentals: [CarRental] = [],
        activities: [TripActivity] = [],
        notes: String? = nil,
        documents: [TripDocument] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.flights = flights
        self.hotels = hotels
        self.carRentals = carRentals
        self.activities = activities
        self.notes = notes
        self.documents = documents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isUpcoming: Bool {
        startDate > Date()
    }

    var isActive: Bool {
        let now = Date()
        return startDate <= now && endDate >= now
    }

    var daysUntilStart: Int? {
        guard isUpcoming else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: startDate).day
    }

    var duration: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
}

struct HotelReservation: Identifiable, Codable, Hashable {
    let id: UUID
    let hotelName: String
    let address: String

    var checkIn: Date
    var checkOut: Date

    var confirmationNumber: String?
    var roomType: String?
    var totalCost: Decimal?

    var phoneNumber: String?
    var website: String?

    var notes: String?
}

struct CarRental: Identifiable, Codable, Hashable {
    let id: UUID
    let company: String

    var pickupLocation: String
    var pickupTime: Date
    var dropoffLocation: String
    var dropoffTime: Date

    var confirmationNumber: String?
    var carType: String?
    var totalCost: Decimal?

    var notes: String?
}

struct TripActivity: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var location: String?
    var dateTime: Date
    var duration: TimeInterval?
    var confirmationNumber: String?
    var cost: Decimal?
    var notes: String?
}

struct TripDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: DocumentType
    var fileUrl: String
    var addedAt: Date

    enum DocumentType: String, Codable {
        case passport
        case visa
        case insurance
        case confirmation
        case ticket
        case other
    }
}
