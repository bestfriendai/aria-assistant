import Foundation
import WeatherKit
import CoreLocation

/// Weather service using WeatherKit
actor WeatherService {
    // MARK: - WeatherKit

    private let weatherService = WeatherKit.WeatherService.shared

    // MARK: - Cache

    private var currentWeatherCache: Weather?
    private var lastLocation: CLLocation?
    private var lastFetch: Date?
    private let cacheExpiry: TimeInterval = 600 // 10 minutes

    // MARK: - Current Weather

    func getCurrentWeather(for location: CLLocation? = nil) async throws -> Weather {
        let targetLocation = location ?? lastLocation ?? CLLocation(latitude: 37.7749, longitude: -122.4194) // Default SF

        // Check cache
        if let cached = currentWeatherCache,
           let lastFetch = lastFetch,
           Date().timeIntervalSince(lastFetch) < cacheExpiry,
           isSameLocation(targetLocation, lastLocation) {
            return cached
        }

        // Fetch from WeatherKit
        let weather = try await fetchWeather(for: targetLocation)

        currentWeatherCache = weather
        lastLocation = targetLocation
        lastFetch = Date()

        return weather
    }

    func getCurrentWeather(latitude: Double, longitude: Double) async throws -> Weather {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return try await getCurrentWeather(for: location)
    }

    // MARK: - WeatherKit Fetch

    private func fetchWeather(for location: CLLocation) async throws -> Weather {
        let appleWeather = try await weatherService.weather(for: location)

        // Get location name
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        let locationName = placemarks?.first?.locality ?? "Unknown"

        // Map current conditions
        let current = CurrentWeather(
            temperature: appleWeather.currentWeather.temperature.value,
            feelsLike: appleWeather.currentWeather.apparentTemperature.value,
            humidity: Int(appleWeather.currentWeather.humidity * 100),
            windSpeed: appleWeather.currentWeather.wind.speed.value,
            windDirection: Int(appleWeather.currentWeather.wind.direction.value),
            uvIndex: appleWeather.currentWeather.uvIndex.value,
            visibility: appleWeather.currentWeather.visibility.value / 1000, // Convert to km
            pressure: appleWeather.currentWeather.pressure.value,
            condition: mapCondition(appleWeather.currentWeather.condition),
            conditionDescription: appleWeather.currentWeather.condition.description,
            isDay: appleWeather.currentWeather.isDaylight
        )

        // Map hourly forecast
        let hourly: [HourlyForecast] = appleWeather.hourlyForecast.prefix(24).map { hour in
            HourlyForecast(
                time: hour.date,
                temperature: hour.temperature.value,
                feelsLike: hour.apparentTemperature.value,
                precipitationChance: Int(hour.precipitationChance * 100),
                condition: mapCondition(hour.condition),
                isDay: hour.isDaylight
            )
        }

        // Map daily forecast
        let daily: [DailyForecast] = appleWeather.dailyForecast.prefix(10).map { day in
            DailyForecast(
                date: day.date,
                highTemperature: day.highTemperature.value,
                lowTemperature: day.lowTemperature.value,
                precipitationChance: Int(day.precipitationChance * 100),
                condition: mapCondition(day.condition),
                sunrise: day.sun.sunrise ?? day.date,
                sunset: day.sun.sunset ?? day.date,
                uvIndex: day.uvIndex.value
            )
        }

        // Map weather alerts
        let alerts: [WeatherAlert] = appleWeather.weatherAlerts?.map { alert in
            WeatherAlert(
                title: alert.summary,
                severity: mapSeverity(alert.severity),
                description: alert.detailsURL?.absoluteString ?? "",
                startTime: alert.metadata.issueDate,
                endTime: alert.metadata.expirationDate,
                source: alert.source
            )
        } ?? []

        return Weather(
            location: locationName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            current: current,
            hourly: hourly,
            daily: daily,
            alerts: alerts,
            lastUpdated: Date()
        )
    }

    private func mapCondition(_ condition: WeatherCondition) -> Aria.WeatherCondition {
        switch condition {
        case .clear: return .clear
        case .partlyCloudy, .mostlyClear: return .partlyCloudy
        case .cloudy, .mostlyCloudy: return .cloudy
        case .foggy, .haze: return .fog
        case .rain, .drizzle: return .rain
        case .heavyRain: return .heavyRain
        case .thunderstorms: return .thunderstorm
        case .snow, .flurries, .heavySnow, .blizzard: return .snow
        case .sleet, .freezingRain: return .sleet
        case .hail: return .hail
        case .windy, .breezy: return .wind
        case .blowingDust: return .dust
        case .smoky: return .smoke
        default: return .cloudy
        }
    }

    private func mapSeverity(_ severity: WeatherSeverity) -> WeatherAlert.AlertSeverity {
        switch severity {
        case .minor: return .minor
        case .moderate: return .moderate
        case .severe: return .severe
        case .extreme: return .extreme
        default: return .minor
        }
    }

    // MARK: - Helpers

    private func isSameLocation(_ a: CLLocation?, _ b: CLLocation?) -> Bool {
        guard let a = a, let b = b else { return false }
        return a.distance(from: b) < 1000 // Within 1km
    }

    // MARK: - Convenience Methods

    func getTemperature(for location: CLLocation? = nil) async throws -> (current: Double, feelsLike: Double) {
        let weather = try await getCurrentWeather(for: location)
        return (weather.current.temperature, weather.current.feelsLike)
    }

    func willRain(within hours: Int = 6, for location: CLLocation? = nil) async throws -> Bool {
        let weather = try await getCurrentWeather(for: location)
        let upcoming = weather.hourly.prefix(hours)
        return upcoming.contains { $0.precipitationChance > 30 }
    }

    func getRainChance(for location: CLLocation? = nil) async throws -> Int {
        let weather = try await getCurrentWeather(for: location)
        return weather.hourly.first?.precipitationChance ?? 0
    }

    func getWeatherSummary(for location: CLLocation? = nil) async throws -> String {
        let weather = try await getCurrentWeather(for: location)
        let temp = Int(weather.current.temperature)
        let condition = weather.current.conditionDescription

        var summary = "It's \(temp)° and \(condition) in \(weather.location)."

        if !weather.alerts.isEmpty {
            summary += " \(weather.alerts.count) weather alert(s) active."
        }

        if let rain = weather.hourly.first(where: { $0.precipitationChance > 50 }) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h a"
            summary += " Rain likely around \(formatter.string(from: rain.time))."
        }

        return summary
    }

    func shouldBringUmbrella(for location: CLLocation? = nil) async throws -> Bool {
        try await willRain(within: 12, for: location)
    }

    func getUVWarning(for location: CLLocation? = nil) async throws -> String? {
        let weather = try await getCurrentWeather(for: location)
        let uv = weather.current.uvIndex

        if uv >= 11 {
            return "Extreme UV index (\(uv)). Avoid sun exposure."
        } else if uv >= 8 {
            return "Very high UV index (\(uv)). Sun protection essential."
        } else if uv >= 6 {
            return "High UV index (\(uv)). Wear sunscreen."
        }
        return nil
    }
}

// Note: WeatherKit requires app entitlement and Apple Developer Program membership
