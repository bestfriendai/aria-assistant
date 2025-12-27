import Foundation
import CoreLocation

/// Location-aware features
struct UserLocation: Codable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var accuracy: Double
    var timestamp: Date

    var placemark: Placemark?
    var semanticLocation: SemanticLocation?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Placemark: Codable {
    var name: String?
    var thoroughfare: String? // Street
    var subThoroughfare: String? // Street number
    var locality: String? // City
    var subLocality: String? // Neighborhood
    var administrativeArea: String? // State
    var postalCode: String?
    var country: String?
    var isoCountryCode: String?

    var formattedAddress: String {
        var parts: [String] = []
        if let street = thoroughfare {
            if let number = subThoroughfare {
                parts.append("\(number) \(street)")
            } else {
                parts.append(street)
            }
        }
        if let city = locality {
            parts.append(city)
        }
        if let state = administrativeArea {
            parts.append(state)
        }
        return parts.joined(separator: ", ")
    }

    var shortAddress: String {
        if let name = name, !name.isEmpty {
            return name
        }
        return locality ?? administrativeArea ?? "Unknown"
    }
}

enum SemanticLocation: String, Codable {
    case home
    case work
    case gym
    case grocery
    case restaurant
    case cafe
    case shopping
    case medical
    case transit
    case airport
    case hotel
    case other

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        case .gym: return "figure.strengthtraining.traditional"
        case .grocery: return "cart.fill"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .shopping: return "bag.fill"
        case .medical: return "cross.case.fill"
        case .transit: return "tram.fill"
        case .airport: return "airplane"
        case .hotel: return "bed.double.fill"
        case .other: return "mappin"
        }
    }
}

/// Saved/frequent locations
struct SavedLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: SemanticLocation
    var latitude: Double
    var longitude: Double
    var address: String?
    var radius: Double // meters, for geofence

    var arrivalReminders: [LocationReminder]
    var departureReminders: [LocationReminder]

    var visitCount: Int
    var lastVisited: Date?
    var averageVisitDuration: TimeInterval?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: SemanticLocation = .other,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        radius: Double = 100,
        arrivalReminders: [LocationReminder] = [],
        departureReminders: [LocationReminder] = [],
        visitCount: Int = 0,
        lastVisited: Date? = nil,
        averageVisitDuration: TimeInterval? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.radius = radius
        self.arrivalReminders = arrivalReminders
        self.departureReminders = departureReminders
        self.visitCount = visitCount
        self.lastVisited = lastVisited
        self.averageVisitDuration = averageVisitDuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from location: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let to = CLLocation(latitude: latitude, longitude: longitude)
        return from.distance(from: to)
    }

    func contains(_ location: CLLocationCoordinate2D) -> Bool {
        distance(from: location) <= radius
    }
}

/// Location-based reminder
struct LocationReminder: Identifiable, Codable, Hashable {
    let id: UUID
    var taskId: UUID?
    var title: String
    var notes: String?
    var triggerType: TriggerType
    var isActive: Bool
    var lastTriggered: Date?

    init(
        id: UUID = UUID(),
        taskId: UUID? = nil,
        title: String,
        notes: String? = nil,
        triggerType: TriggerType,
        isActive: Bool = true,
        lastTriggered: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.title = title
        self.notes = notes
        self.triggerType = triggerType
        self.isActive = isActive
        self.lastTriggered = lastTriggered
    }

    enum TriggerType: String, Codable, Hashable {
        case onArrival = "on_arrival"
        case onDeparture = "on_departure"
    }
}

/// Commute/route information
struct CommuteRoute: Identifiable, Codable {
    let id: UUID
    var name: String // "Work commute"
    var origin: SavedLocation
    var destination: SavedLocation

    var usualDepartureTime: Date?
    var usualArrivalTime: Date?
    var transportMode: TransportMode

    var averageDuration: TimeInterval
    var currentDuration: TimeInterval?
    var currentTrafficCondition: TrafficCondition?

    var lastChecked: Date?

    var delayMinutes: Int? {
        guard let current = currentDuration else { return nil }
        let delay = current - averageDuration
        return delay > 60 ? Int(delay / 60) : nil
    }

    var shouldLeaveNow: Bool {
        guard let departureTime = usualDepartureTime,
              let delay = delayMinutes else { return false }
        let adjustedDeparture = departureTime.addingTimeInterval(-Double(delay * 60))
        return Date() >= adjustedDeparture
    }
}

enum TransportMode: String, Codable {
    case driving
    case transit
    case walking
    case cycling

    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .transit: return "tram.fill"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        }
    }
}

enum TrafficCondition: String, Codable {
    case light
    case moderate
    case heavy
    case severe

    var color: String {
        switch self {
        case .light: return "green"
        case .moderate: return "yellow"
        case .heavy: return "orange"
        case .severe: return "red"
        }
    }
}

/// Parking information
struct ParkingSession: Identifiable, Codable {
    let id: UUID
    var location: SavedLocation?
    var latitude: Double
    var longitude: Double
    var address: String?

    var parkedAt: Date
    var expiresAt: Date?
    var meterNumber: String?
    var lotName: String?
    var spotNumber: String?
    var level: String? // Floor/level in garage

    var photoUrl: String? // Photo of spot for reference
    var notes: String?

    var isActive: Bool
    var reminderSet: Bool
    var reminderMinutesBefore: Int?

    init(
        id: UUID = UUID(),
        location: SavedLocation? = nil,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        parkedAt: Date = Date(),
        expiresAt: Date? = nil,
        meterNumber: String? = nil,
        lotName: String? = nil,
        spotNumber: String? = nil,
        level: String? = nil,
        photoUrl: String? = nil,
        notes: String? = nil,
        isActive: Bool = true,
        reminderSet: Bool = false,
        reminderMinutesBefore: Int? = nil
    ) {
        self.id = id
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.parkedAt = parkedAt
        self.expiresAt = expiresAt
        self.meterNumber = meterNumber
        self.lotName = lotName
        self.spotNumber = spotNumber
        self.level = level
        self.photoUrl = photoUrl
        self.notes = notes
        self.isActive = isActive
        self.reminderSet = reminderSet
        self.reminderMinutesBefore = reminderMinutesBefore
    }

    var isExpiringSoon: Bool {
        guard let expires = expiresAt else { return false }
        let minutesUntilExpiry = Calendar.current.dateComponents([.minute], from: Date(), to: expires).minute ?? 0
        return minutesUntilExpiry <= 15 && minutesUntilExpiry > 0
    }

    var isExpired: Bool {
        guard let expires = expiresAt else { return false }
        return expires < Date()
    }

    var minutesUntilExpiry: Int? {
        guard let expires = expiresAt else { return nil }
        return Calendar.current.dateComponents([.minute], from: Date(), to: expires).minute
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
