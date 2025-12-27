import Foundation
import CoreLocation
import MapKit

/// Location intelligence service for contextual awareness
actor LocationService: NSObject {
    // MARK: - Location Manager

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    // MARK: - State

    private var currentLocation: CLLocation?
    private var currentPlacemark: CLPlacemark?
    private var locationHistory: [LocationEntry] = []
    private var savedPlaces: [SavedPlace] = []
    private var geofences: [Geofence] = []

    // MARK: - Continuation for async

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    func initialize() async throws {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = locationManager.authorizationStatus

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Would need to implement proper async waiting
            return true
        default:
            return false
        }
    }

    func requestAlwaysAuthorization() async {
        locationManager.requestAlwaysAuthorization()
    }

    var isAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    // MARK: - Current Location

    func getCurrentLocation() async throws -> CLLocation {
        if let cached = currentLocation,
           Date().timeIntervalSince(cached.timestamp) < 60 {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    func getCurrentPlacemark() async throws -> CLPlacemark {
        let location = try await getCurrentLocation()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)

        guard let placemark = placemarks.first else {
            throw LocationError.geocodingFailed
        }

        currentPlacemark = placemark
        return placemark
    }

    func getCurrentAddress() async throws -> String {
        let placemark = try await getCurrentPlacemark()
        return formatAddress(placemark)
    }

    func getCurrentCity() async throws -> String {
        let placemark = try await getCurrentPlacemark()
        return placemark.locality ?? "Unknown"
    }

    // MARK: - Location Context

    func getLocationContext() async throws -> LocationContext {
        let location = try await getCurrentLocation()
        let placemark = try await getCurrentPlacemark()

        // Determine place type
        let placeType = determinePlaceType(placemark)

        // Check if at known place
        let matchedPlace = savedPlaces.first { place in
            location.distance(from: place.location) < place.radius
        }

        // Get nearby POIs
        let nearbyPOIs = try await searchNearbyPOIs(
            location: location,
            types: [.restaurant, .cafe, .store]
        )

        return LocationContext(
            location: location,
            placemark: placemark,
            placeType: placeType,
            savedPlace: matchedPlace,
            nearbyPOIs: nearbyPOIs,
            isHome: matchedPlace?.type == .home,
            isWork: matchedPlace?.type == .work
        )
    }

    private func determinePlaceType(_ placemark: CLPlacemark) -> PlaceType {
        if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
            let firstArea = areasOfInterest.first?.lowercased() ?? ""

            if firstArea.contains("airport") { return .airport }
            if firstArea.contains("hospital") || firstArea.contains("medical") { return .hospital }
            if firstArea.contains("gym") || firstArea.contains("fitness") { return .gym }
            if firstArea.contains("restaurant") { return .restaurant }
            if firstArea.contains("store") || firstArea.contains("mall") { return .store }
            if firstArea.contains("hotel") { return .hotel }
        }

        return .other
    }

    // MARK: - Geocoding

    func geocodeAddress(_ address: String) async throws -> CLLocation {
        let placemarks = try await geocoder.geocodeAddressString(address)

        guard let placemark = placemarks.first,
              let location = placemark.location else {
            throw LocationError.geocodingFailed
        }

        return location
    }

    func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)

        guard let placemark = placemarks.first else {
            throw LocationError.geocodingFailed
        }

        return placemark
    }

    // MARK: - Distance & ETA

    func getDistance(to destination: CLLocation) async throws -> Double {
        let current = try await getCurrentLocation()
        return current.distance(from: destination)
    }

    func getDistance(toAddress address: String) async throws -> Double {
        let destination = try await geocodeAddress(address)
        return try await getDistance(to: destination)
    }

    func getETA(
        to destination: CLLocation,
        transportType: MKDirectionsTransportType = .automobile
    ) async throws -> TimeInterval {
        let current = try await getCurrentLocation()

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transportType

        let directions = MKDirections(request: request)
        let response = try await directions.calculateETA()

        return response.expectedTravelTime
    }

    func getETAToAddress(_ address: String) async throws -> TimeInterval {
        let destination = try await geocodeAddress(address)
        return try await getETA(to: destination)
    }

    func getDirections(
        to destination: CLLocation,
        transportType: MKDirectionsTransportType = .automobile
    ) async throws -> [MKRoute] {
        let current = try await getCurrentLocation()

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transportType
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        return response.routes
    }

    // MARK: - POI Search

    func searchNearbyPOIs(
        location: CLLocation? = nil,
        types: [POIType],
        radius: Double = 500
    ) async throws -> [PointOfInterest] {
        let searchLocation = location ?? (try await getCurrentLocation())

        var allPOIs: [PointOfInterest] = []

        for type in types {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = type.searchQuery
            request.region = MKCoordinateRegion(
                center: searchLocation.coordinate,
                latitudinalMeters: radius,
                longitudinalMeters: radius
            )

            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            let pois = response.mapItems.map { item in
                PointOfInterest(
                    name: item.name ?? "",
                    type: type,
                    location: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ),
                    address: formatAddress(item.placemark),
                    phone: item.phoneNumber,
                    url: item.url,
                    distance: item.placemark.location?.distance(from: searchLocation)
                )
            }

            allPOIs.append(contentsOf: pois)
        }

        return allPOIs.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    func searchPOIs(query: String, radius: Double = 1000) async throws -> [PointOfInterest] {
        let location = try await getCurrentLocation()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response.mapItems.map { item in
            PointOfInterest(
                name: item.name ?? "",
                type: .other,
                location: CLLocation(
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                ),
                address: formatAddress(item.placemark),
                phone: item.phoneNumber,
                url: item.url,
                distance: item.placemark.location?.distance(from: location)
            )
        }
    }

    // MARK: - Saved Places

    func savePlace(
        name: String,
        location: CLLocation,
        type: SavedPlaceType,
        radius: Double = 100
    ) async -> SavedPlace {
        let place = SavedPlace(
            name: name,
            location: location,
            type: type,
            radius: radius
        )

        savedPlaces.append(place)
        return place
    }

    func setHome(location: CLLocation) async -> SavedPlace {
        // Remove existing home
        savedPlaces.removeAll { $0.type == .home }
        return await savePlace(name: "Home", location: location, type: .home)
    }

    func setWork(location: CLLocation) async -> SavedPlace {
        // Remove existing work
        savedPlaces.removeAll { $0.type == .work }
        return await savePlace(name: "Work", location: location, type: .work)
    }

    func getSavedPlaces() async -> [SavedPlace] {
        savedPlaces
    }

    func getHome() async -> SavedPlace? {
        savedPlaces.first { $0.type == .home }
    }

    func getWork() async -> SavedPlace? {
        savedPlaces.first { $0.type == .work }
    }

    func removeSavedPlace(id: UUID) async {
        savedPlaces.removeAll { $0.id == id }
    }

    // MARK: - Geofencing

    func addGeofence(
        center: CLLocation,
        radius: Double,
        identifier: String,
        onEnter: Bool = true,
        onExit: Bool = true
    ) async -> Geofence {
        let region = CLCircularRegion(
            center: center.coordinate,
            radius: radius,
            identifier: identifier
        )
        region.notifyOnEntry = onEnter
        region.notifyOnExit = onExit

        locationManager.startMonitoring(for: region)

        let geofence = Geofence(
            identifier: identifier,
            center: center,
            radius: radius,
            notifyOnEnter: onEnter,
            notifyOnExit: onExit
        )

        geofences.append(geofence)
        return geofence
    }

    func removeGeofence(_ geofence: Geofence) async {
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == geofence.identifier }) {
            locationManager.stopMonitoring(for: region)
        }
        geofences.removeAll { $0.id == geofence.id }
    }

    func getActiveGeofences() async -> [Geofence] {
        geofences
    }

    // MARK: - Location History

    func recordLocation(_ location: CLLocation) async {
        let entry = LocationEntry(
            location: location,
            timestamp: Date()
        )
        locationHistory.append(entry)

        // Keep last 1000 entries
        if locationHistory.count > 1000 {
            locationHistory.removeFirst(locationHistory.count - 1000)
        }
    }

    func getLocationHistory(since date: Date) async -> [LocationEntry] {
        locationHistory.filter { $0.timestamp >= date }
    }

    func getRecentLocations(limit: Int = 10) async -> [LocationEntry] {
        Array(locationHistory.suffix(limit))
    }

    // MARK: - Commute Prediction

    func predictCommute(from: SavedPlace, to: SavedPlace) async throws -> CommutePrediction {
        let eta = try await getETA(to: to.location)

        // Would use historical data for better predictions
        let typicalDuration = eta
        let currentConditions = "Normal traffic"

        return CommutePrediction(
            from: from,
            to: to,
            estimatedDuration: eta,
            typicalDuration: typicalDuration,
            trafficConditions: currentConditions,
            suggestedDepartureTime: Date().addingTimeInterval(-eta)
        )
    }

    func getCommuteToWork() async throws -> CommutePrediction? {
        guard let home = await getHome(),
              let work = await getWork() else {
            return nil
        }

        return try await predictCommute(from: home, to: work)
    }

    func getCommuteHome() async throws -> CommutePrediction? {
        guard let home = await getHome(),
              let work = await getWork() else {
            return nil
        }

        return try await predictCommute(from: work, to: home)
    }

    // MARK: - Maps Deep Links

    func getDirectionsURL(to destination: CLLocation, mode: TransportMode = .driving) -> URL? {
        var components = URLComponents(string: "http://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(destination.coordinate.latitude),\(destination.coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: mode.mapsFlag)
        ]
        return components.url
    }

    func getDirectionsURL(toAddress address: String, mode: TransportMode = .driving) -> URL? {
        var components = URLComponents(string: "http://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: address),
            URLQueryItem(name: "dirflg", value: mode.mapsFlag)
        ]
        return components.url
    }

    // MARK: - Helpers

    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var parts: [String] = []

        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                parts.append("\(number) \(street)")
            } else {
                parts.append(street)
            }
        }

        if let city = placemark.locality {
            parts.append(city)
        }

        if let state = placemark.administrativeArea {
            parts.append(state)
        }

        return parts.joined(separator: ", ")
    }

    private func formatAddress(_ placemark: MKPlacemark) -> String {
        var parts: [String] = []

        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                parts.append("\(number) \(street)")
            } else {
                parts.append(street)
            }
        }

        if let city = placemark.locality {
            parts.append(city)
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task {
            await handleLocationUpdate(location)
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        currentLocation = location
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task {
            await handleLocationError(error)
        }
    }

    private func handleLocationError(_ error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // Handle geofence entry
        NotificationCenter.default.post(
            name: .geofenceEntered,
            object: nil,
            userInfo: ["region": region]
        )
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // Handle geofence exit
        NotificationCenter.default.post(
            name: .geofenceExited,
            object: nil,
            userInfo: ["region": region]
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let geofenceEntered = Notification.Name("geofenceEntered")
    static let geofenceExited = Notification.Name("geofenceExited")
}

// MARK: - Models

struct LocationContext {
    let location: CLLocation
    let placemark: CLPlacemark
    let placeType: PlaceType
    let savedPlace: SavedPlace?
    let nearbyPOIs: [PointOfInterest]
    let isHome: Bool
    let isWork: Bool

    var addressString: String {
        var parts: [String] = []
        if let street = placemark.thoroughfare { parts.append(street) }
        if let city = placemark.locality { parts.append(city) }
        return parts.joined(separator: ", ")
    }
}

struct LocationEntry: Identifiable {
    let id: UUID = UUID()
    let location: CLLocation
    let timestamp: Date
}

struct SavedPlace: Identifiable, Codable {
    let id: UUID
    var name: String
    var location: CLLocation
    var type: SavedPlaceType
    var radius: Double
    var address: String?

    init(
        id: UUID = UUID(),
        name: String,
        location: CLLocation,
        type: SavedPlaceType,
        radius: Double = 100,
        address: String? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.type = type
        self.radius = radius
        self.address = address
    }
}

enum SavedPlaceType: String, Codable {
    case home
    case work
    case gym
    case school
    case favorite
    case other
}

struct PointOfInterest: Identifiable {
    let id: UUID = UUID()
    var name: String
    var type: POIType
    var location: CLLocation
    var address: String
    var phone: String?
    var url: URL?
    var distance: Double?

    var distanceString: String {
        guard let meters = distance else { return "" }
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }
}

enum POIType {
    case restaurant
    case cafe
    case store
    case gasStation
    case parking
    case hospital
    case pharmacy
    case gym
    case bank
    case atm
    case other

    var searchQuery: String {
        switch self {
        case .restaurant: return "restaurant"
        case .cafe: return "cafe coffee"
        case .store: return "store"
        case .gasStation: return "gas station"
        case .parking: return "parking"
        case .hospital: return "hospital"
        case .pharmacy: return "pharmacy"
        case .gym: return "gym fitness"
        case .bank: return "bank"
        case .atm: return "atm"
        case .other: return ""
        }
    }
}

enum PlaceType {
    case home
    case work
    case airport
    case hospital
    case gym
    case restaurant
    case store
    case hotel
    case other
}

struct Geofence: Identifiable {
    let id: UUID = UUID()
    let identifier: String
    let center: CLLocation
    let radius: Double
    let notifyOnEnter: Bool
    let notifyOnExit: Bool
}

struct CommutePrediction {
    let from: SavedPlace
    let to: SavedPlace
    let estimatedDuration: TimeInterval
    let typicalDuration: TimeInterval
    let trafficConditions: String
    let suggestedDepartureTime: Date

    var durationMinutes: Int {
        Int(estimatedDuration / 60)
    }

    var isDelayed: Bool {
        estimatedDuration > typicalDuration * 1.2
    }
}

enum TransportMode {
    case driving
    case walking
    case transit
    case cycling

    var mapsFlag: String {
        switch self {
        case .driving: return "d"
        case .walking: return "w"
        case .transit: return "r"
        case .cycling: return "b"
        }
    }
}

// MARK: - Errors

enum LocationError: Error, LocalizedError {
    case notAuthorized
    case locationUnavailable
    case geocodingFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Location access not authorized"
        case .locationUnavailable: return "Location unavailable"
        case .geocodingFailed: return "Geocoding failed"
        }
    }
}
