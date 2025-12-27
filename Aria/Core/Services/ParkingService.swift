import Foundation
import CoreLocation

/// Parking service for finding and paying for parking
actor ParkingService {
    // MARK: - Configuration

    private var spotHeroApiKey: String?
    private var parkWhizApiKey: String?
    private var parkMobileApiKey: String?

    // MARK: - Cache

    private var activeSessionsCache: [ParkingSession] = []
    private var savedLocationsCache: [SavedParkingLocation] = []

    // MARK: - Configuration

    func configure(
        spotHeroApiKey: String? = nil,
        parkWhizApiKey: String? = nil,
        parkMobileApiKey: String? = nil
    ) {
        self.spotHeroApiKey = spotHeroApiKey
        self.parkWhizApiKey = parkWhizApiKey
        self.parkMobileApiKey = parkMobileApiKey
    }

    // MARK: - Find Parking

    func findParking(
        near location: CLLocation,
        startTime: Date = Date(),
        duration: TimeInterval = 3600, // 1 hour default
        vehicleType: VehicleType = .sedan
    ) async throws -> [ParkingSpot] {
        var allSpots: [ParkingSpot] = []

        // Try SpotHero
        if let apiKey = spotHeroApiKey {
            let spotHeroSpots = try await searchSpotHero(
                location: location,
                startTime: startTime,
                duration: duration,
                apiKey: apiKey
            )
            allSpots.append(contentsOf: spotHeroSpots)
        }

        // Try ParkWhiz
        if let apiKey = parkWhizApiKey {
            let parkWhizSpots = try await searchParkWhiz(
                location: location,
                startTime: startTime,
                duration: duration,
                apiKey: apiKey
            )
            allSpots.append(contentsOf: parkWhizSpots)
        }

        // Sort by distance and price
        return allSpots.sorted { spot1, spot2 in
            let dist1 = spot1.location.distance(from: location)
            let dist2 = spot2.location.distance(from: location)

            // Prioritize closer spots, then cheaper
            if abs(dist1 - dist2) > 100 {
                return dist1 < dist2
            }
            return spot1.price < spot2.price
        }
    }

    func findParkingNearDestination(
        destination: CLLocation,
        arrivalTime: Date,
        duration: TimeInterval
    ) async throws -> [ParkingSpot] {
        try await findParking(
            near: destination,
            startTime: arrivalTime,
            duration: duration
        )
    }

    func findEventParking(
        venueName: String,
        venueLocation: CLLocation,
        eventTime: Date
    ) async throws -> [ParkingSpot] {
        // Search for parking that ends after typical event duration
        let duration: TimeInterval = 4 * 3600 // 4 hours for events
        return try await findParking(
            near: venueLocation,
            startTime: eventTime.addingTimeInterval(-3600), // Arrive 1 hour early
            duration: duration
        )
    }

    // MARK: - Reservations

    func reserveSpot(
        _ spot: ParkingSpot,
        startTime: Date,
        endTime: Date,
        vehicleInfo: VehicleInfo? = nil
    ) async throws -> ParkingReservation {
        switch spot.provider {
        case .spotHero:
            return try await reserveSpotHero(spot: spot, startTime: startTime, endTime: endTime)
        case .parkWhiz:
            return try await reserveParkWhiz(spot: spot, startTime: startTime, endTime: endTime)
        case .parkMobile:
            return try await reserveParkMobile(spot: spot, startTime: startTime, endTime: endTime)
        case .direct:
            throw ParkingError.reservationNotSupported
        }
    }

    private func reserveSpotHero(spot: ParkingSpot, startTime: Date, endTime: Date) async throws -> ParkingReservation {
        guard let apiKey = spotHeroApiKey else {
            throw ParkingError.notConfigured
        }

        // SpotHero reservation API
        let url = URL(string: "https://api.spothero.com/v2/reservations")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            "facility_id": spot.externalId,
            "starts": formatter.string(from: startTime),
            "ends": formatter.string(from: endTime)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw ParkingError.reservationFailed
        }

        return try parseSpotHeroReservation(data, spot: spot)
    }

    private func reserveParkWhiz(spot: ParkingSpot, startTime: Date, endTime: Date) async throws -> ParkingReservation {
        // ParkWhiz implementation
        throw ParkingError.reservationFailed
    }

    private func reserveParkMobile(spot: ParkingSpot, startTime: Date, endTime: Date) async throws -> ParkingReservation {
        // ParkMobile implementation
        throw ParkingError.reservationFailed
    }

    func cancelReservation(_ reservation: ParkingReservation) async throws {
        switch reservation.provider {
        case .spotHero:
            try await cancelSpotHeroReservation(reservation)
        case .parkWhiz:
            try await cancelParkWhizReservation(reservation)
        case .parkMobile:
            try await cancelParkMobileReservation(reservation)
        case .direct:
            throw ParkingError.cancellationNotSupported
        }
    }

    private func cancelSpotHeroReservation(_ reservation: ParkingReservation) async throws {
        guard let apiKey = spotHeroApiKey else {
            throw ParkingError.notConfigured
        }

        let url = URL(string: "https://api.spothero.com/v2/reservations/\(reservation.confirmationCode)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParkingError.cancellationFailed
        }
    }

    private func cancelParkWhizReservation(_ reservation: ParkingReservation) async throws {
        // Implementation
    }

    private func cancelParkMobileReservation(_ reservation: ParkingReservation) async throws {
        // Implementation
    }

    // MARK: - Active Sessions

    func startSession(
        at spot: ParkingSpot,
        vehicleInfo: VehicleInfo? = nil,
        duration: TimeInterval? = nil
    ) async throws -> ParkingSession {
        let session = ParkingSession(
            spot: spot,
            startTime: Date(),
            endTime: duration.map { Date().addingTimeInterval($0) },
            vehicleInfo: vehicleInfo,
            status: .active
        )

        activeSessionsCache.append(session)
        return session
    }

    func extendSession(_ session: ParkingSession, additionalTime: TimeInterval) async throws -> ParkingSession {
        guard let index = activeSessionsCache.firstIndex(where: { $0.id == session.id }) else {
            throw ParkingError.sessionNotFound
        }

        var updated = session
        if let currentEnd = updated.endTime {
            updated.endTime = currentEnd.addingTimeInterval(additionalTime)
        } else {
            updated.endTime = Date().addingTimeInterval(additionalTime)
        }

        // If using ParkMobile or similar, extend via API
        if session.spot.provider == .parkMobile {
            try await extendParkMobileSession(session, additionalTime: additionalTime)
        }

        activeSessionsCache[index] = updated
        return updated
    }

    private func extendParkMobileSession(_ session: ParkingSession, additionalTime: TimeInterval) async throws {
        // ParkMobile extension API
    }

    func endSession(_ session: ParkingSession) async throws -> ParkingSession {
        guard let index = activeSessionsCache.firstIndex(where: { $0.id == session.id }) else {
            throw ParkingError.sessionNotFound
        }

        var updated = session
        updated.endTime = Date()
        updated.status = .completed

        activeSessionsCache[index] = updated
        return updated
    }

    func getActiveSessions() async -> [ParkingSession] {
        activeSessionsCache.filter { $0.status == .active }
    }

    func getCurrentSession() async -> ParkingSession? {
        activeSessionsCache.first { $0.status == .active }
    }

    // MARK: - Remember Parking

    func saveCurrentLocation(location: CLLocation, notes: String? = nil) async -> SavedParkingLocation {
        let saved = SavedParkingLocation(
            location: location,
            savedAt: Date(),
            notes: notes
        )

        savedLocationsCache.append(saved)
        return saved
    }

    func getLastSavedLocation() async -> SavedParkingLocation? {
        savedLocationsCache.last
    }

    func clearSavedLocation() async {
        savedLocationsCache.removeAll()
    }

    func getDirectionsToParkedCar() async -> URL? {
        guard let saved = savedLocationsCache.last else { return nil }

        var components = URLComponents(string: "http://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(saved.location.coordinate.latitude),\(saved.location.coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: "w") // Walking directions
        ]

        return components.url
    }

    // MARK: - Provider Search

    private func searchSpotHero(
        location: CLLocation,
        startTime: Date,
        duration: TimeInterval,
        apiKey: String
    ) async throws -> [ParkingSpot] {
        let formatter = ISO8601DateFormatter()
        let endTime = startTime.addingTimeInterval(duration)

        let url = URL(string: "https://api.spothero.com/v2/search/facilities")!
            .appending(queryItems: [
                URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
                URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
                URLQueryItem(name: "starts", value: formatter.string(from: startTime)),
                URLQueryItem(name: "ends", value: formatter.string(from: endTime))
            ])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseSpotHeroResults(data)
    }

    private func searchParkWhiz(
        location: CLLocation,
        startTime: Date,
        duration: TimeInterval,
        apiKey: String
    ) async throws -> [ParkingSpot] {
        let formatter = ISO8601DateFormatter()
        let endTime = startTime.addingTimeInterval(duration)

        let url = URL(string: "https://api.parkwhiz.com/v4/quotes/")!
            .appending(queryItems: [
                URLQueryItem(name: "lat", value: String(location.coordinate.latitude)),
                URLQueryItem(name: "lng", value: String(location.coordinate.longitude)),
                URLQueryItem(name: "start_time", value: formatter.string(from: startTime)),
                URLQueryItem(name: "end_time", value: formatter.string(from: endTime))
            ])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseParkWhizResults(data)
    }

    // MARK: - Parsing

    private func parseSpotHeroResults(_ data: Data) throws -> [ParkingSpot] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let facilities = json["results"] as? [[String: Any]] else {
            throw ParkingError.parseError
        }

        return facilities.compactMap { facility -> ParkingSpot? in
            guard let id = facility["id"] as? String,
                  let name = facility["title"] as? String,
                  let location = facility["location"] as? [String: Any],
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double,
                  let pricing = facility["pricing"] as? [String: Any],
                  let price = pricing["price"] as? Double else {
                return nil
            }

            return ParkingSpot(
                externalId: id,
                name: name,
                address: facility["address"] as? String ?? "",
                latitude: lat,
                longitude: lng,
                price: price,
                provider: .spotHero,
                type: parseSpotType(facility["type"] as? String),
                amenities: parseAmenities(facility["amenities"] as? [String]),
                totalSpaces: facility["capacity"] as? Int,
                availableSpaces: facility["available"] as? Int,
                distanceMeters: facility["distance"] as? Double
            )
        }
    }

    private func parseParkWhizResults(_ data: Data) throws -> [ParkingSpot] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ParkingError.parseError
        }

        return json.compactMap { quote -> ParkingSpot? in
            guard let id = quote["id"] as? String,
                  let location = quote["location"] as? [String: Any],
                  let name = location["name"] as? String,
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double,
                  let pricing = quote["purchase_options"] as? [[String: Any]],
                  let price = pricing.first?["price"] as? [String: Any],
                  let priceAmount = price["USD"] as? Double else {
                return nil
            }

            return ParkingSpot(
                externalId: id,
                name: name,
                address: location["address1"] as? String ?? "",
                latitude: lat,
                longitude: lng,
                price: priceAmount,
                provider: .parkWhiz,
                type: .garage,
                amenities: [],
                distanceMeters: quote["distance"] as? Double
            )
        }
    }

    private func parseSpotHeroReservation(_ data: Data, spot: ParkingSpot) throws -> ParkingReservation {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let confirmationCode = json["confirmation_code"] as? String else {
            throw ParkingError.parseError
        }

        let formatter = ISO8601DateFormatter()
        let startTime = formatter.date(from: json["starts"] as? String ?? "") ?? Date()
        let endTime = formatter.date(from: json["ends"] as? String ?? "") ?? Date()

        return ParkingReservation(
            spot: spot,
            confirmationCode: confirmationCode,
            startTime: startTime,
            endTime: endTime,
            totalPrice: json["total"] as? Double ?? spot.price,
            provider: .spotHero,
            qrCodeUrl: json["qr_code_url"] as? String,
            instructions: json["instructions"] as? String
        )
    }

    private func parseSpotType(_ type: String?) -> ParkingSpotType {
        switch type?.lowercased() {
        case "garage": return .garage
        case "lot": return .lot
        case "street": return .street
        case "valet": return .valet
        default: return .garage
        }
    }

    private func parseAmenities(_ amenities: [String]?) -> [ParkingAmenity] {
        guard let amenities = amenities else { return [] }

        return amenities.compactMap { amenity -> ParkingAmenity? in
            switch amenity.lowercased() {
            case "covered": return .covered
            case "ev_charging", "electric": return .evCharging
            case "handicap", "accessible": return .handicapAccessible
            case "24_hour", "24/7": return .twentyFourHour
            case "security": return .security
            case "attended": return .attended
            case "restroom": return .restroom
            default: return nil
            }
        }
    }

    // MARK: - Alerts

    func getSessionAlerts() async -> [ParkingAlert] {
        var alerts: [ParkingAlert] = []

        for session in activeSessionsCache where session.status == .active {
            guard let endTime = session.endTime else { continue }

            let minutesRemaining = endTime.timeIntervalSinceNow / 60

            if minutesRemaining <= 0 {
                alerts.append(ParkingAlert(
                    session: session,
                    type: .expired,
                    message: "Your parking has expired!"
                ))
            } else if minutesRemaining <= 15 {
                alerts.append(ParkingAlert(
                    session: session,
                    type: .expiringSoon,
                    message: "Parking expires in \(Int(minutesRemaining)) minutes"
                ))
            }
        }

        return alerts
    }
}

// MARK: - Models

struct ParkingSpot: Identifiable, Codable {
    let id: UUID
    let externalId: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var price: Double
    var provider: ParkingProvider
    var type: ParkingSpotType
    var amenities: [ParkingAmenity]
    var totalSpaces: Int?
    var availableSpaces: Int?
    var distanceMeters: Double?
    var operatingHours: String?
    var heightLimit: String?

    init(
        id: UUID = UUID(),
        externalId: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        price: Double,
        provider: ParkingProvider,
        type: ParkingSpotType,
        amenities: [ParkingAmenity] = [],
        totalSpaces: Int? = nil,
        availableSpaces: Int? = nil,
        distanceMeters: Double? = nil,
        operatingHours: String? = nil,
        heightLimit: String? = nil
    ) {
        self.id = id
        self.externalId = externalId
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.price = price
        self.provider = provider
        self.type = type
        self.amenities = amenities
        self.totalSpaces = totalSpaces
        self.availableSpaces = availableSpaces
        self.distanceMeters = distanceMeters
        self.operatingHours = operatingHours
        self.heightLimit = heightLimit
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var distanceString: String {
        guard let meters = distanceMeters else { return "" }
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }

    var priceString: String {
        String(format: "$%.2f", price)
    }
}

struct ParkingReservation: Identifiable, Codable {
    let id: UUID
    let spot: ParkingSpot
    let confirmationCode: String
    let startTime: Date
    let endTime: Date
    let totalPrice: Double
    let provider: ParkingProvider
    var qrCodeUrl: String?
    var instructions: String?
    var vehicleInfo: VehicleInfo?

    init(
        id: UUID = UUID(),
        spot: ParkingSpot,
        confirmationCode: String,
        startTime: Date,
        endTime: Date,
        totalPrice: Double,
        provider: ParkingProvider,
        qrCodeUrl: String? = nil,
        instructions: String? = nil,
        vehicleInfo: VehicleInfo? = nil
    ) {
        self.id = id
        self.spot = spot
        self.confirmationCode = confirmationCode
        self.startTime = startTime
        self.endTime = endTime
        self.totalPrice = totalPrice
        self.provider = provider
        self.qrCodeUrl = qrCodeUrl
        self.instructions = instructions
        self.vehicleInfo = vehicleInfo
    }
}

struct ParkingSession: Identifiable, Codable {
    let id: UUID
    let spot: ParkingSpot
    let startTime: Date
    var endTime: Date?
    var vehicleInfo: VehicleInfo?
    var status: SessionStatus

    init(
        id: UUID = UUID(),
        spot: ParkingSpot,
        startTime: Date,
        endTime: Date? = nil,
        vehicleInfo: VehicleInfo? = nil,
        status: SessionStatus = .active
    ) {
        self.id = id
        self.spot = spot
        self.startTime = startTime
        self.endTime = endTime
        self.vehicleInfo = vehicleInfo
        self.status = status
    }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var remainingTime: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSinceNow
    }

    enum SessionStatus: String, Codable {
        case active
        case completed
        case expired
    }
}

struct SavedParkingLocation: Identifiable, Codable {
    let id: UUID
    let location: CLLocation
    let savedAt: Date
    var notes: String?
    var photoPath: String?
    var floor: String?
    var spot: String?

    init(
        id: UUID = UUID(),
        location: CLLocation,
        savedAt: Date = Date(),
        notes: String? = nil,
        photoPath: String? = nil,
        floor: String? = nil,
        spot: String? = nil
    ) {
        self.id = id
        self.location = location
        self.savedAt = savedAt
        self.notes = notes
        self.photoPath = photoPath
        self.floor = floor
        self.spot = spot
    }
}

struct VehicleInfo: Codable {
    var licensePlate: String
    var make: String?
    var model: String?
    var color: String?
}

enum ParkingProvider: String, Codable {
    case spotHero
    case parkWhiz
    case parkMobile
    case direct
}

enum ParkingSpotType: String, Codable {
    case garage
    case lot
    case street
    case valet
}

enum ParkingAmenity: String, Codable {
    case covered
    case evCharging
    case handicapAccessible
    case twentyFourHour
    case security
    case attended
    case restroom
    case carWash
}

enum VehicleType: String, Codable {
    case sedan
    case suv
    case truck
    case motorcycle
    case ev
    case oversized
}

struct ParkingAlert: Identifiable {
    let id: UUID = UUID()
    let session: ParkingSession
    let type: AlertType
    let message: String

    enum AlertType {
        case expiringSoon
        case expired
    }
}

// MARK: - CLLocation Codable Extension

extension CLLocation: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
}

// MARK: - Errors

enum ParkingError: Error, LocalizedError {
    case notConfigured
    case reservationFailed
    case reservationNotSupported
    case cancellationFailed
    case cancellationNotSupported
    case sessionNotFound
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Parking service not configured"
        case .reservationFailed: return "Failed to make reservation"
        case .reservationNotSupported: return "Reservations not supported"
        case .cancellationFailed: return "Failed to cancel reservation"
        case .cancellationNotSupported: return "Cancellation not supported"
        case .sessionNotFound: return "Parking session not found"
        case .parseError: return "Failed to parse response"
        }
    }
}
