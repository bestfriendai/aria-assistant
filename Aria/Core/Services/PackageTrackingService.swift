import Foundation

/// Package tracking service supporting multiple carriers
actor PackageTrackingService {
    // MARK: - Configuration

    private var afterShipApiKey: String?
    private let baseURL = URL(string: "https://api.aftership.com/v4")!

    // MARK: - Cache

    private var packagesCache: [Package] = []
    private var lastRefresh: Date?
    private let cacheExpiry: TimeInterval = 300 // 5 minutes

    // MARK: - Configuration

    func configure(afterShipApiKey: String) {
        self.afterShipApiKey = afterShipApiKey
    }

    // MARK: - Package Management

    func addPackage(trackingNumber: String, carrier: Carrier? = nil, description: String? = nil) async throws -> Package {
        // Detect carrier if not provided
        let detectedCarrier = carrier ?? detectCarrier(trackingNumber)

        var package = Package(
            trackingNumber: trackingNumber,
            carrier: detectedCarrier,
            description: description,
            status: .pending
        )

        // If API configured, register with AfterShip
        if afterShipApiKey != nil {
            package = try await registerWithAfterShip(package)
        }

        packagesCache.append(package)
        return package
    }

    func removePackage(id: UUID) async {
        packagesCache.removeAll { $0.id == id }
    }

    func getPackages(activeOnly: Bool = false) async -> [Package] {
        // Refresh if needed
        if shouldRefresh() {
            try? await refreshAllPackages()
        }

        if activeOnly {
            return packagesCache.filter { $0.isActive }
        }
        return packagesCache
    }

    func getPackage(id: UUID) async -> Package? {
        packagesCache.first { $0.id == id }
    }

    func getPackage(trackingNumber: String) async -> Package? {
        packagesCache.first { $0.trackingNumber == trackingNumber }
    }

    // MARK: - Tracking

    func trackPackage(_ package: Package) async throws -> Package {
        if let apiKey = afterShipApiKey {
            return try await trackWithAfterShip(package, apiKey: apiKey)
        } else {
            return try await trackDirectWithCarrier(package)
        }
    }

    func refreshAllPackages() async throws {
        var updatedPackages: [Package] = []

        for package in packagesCache where package.isActive {
            do {
                let updated = try await trackPackage(package)
                updatedPackages.append(updated)
            } catch {
                updatedPackages.append(package)
            }
        }

        // Keep inactive packages
        let inactive = packagesCache.filter { !$0.isActive }
        packagesCache = updatedPackages + inactive
        lastRefresh = Date()
    }

    // MARK: - AfterShip Integration

    private func registerWithAfterShip(_ package: Package) async throws -> Package {
        guard let apiKey = afterShipApiKey else {
            throw PackageTrackingError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("/trackings"))
        request.httpMethod = "POST"
        request.setValue("aftership-api-key", forHTTPHeaderField: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "tracking": [
                "tracking_number": package.trackingNumber,
                "slug": carrierSlug(package.carrier),
                "title": package.description ?? ""
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw PackageTrackingError.registrationFailed
        }

        // Parse response and update package
        return try parseAfterShipResponse(data, package: package)
    }

    private func trackWithAfterShip(_ package: Package, apiKey: String) async throws -> Package {
        let slug = carrierSlug(package.carrier)
        let url = baseURL.appendingPathComponent("/trackings/\(slug)/\(package.trackingNumber)")

        var request = URLRequest(url: url)
        request.setValue("aftership-api-key", forHTTPHeaderField: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PackageTrackingError.trackingFailed
        }

        return try parseAfterShipResponse(data, package: package)
    }

    private func parseAfterShipResponse(_ data: Data, package: Package) throws -> Package {
        // Parse AfterShip response
        // This is a simplified implementation
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trackingData = json["data"] as? [String: Any],
              let tracking = trackingData["tracking"] as? [String: Any] else {
            throw PackageTrackingError.parseError
        }

        var updated = package
        updated.status = parseStatus(tracking["tag"] as? String)
        updated.statusDescription = tracking["subtag_message"] as? String

        if let deliveryDate = tracking["expected_delivery"] as? String {
            let formatter = ISO8601DateFormatter()
            updated.estimatedDelivery = formatter.date(from: deliveryDate)
        }

        if let checkpoints = tracking["checkpoints"] as? [[String: Any]] {
            updated.events = checkpoints.compactMap { checkpoint -> TrackingEvent? in
                guard let message = checkpoint["message"] as? String,
                      let dateStr = checkpoint["checkpoint_time"] as? String,
                      let date = ISO8601DateFormatter().date(from: dateStr) else {
                    return nil
                }

                return TrackingEvent(
                    timestamp: date,
                    status: parseStatus(checkpoint["tag"] as? String),
                    description: message,
                    location: checkpoint["location"] as? String
                )
            }
        }

        return updated
    }

    // MARK: - Direct Carrier Tracking

    private func trackDirectWithCarrier(_ package: Package) async throws -> Package {
        switch package.carrier {
        case .ups:
            return try await trackWithUPS(package)
        case .fedex:
            return try await trackWithFedEx(package)
        case .usps:
            return try await trackWithUSPS(package)
        default:
            throw PackageTrackingError.carrierNotSupported
        }
    }

    private func trackWithUPS(_ package: Package) async throws -> Package {
        // UPS tracking implementation
        // Would use UPS Tracking API
        return package
    }

    private func trackWithFedEx(_ package: Package) async throws -> Package {
        // FedEx tracking implementation
        // Would use FedEx Track API
        return package
    }

    private func trackWithUSPS(_ package: Package) async throws -> Package {
        // USPS tracking implementation
        // Would use USPS Web Tools API
        return package
    }

    // MARK: - Carrier Detection

    func detectCarrier(_ trackingNumber: String) -> Carrier {
        let number = trackingNumber.uppercased().replacingOccurrences(of: " ", with: "")

        // UPS: 1Z followed by 16 alphanumeric
        if number.hasPrefix("1Z") && number.count == 18 {
            return .ups
        }

        // FedEx: 12, 15, 20, or 22 digits
        if number.allSatisfy({ $0.isNumber }) {
            switch number.count {
            case 12, 15, 20, 22:
                return .fedex
            case 20...22 where number.hasPrefix("96"):
                return .fedex
            default:
                break
            }
        }

        // USPS: 20-22 digits or starts with specific prefixes
        if number.count >= 20 && number.count <= 22 && number.allSatisfy({ $0.isNumber }) {
            return .usps
        }

        // DHL: 10-11 digits
        if (number.count == 10 || number.count == 11) && number.allSatisfy({ $0.isNumber }) {
            return .dhl
        }

        // Amazon: TBA followed by numbers
        if number.hasPrefix("TBA") {
            return .amazon
        }

        return .other
    }

    // MARK: - Helpers

    private func carrierSlug(_ carrier: Carrier) -> String {
        switch carrier {
        case .ups: return "ups"
        case .fedex: return "fedex"
        case .usps: return "usps"
        case .dhl: return "dhl"
        case .amazon: return "amazon"
        case .ontrac: return "ontrac"
        case .lasership: return "lasership"
        case .other: return "other"
        }
    }

    private func parseStatus(_ tag: String?) -> PackageStatus {
        guard let tag = tag?.lowercased() else { return .unknown }

        switch tag {
        case "pending": return .pending
        case "inforeceived": return .infoReceived
        case "intransit": return .inTransit
        case "outfordelivery": return .outForDelivery
        case "attemptfail": return .attemptFail
        case "delivered": return .delivered
        case "availableforpickup": return .availableForPickup
        case "exception": return .attemptFail
        case "expired": return .expired
        default: return .unknown
        }
    }

    private func shouldRefresh() -> Bool {
        guard let last = lastRefresh else { return true }
        return Date().timeIntervalSince(last) > cacheExpiry
    }

    // MARK: - Email Detection

    func extractTrackingFromEmail(_ emailBody: String) -> [(String, Carrier)]? {
        var results: [(String, Carrier)] = []

        // Common tracking number patterns
        let patterns: [(String, Carrier)] = [
            // UPS
            ("1Z[A-Z0-9]{16}", .ups),
            // FedEx
            ("\\b[0-9]{12}\\b", .fedex),
            ("\\b[0-9]{15}\\b", .fedex),
            ("\\b96[0-9]{18,20}\\b", .fedex),
            // USPS
            ("\\b9[0-9]{21}\\b", .usps),
            ("\\b[0-9]{20,22}\\b", .usps),
            // DHL
            ("\\b[0-9]{10,11}\\b", .dhl),
            // Amazon
            ("TBA[0-9]+", .amazon)
        ]

        for (pattern, carrier) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(
                    in: emailBody,
                    range: NSRange(emailBody.startIndex..., in: emailBody)
                )

                for match in matches {
                    if let range = Range(match.range, in: emailBody) {
                        let trackingNumber = String(emailBody[range])
                        results.append((trackingNumber, carrier))
                    }
                }
            }
        }

        return results.isEmpty ? nil : results
    }
}

// MARK: - Errors

enum PackageTrackingError: Error, LocalizedError {
    case notConfigured
    case registrationFailed
    case trackingFailed
    case carrierNotSupported
    case parseError
    case invalidTrackingNumber

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Package tracking service not configured"
        case .registrationFailed: return "Failed to register package for tracking"
        case .trackingFailed: return "Failed to get tracking information"
        case .carrierNotSupported: return "Carrier not supported for direct tracking"
        case .parseError: return "Failed to parse tracking response"
        case .invalidTrackingNumber: return "Invalid tracking number"
        }
    }
}
