import Foundation

/// Travel service for flights, trips, and bookings
actor TravelService {
    // MARK: - Configuration

    private var flightAwareApiKey: String?
    private var tripItToken: String?

    private let flightAwareBaseURL = URL(string: "https://aeroapi.flightaware.com/aeroapi")!

    // MARK: - Cache

    private var flightsCache: [Flight] = []
    private var tripsCache: [Trip] = []
    private var lastRefresh: Date?

    // MARK: - Configuration

    func configure(flightAwareApiKey: String? = nil, tripItToken: String? = nil) {
        self.flightAwareApiKey = flightAwareApiKey
        self.tripItToken = tripItToken
    }

    // MARK: - Flight Tracking

    func addFlight(
        flightNumber: String,
        date: Date,
        confirmationCode: String? = nil,
        seatNumber: String? = nil
    ) async throws -> Flight {
        // Parse airline code and flight number
        let (airline, number) = parseFlightNumber(flightNumber)

        // Fetch flight info
        let flight = try await fetchFlightInfo(
            airlineCode: airline,
            flightNumber: number,
            date: date
        )

        var updatedFlight = flight
        updatedFlight.confirmationCode = confirmationCode
        updatedFlight.seatNumber = seatNumber

        flightsCache.append(updatedFlight)
        return updatedFlight
    }

    func getFlights(upcoming: Bool = true) async -> [Flight] {
        if upcoming {
            return flightsCache.filter { $0.isUpcoming }
                .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        }
        return flightsCache.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    func getNextFlight() async -> Flight? {
        await getFlights(upcoming: true).first
    }

    func refreshFlight(_ flight: Flight) async throws -> Flight {
        guard let apiKey = flightAwareApiKey else {
            throw TravelServiceError.notConfigured
        }

        let (airline, number) = parseFlightNumber(flight.displayFlightNumber)
        return try await fetchFlightInfo(airlineCode: airline, flightNumber: number, date: flight.scheduledDeparture)
    }

    func refreshAllFlights() async throws {
        for (index, flight) in flightsCache.enumerated() where flight.isUpcoming {
            if let updated = try? await refreshFlight(flight) {
                flightsCache[index] = updated
            }
        }
        lastRefresh = Date()
    }

    // MARK: - FlightAware Integration

    private func fetchFlightInfo(airlineCode: String, flightNumber: String, date: Date) async throws -> Flight {
        guard let apiKey = flightAwareApiKey else {
            throw TravelServiceError.notConfigured
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let url = flightAwareBaseURL
            .appendingPathComponent("/flights/\(airlineCode)\(flightNumber)")
            .appending(queryItems: [URLQueryItem(name: "start", value: dateString)])

        var request = URLRequest(url: url)
        request.setValue("x-apikey", forHTTPHeaderField: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TravelServiceError.flightNotFound
        }

        return try parseFlightAwareResponse(data)
    }

    private func parseFlightAwareResponse(_ data: Data) throws -> Flight {
        // Parse FlightAware response
        // This is a simplified implementation
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flights = json["flights"] as? [[String: Any]],
              let flightData = flights.first else {
            throw TravelServiceError.parseError
        }

        let airline = Airline(
            name: flightData["operator"] as? String ?? "",
            iataCode: flightData["operator_iata"] as? String ?? "",
            icaoCode: flightData["operator_icao"] as? String,
            logoUrl: nil
        )

        let origin = Airport(
            code: (flightData["origin"] as? [String: Any])?["code_iata"] as? String ?? "",
            name: (flightData["origin"] as? [String: Any])?["name"] as? String ?? "",
            city: (flightData["origin"] as? [String: Any])?["city"] as? String ?? "",
            country: (flightData["origin"] as? [String: Any])?["country"] as? String ?? "",
            timezone: nil,
            latitude: nil,
            longitude: nil
        )

        let destination = Airport(
            code: (flightData["destination"] as? [String: Any])?["code_iata"] as? String ?? "",
            name: (flightData["destination"] as? [String: Any])?["name"] as? String ?? "",
            city: (flightData["destination"] as? [String: Any])?["city"] as? String ?? "",
            country: (flightData["destination"] as? [String: Any])?["country"] as? String ?? "",
            timezone: nil,
            latitude: nil,
            longitude: nil
        )

        let formatter = ISO8601DateFormatter()
        let scheduledDeparture = formatter.date(from: flightData["scheduled_off"] as? String ?? "") ?? Date()
        let scheduledArrival = formatter.date(from: flightData["scheduled_on"] as? String ?? "") ?? Date()

        return Flight(
            flightNumber: flightData["flight_number"] as? String ?? "",
            airline: airline,
            departureAirport: origin,
            arrivalAirport: destination,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            status: parseFlightStatus(flightData["status"] as? String),
            gate: (flightData["gate_origin"] as? String),
            terminal: (flightData["terminal_origin"] as? String)
        )
    }

    private func parseFlightStatus(_ status: String?) -> FlightStatus {
        guard let status = status?.lowercased() else { return .scheduled }

        switch status {
        case "scheduled": return .scheduled
        case "active", "en route": return .enRoute
        case "landed": return .landed
        case "arrived": return .arrived
        case "cancelled": return .cancelled
        case "diverted": return .diverted
        default: return .scheduled
        }
    }

    private func parseFlightNumber(_ flightNumber: String) -> (String, String) {
        let cleaned = flightNumber.uppercased().replacingOccurrences(of: " ", with: "")

        // Extract airline code (2-3 letters) and flight number
        var airlineCode = ""
        var number = ""

        for (index, char) in cleaned.enumerated() {
            if char.isLetter && index < 3 {
                airlineCode.append(char)
            } else {
                number = String(cleaned.dropFirst(index))
                break
            }
        }

        return (airlineCode, number)
    }

    // MARK: - Trips

    func getTrips(upcoming: Bool = true) async -> [Trip] {
        if upcoming {
            return tripsCache.filter { $0.isUpcoming || $0.isActive }
                .sorted { $0.startDate < $1.startDate }
        }
        return tripsCache.sorted { $0.startDate > $1.startDate }
    }

    func getCurrentTrip() async -> Trip? {
        tripsCache.first { $0.isActive }
    }

    func getNextTrip() async -> Trip? {
        tripsCache.filter { $0.isUpcoming }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    func createTrip(name: String, destination: String, startDate: Date, endDate: Date) async -> Trip {
        let trip = Trip(
            name: name,
            destination: destination,
            startDate: startDate,
            endDate: endDate
        )
        tripsCache.append(trip)
        return trip
    }

    func addFlightToTrip(_ flight: Flight, tripId: UUID) async throws {
        guard let index = tripsCache.firstIndex(where: { $0.id == tripId }) else {
            throw TravelServiceError.tripNotFound
        }
        tripsCache[index].flights.append(flight)
    }

    func addHotelToTrip(_ hotel: HotelReservation, tripId: UUID) async throws {
        guard let index = tripsCache.firstIndex(where: { $0.id == tripId }) else {
            throw TravelServiceError.tripNotFound
        }
        tripsCache[index].hotels.append(hotel)
    }

    // MARK: - Email Parsing

    func extractFlightFromEmail(_ emailBody: String, subject: String) -> Flight? {
        // Look for common flight confirmation patterns
        // This is a simplified implementation

        // Pattern: "Flight: AA123" or "Flight AA 123"
        let flightPattern = try? NSRegularExpression(
            pattern: "(?:flight[:\\s]+)?([A-Z]{2,3})\\s*([0-9]{1,4})",
            options: .caseInsensitive
        )

        guard let match = flightPattern?.firstMatch(
            in: emailBody,
            range: NSRange(emailBody.startIndex..., in: emailBody)
        ) else {
            return nil
        }

        // Extract flight details
        // Would need more sophisticated parsing for real implementation

        return nil
    }

    func extractHotelFromEmail(_ emailBody: String) -> HotelReservation? {
        // Parse hotel confirmation emails
        return nil
    }

    // MARK: - Alerts

    func getFlightAlerts() async -> [Flight] {
        flightsCache.filter { flight in
            guard flight.isUpcoming else { return false }

            // Alert if delayed
            if flight.isDelayed { return true }

            // Alert if departing soon (within 3 hours)
            if let minutes = flight.minutesUntilDeparture, minutes <= 180 {
                return true
            }

            // Alert if gate changed or status changed
            return false
        }
    }
}

// MARK: - Errors

enum TravelServiceError: Error, LocalizedError {
    case notConfigured
    case flightNotFound
    case tripNotFound
    case parseError
    case networkError

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Travel service not configured"
        case .flightNotFound: return "Flight not found"
        case .tripNotFound: return "Trip not found"
        case .parseError: return "Failed to parse response"
        case .networkError: return "Network error"
        }
    }
}
