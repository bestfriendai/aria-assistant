import Foundation

/// Package tracking model
struct Package: Identifiable, Codable, Hashable {
    let id: UUID
    let trackingNumber: String
    let carrier: Carrier

    var description: String?
    var merchantName: String?
    var merchantOrderId: String?

    var status: PackageStatus
    var statusDescription: String?

    var estimatedDelivery: Date?
    var actualDelivery: Date?

    var origin: Address?
    var destination: Address?
    var currentLocation: String?

    var events: [TrackingEvent]

    var weight: String?
    var dimensions: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        trackingNumber: String,
        carrier: Carrier,
        description: String? = nil,
        merchantName: String? = nil,
        merchantOrderId: String? = nil,
        status: PackageStatus = .unknown,
        statusDescription: String? = nil,
        estimatedDelivery: Date? = nil,
        actualDelivery: Date? = nil,
        origin: Address? = nil,
        destination: Address? = nil,
        currentLocation: String? = nil,
        events: [TrackingEvent] = [],
        weight: String? = nil,
        dimensions: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.trackingNumber = trackingNumber
        self.carrier = carrier
        self.description = description
        self.merchantName = merchantName
        self.merchantOrderId = merchantOrderId
        self.status = status
        self.statusDescription = statusDescription
        self.estimatedDelivery = estimatedDelivery
        self.actualDelivery = actualDelivery
        self.origin = origin
        self.destination = destination
        self.currentLocation = currentLocation
        self.events = events
        self.weight = weight
        self.dimensions = dimensions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isActive: Bool {
        switch status {
        case .delivered, .returned, .cancelled, .expired:
            return false
        default:
            return true
        }
    }

    var daysUntilDelivery: Int? {
        guard let estimated = estimatedDelivery else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: estimated).day
    }

    var isDelayed: Bool {
        guard let estimated = estimatedDelivery else { return false }
        return estimated < Date() && status != .delivered
    }
}

enum Carrier: String, Codable, CaseIterable {
    case ups = "UPS"
    case fedex = "FedEx"
    case usps = "USPS"
    case dhl = "DHL"
    case amazon = "Amazon"
    case ontrac = "OnTrac"
    case lasership = "LaserShip"
    case other = "Other"

    var trackingURLTemplate: String? {
        switch self {
        case .ups:
            return "https://www.ups.com/track?tracknum=%@"
        case .fedex:
            return "https://www.fedex.com/fedextrack/?trknbr=%@"
        case .usps:
            return "https://tools.usps.com/go/TrackConfirmAction?tLabels=%@"
        case .dhl:
            return "https://www.dhl.com/us-en/home/tracking.html?tracking-id=%@"
        case .amazon:
            return nil // Amazon uses internal tracking
        default:
            return nil
        }
    }

    var icon: String {
        switch self {
        case .ups: return "shippingbox.fill"
        case .fedex: return "box.truck.fill"
        case .usps: return "envelope.fill"
        case .dhl: return "airplane"
        case .amazon: return "shippingbox"
        default: return "shippingbox"
        }
    }
}

enum PackageStatus: String, Codable {
    case unknown
    case pending
    case infoReceived = "info_received"
    case inTransit = "in_transit"
    case outForDelivery = "out_for_delivery"
    case attemptFail = "attempt_fail"
    case delivered
    case availableForPickup = "available_for_pickup"
    case returned
    case cancelled
    case expired

    var displayText: String {
        switch self {
        case .unknown: return "Unknown"
        case .pending: return "Pending"
        case .infoReceived: return "Label Created"
        case .inTransit: return "In Transit"
        case .outForDelivery: return "Out for Delivery"
        case .attemptFail: return "Delivery Attempted"
        case .delivered: return "Delivered"
        case .availableForPickup: return "Ready for Pickup"
        case .returned: return "Returned"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        }
    }

    var icon: String {
        switch self {
        case .delivered: return "checkmark.circle.fill"
        case .outForDelivery: return "truck.box.fill"
        case .inTransit: return "arrow.triangle.swap"
        case .attemptFail: return "exclamationmark.triangle.fill"
        default: return "shippingbox"
        }
    }
}

struct TrackingEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let status: PackageStatus
    let description: String
    let location: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        status: PackageStatus,
        description: String,
        location: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.description = description
        self.location = location
    }
}

struct Address: Codable, Hashable {
    var street: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?

    var formatted: String {
        [city, state, postalCode].compactMap { $0 }.joined(separator: ", ")
    }
}
