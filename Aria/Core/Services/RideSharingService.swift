import Foundation
import CoreLocation

/// Ride sharing service supporting Uber and Lyft
actor RideSharingService {
    // MARK: - Configuration

    private var uberClientId: String?
    private var uberClientSecret: String?
    private var lyftClientId: String?
    private var lyftClientSecret: String?

    private var uberAccessToken: String?
    private var lyftAccessToken: String?

    // MARK: - Cache

    private var ridesCache: [Ride] = []
    private var estimatesCache: [RideEstimate] = []
    private var lastEstimateLocation: CLLocation?

    // MARK: - Configuration

    func configure(
        uberClientId: String? = nil,
        uberClientSecret: String? = nil,
        lyftClientId: String? = nil,
        lyftClientSecret: String? = nil
    ) {
        self.uberClientId = uberClientId
        self.uberClientSecret = uberClientSecret
        self.lyftClientId = lyftClientId
        self.lyftClientSecret = lyftClientSecret
    }

    func setAccessTokens(uber: String? = nil, lyft: String? = nil) {
        self.uberAccessToken = uber
        self.lyftAccessToken = lyft
    }

    // MARK: - Estimates

    func getEstimates(
        from origin: CLLocation,
        to destination: CLLocation,
        providers: [RideProvider] = [.uber, .lyft]
    ) async throws -> [RideEstimate] {
        var estimates: [RideEstimate] = []

        for provider in providers {
            switch provider {
            case .uber:
                if uberAccessToken != nil {
                    let uberEstimates = try await getUberEstimates(from: origin, to: destination)
                    estimates.append(contentsOf: uberEstimates)
                }
            case .lyft:
                if lyftAccessToken != nil {
                    let lyftEstimates = try await getLyftEstimates(from: origin, to: destination)
                    estimates.append(contentsOf: lyftEstimates)
                }
            }
        }

        estimatesCache = estimates
        lastEstimateLocation = origin
        return estimates.sorted { $0.estimatedPrice < $1.estimatedPrice }
    }

    func getCheapestRide(from origin: CLLocation, to destination: CLLocation) async throws -> RideEstimate? {
        let estimates = try await getEstimates(from: origin, to: destination)
        return estimates.min { $0.estimatedPrice < $1.estimatedPrice }
    }

    func getFastestRide(from origin: CLLocation, to destination: CLLocation) async throws -> RideEstimate? {
        let estimates = try await getEstimates(from: origin, to: destination)
        return estimates.min { $0.estimatedPickupMinutes < $1.estimatedPickupMinutes }
    }

    // MARK: - Uber Integration

    private func getUberEstimates(from origin: CLLocation, to destination: CLLocation) async throws -> [RideEstimate] {
        guard let token = uberAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.uber.com/v1.2/estimates/price")!
            .appending(queryItems: [
                URLQueryItem(name: "start_latitude", value: String(origin.coordinate.latitude)),
                URLQueryItem(name: "start_longitude", value: String(origin.coordinate.longitude)),
                URLQueryItem(name: "end_latitude", value: String(destination.coordinate.latitude)),
                URLQueryItem(name: "end_longitude", value: String(destination.coordinate.longitude))
            ])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RideSharingError.requestFailed
        }

        return try parseUberEstimates(data, origin: origin, destination: destination)
    }

    private func parseUberEstimates(_ data: Data, origin: CLLocation, destination: CLLocation) throws -> [RideEstimate] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prices = json["prices"] as? [[String: Any]] else {
            throw RideSharingError.parseError
        }

        return prices.compactMap { price -> RideEstimate? in
            guard let displayName = price["display_name"] as? String,
                  let lowEstimate = price["low_estimate"] as? Double,
                  let highEstimate = price["high_estimate"] as? Double,
                  let duration = price["duration"] as? Int else {
                return nil
            }

            let rideType = mapUberRideType(displayName)

            return RideEstimate(
                provider: .uber,
                rideType: rideType,
                displayName: displayName,
                estimatedPrice: (lowEstimate + highEstimate) / 2,
                lowPrice: lowEstimate,
                highPrice: highEstimate,
                estimatedDurationMinutes: duration / 60,
                estimatedPickupMinutes: price["pickup_estimate"] as? Int ?? 5,
                surgeMultiplier: price["surge_multiplier"] as? Double ?? 1.0,
                origin: origin,
                destination: destination
            )
        }
    }

    private func mapUberRideType(_ name: String) -> RideType {
        let lower = name.lowercased()
        if lower.contains("black") || lower.contains("lux") {
            return .luxury
        } else if lower.contains("xl") || lower.contains("suv") {
            return .xl
        } else if lower.contains("pool") || lower.contains("share") {
            return .shared
        } else if lower.contains("comfort") {
            return .comfort
        }
        return .standard
    }

    // MARK: - Lyft Integration

    private func getLyftEstimates(from origin: CLLocation, to destination: CLLocation) async throws -> [RideEstimate] {
        guard let token = lyftAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.lyft.com/v1/cost")!
            .appending(queryItems: [
                URLQueryItem(name: "start_lat", value: String(origin.coordinate.latitude)),
                URLQueryItem(name: "start_lng", value: String(origin.coordinate.longitude)),
                URLQueryItem(name: "end_lat", value: String(destination.coordinate.latitude)),
                URLQueryItem(name: "end_lng", value: String(destination.coordinate.longitude))
            ])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RideSharingError.requestFailed
        }

        return try parseLyftEstimates(data, origin: origin, destination: destination)
    }

    private func parseLyftEstimates(_ data: Data, origin: CLLocation, destination: CLLocation) throws -> [RideEstimate] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let costs = json["cost_estimates"] as? [[String: Any]] else {
            throw RideSharingError.parseError
        }

        return costs.compactMap { cost -> RideEstimate? in
            guard let displayName = cost["display_name"] as? String,
                  let minCost = cost["estimated_cost_cents_min"] as? Int,
                  let maxCost = cost["estimated_cost_cents_max"] as? Int,
                  let duration = cost["estimated_duration_seconds"] as? Int else {
                return nil
            }

            let rideType = mapLyftRideType(displayName)

            return RideEstimate(
                provider: .lyft,
                rideType: rideType,
                displayName: displayName,
                estimatedPrice: Double(minCost + maxCost) / 200.0, // Convert cents to dollars
                lowPrice: Double(minCost) / 100.0,
                highPrice: Double(maxCost) / 100.0,
                estimatedDurationMinutes: duration / 60,
                estimatedPickupMinutes: (cost["primetime_percentage"] as? Int) ?? 5,
                surgeMultiplier: 1.0 + (Double(cost["primetime_percentage"] as? Int ?? 0) / 100.0),
                origin: origin,
                destination: destination
            )
        }
    }

    private func mapLyftRideType(_ name: String) -> RideType {
        let lower = name.lowercased()
        if lower.contains("lux") || lower.contains("black") {
            return .luxury
        } else if lower.contains("xl") {
            return .xl
        } else if lower.contains("shared") || lower.contains("wait") {
            return .shared
        }
        return .standard
    }

    // MARK: - Ride Requests

    func requestRide(estimate: RideEstimate) async throws -> Ride {
        switch estimate.provider {
        case .uber:
            return try await requestUberRide(estimate)
        case .lyft:
            return try await requestLyftRide(estimate)
        }
    }

    private func requestUberRide(_ estimate: RideEstimate) async throws -> Ride {
        guard let token = uberAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.uber.com/v1.2/requests")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "start_latitude": estimate.origin.coordinate.latitude,
            "start_longitude": estimate.origin.coordinate.longitude,
            "end_latitude": estimate.destination.coordinate.latitude,
            "end_longitude": estimate.destination.coordinate.longitude,
            "product_id": estimate.productId ?? ""
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            throw RideSharingError.requestFailed
        }

        let ride = try parseUberRideResponse(data, estimate: estimate)
        ridesCache.append(ride)
        return ride
    }

    private func parseUberRideResponse(_ data: Data, estimate: RideEstimate) throws -> Ride {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestId = json["request_id"] as? String else {
            throw RideSharingError.parseError
        }

        return Ride(
            requestId: requestId,
            provider: .uber,
            rideType: estimate.rideType,
            status: .pending,
            origin: estimate.origin,
            destination: estimate.destination,
            estimatedPrice: estimate.estimatedPrice,
            estimatedDuration: estimate.estimatedDurationMinutes,
            estimatedPickup: estimate.estimatedPickupMinutes,
            requestedAt: Date()
        )
    }

    private func requestLyftRide(_ estimate: RideEstimate) async throws -> Ride {
        guard let token = lyftAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.lyft.com/v1/rides")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "origin": [
                "lat": estimate.origin.coordinate.latitude,
                "lng": estimate.origin.coordinate.longitude
            ],
            "destination": [
                "lat": estimate.destination.coordinate.latitude,
                "lng": estimate.destination.coordinate.longitude
            ],
            "ride_type": estimate.productId ?? "lyft"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw RideSharingError.requestFailed
        }

        let ride = try parseLyftRideResponse(data, estimate: estimate)
        ridesCache.append(ride)
        return ride
    }

    private func parseLyftRideResponse(_ data: Data, estimate: RideEstimate) throws -> Ride {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rideId = json["ride_id"] as? String else {
            throw RideSharingError.parseError
        }

        return Ride(
            requestId: rideId,
            provider: .lyft,
            rideType: estimate.rideType,
            status: .pending,
            origin: estimate.origin,
            destination: estimate.destination,
            estimatedPrice: estimate.estimatedPrice,
            estimatedDuration: estimate.estimatedDurationMinutes,
            estimatedPickup: estimate.estimatedPickupMinutes,
            requestedAt: Date()
        )
    }

    // MARK: - Ride Status

    func getRideStatus(_ ride: Ride) async throws -> Ride {
        switch ride.provider {
        case .uber:
            return try await getUberRideStatus(ride)
        case .lyft:
            return try await getLyftRideStatus(ride)
        }
    }

    private func getUberRideStatus(_ ride: Ride) async throws -> Ride {
        guard let token = uberAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.uber.com/v1.2/requests/\(ride.requestId)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RideSharingError.requestFailed
        }

        return try parseUberRideStatus(data, ride: ride)
    }

    private func parseUberRideStatus(_ data: Data, ride: Ride) throws -> Ride {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RideSharingError.parseError
        }

        var updated = ride
        updated.status = parseRideStatus(json["status"] as? String)

        if let driver = json["driver"] as? [String: Any] {
            updated.driver = Driver(
                name: driver["name"] as? String ?? "",
                rating: driver["rating"] as? Double,
                phoneNumber: driver["phone_number"] as? String,
                photoUrl: driver["picture_url"] as? String
            )
        }

        if let vehicle = json["vehicle"] as? [String: Any] {
            updated.vehicle = Vehicle(
                make: vehicle["make"] as? String ?? "",
                model: vehicle["model"] as? String ?? "",
                color: vehicle["color"] as? String,
                licensePlate: vehicle["license_plate"] as? String ?? ""
            )
        }

        if let eta = json["eta"] as? Int {
            updated.estimatedPickup = eta
        }

        if let location = json["location"] as? [String: Any],
           let lat = location["latitude"] as? Double,
           let lng = location["longitude"] as? Double {
            updated.driverLocation = CLLocation(latitude: lat, longitude: lng)
        }

        return updated
    }

    private func getLyftRideStatus(_ ride: Ride) async throws -> Ride {
        guard let token = lyftAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.lyft.com/v1/rides/\(ride.requestId)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RideSharingError.requestFailed
        }

        return try parseLyftRideStatus(data, ride: ride)
    }

    private func parseLyftRideStatus(_ data: Data, ride: Ride) throws -> Ride {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RideSharingError.parseError
        }

        var updated = ride
        updated.status = parseRideStatus(json["status"] as? String)

        if let driver = json["driver"] as? [String: Any] {
            updated.driver = Driver(
                name: "\(driver["first_name"] as? String ?? "")",
                rating: driver["rating"] as? Double,
                phoneNumber: driver["phone_number"] as? String,
                photoUrl: driver["image_url"] as? String
            )
        }

        if let vehicle = json["vehicle"] as? [String: Any] {
            updated.vehicle = Vehicle(
                make: vehicle["make"] as? String ?? "",
                model: vehicle["model"] as? String ?? "",
                color: vehicle["color"] as? String,
                licensePlate: vehicle["license_plate"] as? String ?? ""
            )
        }

        if let origin = json["origin"] as? [String: Any],
           let eta = origin["eta_seconds"] as? Int {
            updated.estimatedPickup = eta / 60
        }

        if let location = json["location"] as? [String: Any],
           let lat = location["lat"] as? Double,
           let lng = location["lng"] as? Double {
            updated.driverLocation = CLLocation(latitude: lat, longitude: lng)
        }

        return updated
    }

    private func parseRideStatus(_ status: String?) -> RideStatus {
        guard let status = status?.lowercased() else { return .unknown }

        switch status {
        case "processing", "pending":
            return .pending
        case "accepted", "matched":
            return .accepted
        case "arriving", "arrived":
            return .arriving
        case "in_progress", "picked_up":
            return .inProgress
        case "completed", "dropped_off":
            return .completed
        case "canceled", "cancelled":
            return .cancelled
        case "driver_canceled":
            return .driverCancelled
        case "no_drivers_available":
            return .noDriversAvailable
        default:
            return .unknown
        }
    }

    // MARK: - Cancel Ride

    func cancelRide(_ ride: Ride) async throws {
        switch ride.provider {
        case .uber:
            try await cancelUberRide(ride)
        case .lyft:
            try await cancelLyftRide(ride)
        }

        if let index = ridesCache.firstIndex(where: { $0.id == ride.id }) {
            ridesCache[index].status = .cancelled
        }
    }

    private func cancelUberRide(_ ride: Ride) async throws {
        guard let token = uberAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.uber.com/v1.2/requests/\(ride.requestId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw RideSharingError.cancelFailed
        }
    }

    private func cancelLyftRide(_ ride: Ride) async throws {
        guard let token = lyftAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.lyft.com/v1/rides/\(ride.requestId)/cancel")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw RideSharingError.cancelFailed
        }
    }

    // MARK: - Ride History

    func getRideHistory(limit: Int = 10) async throws -> [Ride] {
        var allRides: [Ride] = []

        if uberAccessToken != nil {
            let uberRides = try await getUberHistory(limit: limit)
            allRides.append(contentsOf: uberRides)
        }

        if lyftAccessToken != nil {
            let lyftRides = try await getLyftHistory(limit: limit)
            allRides.append(contentsOf: lyftRides)
        }

        return allRides.sorted { ($0.completedAt ?? $0.requestedAt) > ($1.completedAt ?? $1.requestedAt) }
    }

    private func getUberHistory(limit: Int) async throws -> [Ride] {
        guard let token = uberAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.uber.com/v1.2/history")!
            .appending(queryItems: [URLQueryItem(name: "limit", value: String(limit))])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RideSharingError.requestFailed
        }

        return try parseUberHistory(data)
    }

    private func parseUberHistory(_ data: Data) throws -> [Ride] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let history = json["history"] as? [[String: Any]] else {
            throw RideSharingError.parseError
        }

        return history.compactMap { trip -> Ride? in
            guard let requestId = trip["request_id"] as? String,
                  let startTime = trip["start_time"] as? TimeInterval else {
                return nil
            }

            let startCity = trip["start_city"] as? [String: Any]
            let origin = CLLocation(
                latitude: startCity?["latitude"] as? Double ?? 0,
                longitude: startCity?["longitude"] as? Double ?? 0
            )

            return Ride(
                requestId: requestId,
                provider: .uber,
                rideType: .standard,
                status: .completed,
                origin: origin,
                destination: origin, // Uber history doesn't always include destination
                estimatedPrice: 0,
                estimatedDuration: 0,
                estimatedPickup: 0,
                requestedAt: Date(timeIntervalSince1970: startTime),
                completedAt: trip["end_time"] != nil ? Date(timeIntervalSince1970: trip["end_time"] as! TimeInterval) : nil
            )
        }
    }

    private func getLyftHistory(limit: Int) async throws -> [Ride] {
        guard let token = lyftAccessToken else {
            throw RideSharingError.notAuthenticated
        }

        let url = URL(string: "https://api.lyft.com/v1/rides")!
            .appending(queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start_time", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 24 * 3600)))
            ])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RideSharingError.requestFailed
        }

        return try parseLyftHistory(data)
    }

    private func parseLyftHistory(_ data: Data) throws -> [Ride] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rides = json["ride_history"] as? [[String: Any]] else {
            throw RideSharingError.parseError
        }

        return rides.compactMap { trip -> Ride? in
            guard let rideId = trip["ride_id"] as? String else {
                return nil
            }

            let origin: CLLocation
            if let originData = trip["origin"] as? [String: Any],
               let lat = originData["lat"] as? Double,
               let lng = originData["lng"] as? Double {
                origin = CLLocation(latitude: lat, longitude: lng)
            } else {
                origin = CLLocation(latitude: 0, longitude: 0)
            }

            let destination: CLLocation
            if let destData = trip["destination"] as? [String: Any],
               let lat = destData["lat"] as? Double,
               let lng = destData["lng"] as? Double {
                destination = CLLocation(latitude: lat, longitude: lng)
            } else {
                destination = origin
            }

            return Ride(
                requestId: rideId,
                provider: .lyft,
                rideType: mapLyftRideType(trip["ride_type"] as? String ?? ""),
                status: parseRideStatus(trip["status"] as? String),
                origin: origin,
                destination: destination,
                estimatedPrice: 0,
                estimatedDuration: 0,
                estimatedPickup: 0,
                requestedAt: ISO8601DateFormatter().date(from: trip["requested_at"] as? String ?? "") ?? Date()
            )
        }
    }

    // MARK: - Active Rides

    func getActiveRides() async -> [Ride] {
        ridesCache.filter { $0.isActive }
    }

    func getCurrentRide() async -> Ride? {
        ridesCache.first { $0.isActive }
    }

    // MARK: - Deep Links

    func getUberDeepLink(to destination: CLLocation, from origin: CLLocation? = nil) -> URL? {
        var components = URLComponents(string: "uber://")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "setPickup"),
            URLQueryItem(name: "dropoff[latitude]", value: String(destination.coordinate.latitude)),
            URLQueryItem(name: "dropoff[longitude]", value: String(destination.coordinate.longitude))
        ]

        if let origin = origin {
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "pickup[latitude]", value: String(origin.coordinate.latitude)),
                URLQueryItem(name: "pickup[longitude]", value: String(origin.coordinate.longitude))
            ])
        } else {
            components.queryItems?.append(URLQueryItem(name: "pickup", value: "my_location"))
        }

        return components.url
    }

    func getLyftDeepLink(to destination: CLLocation, from origin: CLLocation? = nil) -> URL? {
        var components = URLComponents(string: "lyft://ridetype")!
        components.queryItems = [
            URLQueryItem(name: "id", value: "lyft"),
            URLQueryItem(name: "destination[latitude]", value: String(destination.coordinate.latitude)),
            URLQueryItem(name: "destination[longitude]", value: String(destination.coordinate.longitude))
        ]

        if let origin = origin {
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "pickup[latitude]", value: String(origin.coordinate.latitude)),
                URLQueryItem(name: "pickup[longitude]", value: String(origin.coordinate.longitude))
            ])
        }

        return components.url
    }
}

// MARK: - Errors

enum RideSharingError: Error, LocalizedError {
    case notAuthenticated
    case requestFailed
    case parseError
    case cancelFailed
    case noRidesAvailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with ride service"
        case .requestFailed: return "Ride request failed"
        case .parseError: return "Failed to parse response"
        case .cancelFailed: return "Failed to cancel ride"
        case .noRidesAvailable: return "No rides available"
        }
    }
}
