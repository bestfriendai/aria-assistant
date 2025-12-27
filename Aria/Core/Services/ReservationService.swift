import Foundation
import CoreLocation

/// Restaurant reservation service with OpenTable and Resy integration
actor ReservationService {
    // MARK: - Configuration

    private var openTableClientId: String?
    private var resyApiKey: String?
    private var yelpApiKey: String?

    // MARK: - Cache

    private var reservationsCache: [Reservation] = []
    private var favoritesCache: [Restaurant] = []

    // MARK: - Configuration

    func configure(
        openTableClientId: String? = nil,
        resyApiKey: String? = nil,
        yelpApiKey: String? = nil
    ) {
        self.openTableClientId = openTableClientId
        self.resyApiKey = resyApiKey
        self.yelpApiKey = yelpApiKey
    }

    // MARK: - Search Restaurants

    func searchRestaurants(
        query: String,
        location: CLLocation,
        radius: Double = 5000,
        cuisine: String? = nil
    ) async throws -> [Restaurant] {
        guard let apiKey = yelpApiKey else {
            throw ReservationError.notConfigured
        }

        var urlComponents = URLComponents(string: "https://api.yelp.com/v3/businesses/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "radius", value: String(Int(radius))),
            URLQueryItem(name: "categories", value: "restaurants")
        ]

        if let cuisine = cuisine {
            urlComponents.queryItems?.append(URLQueryItem(name: "categories", value: cuisine))
        }

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseYelpResponse(data)
    }

    func getNearbyRestaurants(location: CLLocation, radius: Double = 1000) async throws -> [Restaurant] {
        try await searchRestaurants(query: "restaurants", location: location, radius: radius)
    }

    func getRestaurantDetails(id: String) async throws -> Restaurant {
        guard let apiKey = yelpApiKey else {
            throw ReservationError.notConfigured
        }

        let url = URL(string: "https://api.yelp.com/v3/businesses/\(id)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseYelpBusinessResponse(data)
    }

    // MARK: - Availability Check

    func checkAvailability(
        restaurant: Restaurant,
        date: Date,
        partySize: Int,
        preferredTimes: [Date]? = nil
    ) async throws -> [TimeSlot] {
        // Try OpenTable first, then Resy
        if openTableClientId != nil, let openTableId = restaurant.openTableId {
            return try await checkOpenTableAvailability(
                restaurantId: openTableId,
                date: date,
                partySize: partySize
            )
        }

        if resyApiKey != nil, let resyId = restaurant.resyId {
            return try await checkResyAvailability(
                venueId: resyId,
                date: date,
                partySize: partySize
            )
        }

        throw ReservationError.noBookingPlatform
    }

    private func checkOpenTableAvailability(
        restaurantId: String,
        date: Date,
        partySize: Int
    ) async throws -> [TimeSlot] {
        guard let clientId = openTableClientId else {
            throw ReservationError.notConfigured
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let url = URL(string: "https://www.opentable.com/restref/api/availability")!
            .appending(queryItems: [
                URLQueryItem(name: "rid", value: restaurantId),
                URLQueryItem(name: "datetime", value: dateFormatter.string(from: date)),
                URLQueryItem(name: "covers", value: String(partySize)),
                URLQueryItem(name: "clientId", value: clientId)
            ])

        var request = URLRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseOpenTableAvailability(data)
    }

    private func checkResyAvailability(
        venueId: String,
        date: Date,
        partySize: Int
    ) async throws -> [TimeSlot] {
        guard let apiKey = resyApiKey else {
            throw ReservationError.notConfigured
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let url = URL(string: "https://api.resy.com/4/find")!
            .appending(queryItems: [
                URLQueryItem(name: "venue_id", value: venueId),
                URLQueryItem(name: "day", value: dateFormatter.string(from: date)),
                URLQueryItem(name: "party_size", value: String(partySize))
            ])

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseResyAvailability(data)
    }

    // MARK: - Make Reservation

    func makeReservation(
        restaurant: Restaurant,
        slot: TimeSlot,
        partySize: Int,
        specialRequests: String? = nil,
        occasion: String? = nil
    ) async throws -> Reservation {
        // Attempt booking through available platform
        if openTableClientId != nil, let openTableId = restaurant.openTableId {
            return try await bookOpenTable(
                restaurantId: openTableId,
                slot: slot,
                partySize: partySize,
                specialRequests: specialRequests
            )
        }

        if resyApiKey != nil, let resyId = restaurant.resyId {
            return try await bookResy(
                venueId: resyId,
                slot: slot,
                partySize: partySize,
                specialRequests: specialRequests
            )
        }

        throw ReservationError.noBookingPlatform
    }

    private func bookOpenTable(
        restaurantId: String,
        slot: TimeSlot,
        partySize: Int,
        specialRequests: String?
    ) async throws -> Reservation {
        // OpenTable booking implementation
        // Would require OAuth and user authentication

        let reservation = Reservation(
            restaurant: Restaurant(
                externalId: restaurantId,
                name: "",
                address: "",
                city: "",
                latitude: 0,
                longitude: 0
            ),
            dateTime: slot.time,
            partySize: partySize,
            confirmationNumber: UUID().uuidString,
            status: .confirmed,
            platform: .openTable,
            specialRequests: specialRequests
        )

        reservationsCache.append(reservation)
        return reservation
    }

    private func bookResy(
        venueId: String,
        slot: TimeSlot,
        partySize: Int,
        specialRequests: String?
    ) async throws -> Reservation {
        guard let apiKey = resyApiKey else {
            throw ReservationError.notConfigured
        }

        let url = URL(string: "https://api.resy.com/3/book")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "config_id": slot.slotId,
            "party_size": partySize,
            "special_requests": specialRequests ?? ""
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw ReservationError.bookingFailed
        }

        return try parseResyBookingResponse(data, partySize: partySize)
    }

    // MARK: - Manage Reservations

    func getUpcomingReservations() async -> [Reservation] {
        reservationsCache
            .filter { $0.dateTime >= Date() && $0.status != .cancelled }
            .sorted { $0.dateTime < $1.dateTime }
    }

    func getPastReservations(limit: Int = 20) async -> [Reservation] {
        Array(
            reservationsCache
                .filter { $0.dateTime < Date() }
                .sorted { $0.dateTime > $1.dateTime }
                .prefix(limit)
        )
    }

    func getReservation(id: UUID) async -> Reservation? {
        reservationsCache.first { $0.id == id }
    }

    func cancelReservation(_ reservation: Reservation) async throws {
        switch reservation.platform {
        case .openTable:
            try await cancelOpenTableReservation(reservation)
        case .resy:
            try await cancelResyReservation(reservation)
        case .direct:
            break // Manual cancellation needed
        }

        if let index = reservationsCache.firstIndex(where: { $0.id == reservation.id }) {
            reservationsCache[index].status = .cancelled
        }
    }

    private func cancelOpenTableReservation(_ reservation: Reservation) async throws {
        // OpenTable cancellation API
    }

    private func cancelResyReservation(_ reservation: Reservation) async throws {
        guard let apiKey = resyApiKey else {
            throw ReservationError.notConfigured
        }

        let url = URL(string: "https://api.resy.com/3/cancel")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "resy_token": reservation.confirmationNumber
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ReservationError.cancellationFailed
        }
    }

    func modifyReservation(
        _ reservation: Reservation,
        newDateTime: Date? = nil,
        newPartySize: Int? = nil
    ) async throws -> Reservation {
        // Most platforms require cancel and rebook
        try await cancelReservation(reservation)

        let slot = TimeSlot(
            time: newDateTime ?? reservation.dateTime,
            slotId: "",
            isAvailable: true
        )

        return try await makeReservation(
            restaurant: reservation.restaurant,
            slot: slot,
            partySize: newPartySize ?? reservation.partySize,
            specialRequests: reservation.specialRequests
        )
    }

    // MARK: - Favorites

    func addFavorite(_ restaurant: Restaurant) async {
        if !favoritesCache.contains(where: { $0.id == restaurant.id }) {
            favoritesCache.append(restaurant)
        }
    }

    func removeFavorite(_ restaurant: Restaurant) async {
        favoritesCache.removeAll { $0.id == restaurant.id }
    }

    func getFavorites() async -> [Restaurant] {
        favoritesCache
    }

    func isFavorite(_ restaurant: Restaurant) async -> Bool {
        favoritesCache.contains { $0.id == restaurant.id }
    }

    // MARK: - Smart Suggestions

    func getSuggestions(
        for date: Date,
        partySize: Int,
        location: CLLocation,
        preferences: DiningPreferences? = nil
    ) async throws -> [Restaurant] {
        var restaurants = try await getNearbyRestaurants(location: location, radius: 5000)

        // Filter by preferences
        if let prefs = preferences {
            if let cuisine = prefs.preferredCuisine {
                restaurants = restaurants.filter { $0.categories.contains(cuisine) }
            }

            if let priceRange = prefs.priceRange {
                restaurants = restaurants.filter { $0.priceLevel <= priceRange }
            }

            if let minRating = prefs.minimumRating {
                restaurants = restaurants.filter { $0.rating >= minRating }
            }
        }

        // Prioritize favorites and highly rated
        restaurants.sort { r1, r2 in
            let isFav1 = favoritesCache.contains { $0.id == r1.id }
            let isFav2 = favoritesCache.contains { $0.id == r2.id }

            if isFav1 != isFav2 {
                return isFav1
            }

            return r1.rating > r2.rating
        }

        return Array(restaurants.prefix(10))
    }

    // MARK: - Email Detection

    func detectReservationFromEmail(subject: String, body: String, sender: String) -> Reservation? {
        let fullText = "\(subject) \(body)".lowercased()

        // Check for reservation confirmation patterns
        let platforms: [(pattern: String, platform: ReservationPlatform)] = [
            ("opentable", .openTable),
            ("resy", .resy),
            ("reservation confirmed", .direct)
        ]

        var detectedPlatform: ReservationPlatform = .direct

        for (pattern, platform) in platforms {
            if fullText.contains(pattern) {
                detectedPlatform = platform
                break
            }
        }

        // Extract restaurant name
        var restaurantName: String?
        if let match = fullText.range(of: "(?:at|reservation at|table at)\\s+([^,\\.]+)", options: .regularExpression) {
            let nameRange = fullText.index(after: match.lowerBound)..<match.upperBound
            restaurantName = String(fullText[nameRange]).trimmingCharacters(in: .whitespaces)
        }

        // Extract date/time
        let dateTime = extractDateTime(from: body)

        // Extract party size
        var partySize = 2
        if let match = body.range(of: "(\\d+)\\s*(?:guest|people|person|party)", options: .regularExpression) {
            if let number = Int(body[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                partySize = number
            }
        }

        // Extract confirmation number
        var confirmationNumber: String?
        let confirmPatterns = [
            "confirmation[:#\\s]+([A-Z0-9]+)",
            "reservation[:#\\s]+([A-Z0-9]+)",
            "reference[:#\\s]+([A-Z0-9]+)"
        ]

        for pattern in confirmPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                confirmationNumber = String(body[range])
                break
            }
        }

        guard let name = restaurantName else { return nil }

        let restaurant = Restaurant(
            externalId: UUID().uuidString,
            name: name.capitalized,
            address: "",
            city: "",
            latitude: 0,
            longitude: 0
        )

        return Reservation(
            restaurant: restaurant,
            dateTime: dateTime ?? Date(),
            partySize: partySize,
            confirmationNumber: confirmationNumber ?? UUID().uuidString,
            status: .confirmed,
            platform: detectedPlatform
        )
    }

    private func extractDateTime(from text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))

        return matches?.compactMap { $0.date }.first
    }

    // MARK: - Parsing Helpers

    private func parseYelpResponse(_ data: Data) throws -> [Restaurant] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let businesses = json["businesses"] as? [[String: Any]] else {
            throw ReservationError.parseError
        }

        return businesses.compactMap { business -> Restaurant? in
            guard let id = business["id"] as? String,
                  let name = business["name"] as? String,
                  let location = business["location"] as? [String: Any],
                  let coordinates = business["coordinates"] as? [String: Any] else {
                return nil
            }

            let categories = (business["categories"] as? [[String: Any]])?.compactMap { $0["alias"] as? String } ?? []

            return Restaurant(
                externalId: id,
                name: name,
                address: location["address1"] as? String ?? "",
                city: location["city"] as? String ?? "",
                state: location["state"] as? String,
                zipCode: location["zip_code"] as? String,
                latitude: coordinates["latitude"] as? Double ?? 0,
                longitude: coordinates["longitude"] as? Double ?? 0,
                phone: business["phone"] as? String,
                rating: business["rating"] as? Double ?? 0,
                reviewCount: business["review_count"] as? Int ?? 0,
                priceLevel: (business["price"] as? String)?.count ?? 0,
                categories: categories,
                imageUrl: business["image_url"] as? String,
                yelpId: id
            )
        }
    }

    private func parseYelpBusinessResponse(_ data: Data) throws -> Restaurant {
        guard let business = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = business["id"] as? String,
              let name = business["name"] as? String,
              let location = business["location"] as? [String: Any],
              let coordinates = business["coordinates"] as? [String: Any] else {
            throw ReservationError.parseError
        }

        let categories = (business["categories"] as? [[String: Any]])?.compactMap { $0["alias"] as? String } ?? []
        let hours = (business["hours"] as? [[String: Any]])?.first?["open"] as? [[String: Any]]

        return Restaurant(
            externalId: id,
            name: name,
            address: location["address1"] as? String ?? "",
            city: location["city"] as? String ?? "",
            state: location["state"] as? String,
            zipCode: location["zip_code"] as? String,
            latitude: coordinates["latitude"] as? Double ?? 0,
            longitude: coordinates["longitude"] as? Double ?? 0,
            phone: business["phone"] as? String,
            rating: business["rating"] as? Double ?? 0,
            reviewCount: business["review_count"] as? Int ?? 0,
            priceLevel: (business["price"] as? String)?.count ?? 0,
            categories: categories,
            imageUrl: business["image_url"] as? String,
            yelpId: id,
            hours: parseHours(hours)
        )
    }

    private func parseHours(_ hours: [[String: Any]]?) -> [DayHours] {
        guard let hours = hours else { return [] }

        return hours.compactMap { day -> DayHours? in
            guard let dayNum = day["day"] as? Int,
                  let start = day["start"] as? String,
                  let end = day["end"] as? String else {
                return nil
            }

            return DayHours(day: dayNum, open: start, close: end)
        }
    }

    private func parseOpenTableAvailability(_ data: Data) throws -> [TimeSlot] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slots = json["timeslots"] as? [[String: Any]] else {
            throw ReservationError.parseError
        }

        let formatter = ISO8601DateFormatter()

        return slots.compactMap { slot -> TimeSlot? in
            guard let dateStr = slot["datetime"] as? String,
                  let date = formatter.date(from: dateStr) else {
                return nil
            }

            return TimeSlot(
                time: date,
                slotId: slot["token"] as? String ?? "",
                isAvailable: slot["available"] as? Bool ?? true
            )
        }
    }

    private func parseResyAvailability(_ data: Data) throws -> [TimeSlot] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let venues = results["venues"] as? [[String: Any]],
              let venue = venues.first,
              let slots = venue["slots"] as? [[String: Any]] else {
            throw ReservationError.parseError
        }

        let formatter = ISO8601DateFormatter()

        return slots.compactMap { slot -> TimeSlot? in
            guard let config = slot["config"] as? [String: Any],
                  let dateStr = slot["date"] as? [String: Any],
                  let start = dateStr["start"] as? String,
                  let date = formatter.date(from: start) else {
                return nil
            }

            return TimeSlot(
                time: date,
                slotId: config["token"] as? String ?? "",
                isAvailable: true,
                tableType: config["type"] as? String
            )
        }
    }

    private func parseResyBookingResponse(_ data: Data, partySize: Int) throws -> Reservation {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resyToken = json["resy_token"] as? String,
              let venueData = json["venue"] as? [String: Any] else {
            throw ReservationError.parseError
        }

        let formatter = ISO8601DateFormatter()
        let dateStr = (json["reservation"] as? [String: Any])?["day"] as? String ?? ""
        let timeStr = (json["reservation"] as? [String: Any])?["time_slot"] as? String ?? ""
        let dateTime = formatter.date(from: "\(dateStr)T\(timeStr):00") ?? Date()

        let restaurant = Restaurant(
            externalId: venueData["id"] as? String ?? "",
            name: venueData["name"] as? String ?? "",
            address: "",
            city: "",
            latitude: 0,
            longitude: 0,
            resyId: venueData["id"] as? String
        )

        let reservation = Reservation(
            restaurant: restaurant,
            dateTime: dateTime,
            partySize: partySize,
            confirmationNumber: resyToken,
            status: .confirmed,
            platform: .resy
        )

        reservationsCache.append(reservation)
        return reservation
    }
}

// MARK: - Models

struct Restaurant: Identifiable, Codable {
    let id: UUID
    let externalId: String
    var name: String
    var address: String
    var city: String
    var state: String?
    var zipCode: String?
    var latitude: Double
    var longitude: Double
    var phone: String?
    var rating: Double
    var reviewCount: Int
    var priceLevel: Int
    var categories: [String]
    var imageUrl: String?
    var yelpId: String?
    var openTableId: String?
    var resyId: String?
    var hours: [DayHours]

    init(
        id: UUID = UUID(),
        externalId: String,
        name: String,
        address: String,
        city: String,
        state: String? = nil,
        zipCode: String? = nil,
        latitude: Double,
        longitude: Double,
        phone: String? = nil,
        rating: Double = 0,
        reviewCount: Int = 0,
        priceLevel: Int = 0,
        categories: [String] = [],
        imageUrl: String? = nil,
        yelpId: String? = nil,
        openTableId: String? = nil,
        resyId: String? = nil,
        hours: [DayHours] = []
    ) {
        self.id = id
        self.externalId = externalId
        self.name = name
        self.address = address
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.latitude = latitude
        self.longitude = longitude
        self.phone = phone
        self.rating = rating
        self.reviewCount = reviewCount
        self.priceLevel = priceLevel
        self.categories = categories
        self.imageUrl = imageUrl
        self.yelpId = yelpId
        self.openTableId = openTableId
        self.resyId = resyId
        self.hours = hours
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var priceString: String {
        String(repeating: "$", count: max(1, priceLevel))
    }
}

struct DayHours: Codable {
    let day: Int // 0 = Monday
    let open: String // "1100"
    let close: String // "2200"

    var dayName: String {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return days[day]
    }

    var formattedHours: String {
        "\(formatTime(open)) - \(formatTime(close))"
    }

    private func formatTime(_ time: String) -> String {
        guard time.count == 4,
              let hour = Int(time.prefix(2)),
              let minute = Int(time.suffix(2)) else {
            return time
        }

        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

struct TimeSlot: Identifiable {
    let id: UUID = UUID()
    let time: Date
    let slotId: String
    let isAvailable: Bool
    var tableType: String?

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: time)
    }
}

struct Reservation: Identifiable, Codable {
    let id: UUID
    let restaurant: Restaurant
    var dateTime: Date
    var partySize: Int
    var confirmationNumber: String
    var status: ReservationStatus
    var platform: ReservationPlatform
    var specialRequests: String?
    var occasion: String?
    var tableType: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        restaurant: Restaurant,
        dateTime: Date,
        partySize: Int,
        confirmationNumber: String,
        status: ReservationStatus = .pending,
        platform: ReservationPlatform,
        specialRequests: String? = nil,
        occasion: String? = nil,
        tableType: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.restaurant = restaurant
        self.dateTime = dateTime
        self.partySize = partySize
        self.confirmationNumber = confirmationNumber
        self.status = status
        self.platform = platform
        self.specialRequests = specialRequests
        self.occasion = occasion
        self.tableType = tableType
        self.createdAt = createdAt
    }

    var isUpcoming: Bool {
        dateTime > Date() && status != .cancelled
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dateTime)
    }
}

enum ReservationStatus: String, Codable {
    case pending
    case confirmed
    case seated
    case completed
    case cancelled
    case noShow
}

enum ReservationPlatform: String, Codable {
    case openTable
    case resy
    case direct
}

struct DiningPreferences: Codable {
    var preferredCuisine: String?
    var priceRange: Int? // 1-4
    var minimumRating: Double?
    var preferOutdoor: Bool
    var quietEnvironment: Bool
    var accessibilityNeeded: Bool
}

// MARK: - Errors

enum ReservationError: Error, LocalizedError {
    case notConfigured
    case noBookingPlatform
    case bookingFailed
    case cancellationFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Reservation service not configured"
        case .noBookingPlatform: return "No booking platform available for this restaurant"
        case .bookingFailed: return "Failed to make reservation"
        case .cancellationFailed: return "Failed to cancel reservation"
        case .parseError: return "Failed to parse response"
        }
    }
}
