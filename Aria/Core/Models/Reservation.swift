import Foundation

/// Restaurant reservation model
struct RestaurantReservation: Identifiable, Codable, Hashable {
    let id: UUID
    let source: ReservationSource

    var restaurantName: String
    var restaurantAddress: String?
    var restaurantPhone: String?
    var cuisineType: String?
    var priceRange: PriceRange?

    var dateTime: Date
    var partySize: Int
    var confirmationNumber: String?

    var tableType: String? // "outdoor", "bar", "booth"
    var specialRequests: String?

    var status: ReservationStatus
    var reminderSet: Bool

    var latitude: Double?
    var longitude: Double?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        source: ReservationSource = .manual,
        restaurantName: String,
        restaurantAddress: String? = nil,
        restaurantPhone: String? = nil,
        cuisineType: String? = nil,
        priceRange: PriceRange? = nil,
        dateTime: Date,
        partySize: Int = 2,
        confirmationNumber: String? = nil,
        tableType: String? = nil,
        specialRequests: String? = nil,
        status: ReservationStatus = .confirmed,
        reminderSet: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.restaurantName = restaurantName
        self.restaurantAddress = restaurantAddress
        self.restaurantPhone = restaurantPhone
        self.cuisineType = cuisineType
        self.priceRange = priceRange
        self.dateTime = dateTime
        self.partySize = partySize
        self.confirmationNumber = confirmationNumber
        self.tableType = tableType
        self.specialRequests = specialRequests
        self.status = status
        self.reminderSet = reminderSet
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isUpcoming: Bool {
        dateTime > Date() && status == .confirmed
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(dateTime)
    }

    var minutesUntil: Int? {
        guard isUpcoming else { return nil }
        return Int(dateTime.timeIntervalSinceNow / 60)
    }

    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: dateTime)
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: dateTime)
    }
}

enum ReservationSource: String, Codable {
    case openTable = "opentable"
    case resy
    case yelp
    case manual
    case email // Extracted from email

    var displayName: String {
        switch self {
        case .openTable: return "OpenTable"
        case .resy: return "Resy"
        case .yelp: return "Yelp"
        case .manual: return "Manual"
        case .email: return "Email"
        }
    }
}

enum ReservationStatus: String, Codable {
    case pending
    case confirmed
    case cancelled
    case completed
    case noShow = "no_show"
}

enum PriceRange: Int, Codable {
    case low = 1 // $
    case medium = 2 // $$
    case high = 3 // $$$
    case veryHigh = 4 // $$$$

    var displayText: String {
        String(repeating: "$", count: rawValue)
    }
}

/// Ride/Transportation booking
struct RideBooking: Identifiable, Codable, Hashable {
    let id: UUID
    let service: RideService

    var pickupLocation: String
    var pickupLatitude: Double
    var pickupLongitude: Double

    var dropoffLocation: String
    var dropoffLatitude: Double
    var dropoffLongitude: Double

    var requestedTime: Date
    var estimatedPickupTime: Date?
    var estimatedArrivalTime: Date?
    var actualPickupTime: Date?
    var actualArrivalTime: Date?

    var status: RideStatus
    var rideType: String // "UberX", "Lyft", etc.

    var estimatedPrice: Decimal?
    var actualPrice: Decimal?
    var currency: String

    var driverName: String?
    var driverRating: Double?
    var vehicleInfo: String? // "White Toyota Camry"
    var licensePlate: String?

    var surgeMultiplier: Double?
    var promoCode: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        service: RideService,
        pickupLocation: String,
        pickupLatitude: Double,
        pickupLongitude: Double,
        dropoffLocation: String,
        dropoffLatitude: Double,
        dropoffLongitude: Double,
        requestedTime: Date = Date(),
        estimatedPickupTime: Date? = nil,
        estimatedArrivalTime: Date? = nil,
        actualPickupTime: Date? = nil,
        actualArrivalTime: Date? = nil,
        status: RideStatus = .requested,
        rideType: String = "Standard",
        estimatedPrice: Decimal? = nil,
        actualPrice: Decimal? = nil,
        currency: String = "USD",
        driverName: String? = nil,
        driverRating: Double? = nil,
        vehicleInfo: String? = nil,
        licensePlate: String? = nil,
        surgeMultiplier: Double? = nil,
        promoCode: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.service = service
        self.pickupLocation = pickupLocation
        self.pickupLatitude = pickupLatitude
        self.pickupLongitude = pickupLongitude
        self.dropoffLocation = dropoffLocation
        self.dropoffLatitude = dropoffLatitude
        self.dropoffLongitude = dropoffLongitude
        self.requestedTime = requestedTime
        self.estimatedPickupTime = estimatedPickupTime
        self.estimatedArrivalTime = estimatedArrivalTime
        self.actualPickupTime = actualPickupTime
        self.actualArrivalTime = actualArrivalTime
        self.status = status
        self.rideType = rideType
        self.estimatedPrice = estimatedPrice
        self.actualPrice = actualPrice
        self.currency = currency
        self.driverName = driverName
        self.driverRating = driverRating
        self.vehicleInfo = vehicleInfo
        self.licensePlate = licensePlate
        self.surgeMultiplier = surgeMultiplier
        self.promoCode = promoCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isActive: Bool {
        switch status {
        case .requested, .accepted, .driverEnRoute, .driverArrived, .inProgress:
            return true
        default:
            return false
        }
    }

    var minutesUntilPickup: Int? {
        guard let pickup = estimatedPickupTime else { return nil }
        return Int(pickup.timeIntervalSinceNow / 60)
    }

    var hasSurge: Bool {
        (surgeMultiplier ?? 1.0) > 1.0
    }
}

enum RideService: String, Codable {
    case uber
    case lyft

    var displayName: String {
        switch self {
        case .uber: return "Uber"
        case .lyft: return "Lyft"
        }
    }

    var icon: String {
        "car.fill"
    }
}

enum RideStatus: String, Codable {
    case requested
    case accepted
    case driverEnRoute = "driver_en_route"
    case driverArrived = "driver_arrived"
    case inProgress = "in_progress"
    case completed
    case cancelled
    case noDriversAvailable = "no_drivers"

    var displayText: String {
        switch self {
        case .requested: return "Finding driver..."
        case .accepted: return "Driver assigned"
        case .driverEnRoute: return "Driver on the way"
        case .driverArrived: return "Driver arrived"
        case .inProgress: return "Trip in progress"
        case .completed: return "Trip completed"
        case .cancelled: return "Cancelled"
        case .noDriversAvailable: return "No drivers available"
        }
    }
}
