import Foundation

/// Music/Media models
struct NowPlaying: Codable {
    var title: String
    var artist: String
    var album: String?
    var artwork: String? // URL
    var duration: TimeInterval
    var currentPosition: TimeInterval
    var isPlaying: Bool
    var source: MusicSource

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentPosition / duration
    }

    var remainingTime: TimeInterval {
        duration - currentPosition
    }
}

enum MusicSource: String, Codable {
    case appleMusic
    case spotify
    case podcast
    case audiobook
    case other
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String // Apple Music or Spotify ID
    var name: String
    var description: String?
    var trackCount: Int
    var duration: TimeInterval
    var artwork: String?
    var source: MusicSource
    var isUserCreated: Bool

    var durationFormatted: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

struct MusicTrack: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var artwork: String?
    var source: MusicSource
}

struct Podcast: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String
    var name: String
    var author: String
    var description: String?
    var artwork: String?
    var latestEpisode: PodcastEpisode?
    var unplayedCount: Int
    var isSubscribed: Bool
}

struct PodcastEpisode: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String
    var title: String
    var description: String?
    var duration: TimeInterval
    var publishDate: Date
    var isPlayed: Bool
    var playbackPosition: TimeInterval
    var artwork: String?

    var isInProgress: Bool {
        playbackPosition > 0 && !isPlayed
    }

    var remainingTime: TimeInterval {
        duration - playbackPosition
    }
}

/// News models
struct NewsArticle: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String
    var title: String
    var summary: String?
    var content: String?
    var author: String?
    var source: String
    var url: String
    var imageUrl: String?
    var publishedAt: Date
    var category: NewsCategory
    var isRead: Bool
    var isSaved: Bool

    var timeAgo: String {
        let interval = Date().timeIntervalSince(publishedAt)
        if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
}

enum NewsCategory: String, Codable, CaseIterable {
    case topStories = "top_stories"
    case technology
    case business
    case sports
    case entertainment
    case science
    case health
    case politics
    case world
    case local
    case custom

    var displayName: String {
        switch self {
        case .topStories: return "Top Stories"
        default: return rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .topStories: return "newspaper.fill"
        case .technology: return "laptopcomputer"
        case .business: return "chart.line.uptrend.xyaxis"
        case .sports: return "sportscourt.fill"
        case .entertainment: return "film.fill"
        case .science: return "atom"
        case .health: return "heart.fill"
        case .politics: return "building.columns.fill"
        case .world: return "globe"
        case .local: return "location.fill"
        case .custom: return "star.fill"
        }
    }
}

/// Weather models
struct Weather: Codable {
    var location: String
    var latitude: Double
    var longitude: Double

    var current: CurrentWeather
    var hourly: [HourlyForecast]
    var daily: [DailyForecast]
    var alerts: [WeatherAlert]

    var lastUpdated: Date
}

struct CurrentWeather: Codable {
    var temperature: Double // Celsius
    var feelsLike: Double
    var humidity: Int // percentage
    var windSpeed: Double // km/h
    var windDirection: Int // degrees
    var uvIndex: Int
    var visibility: Double // km
    var pressure: Double // hPa
    var condition: WeatherCondition
    var conditionDescription: String
    var isDay: Bool

    var temperatureFahrenheit: Double {
        temperature * 9/5 + 32
    }
}

struct HourlyForecast: Identifiable, Codable {
    let id: UUID
    var time: Date
    var temperature: Double
    var feelsLike: Double
    var precipitationChance: Int // percentage
    var condition: WeatherCondition
    var isDay: Bool

    init(
        id: UUID = UUID(),
        time: Date,
        temperature: Double,
        feelsLike: Double,
        precipitationChance: Int,
        condition: WeatherCondition,
        isDay: Bool
    ) {
        self.id = id
        self.time = time
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.precipitationChance = precipitationChance
        self.condition = condition
        self.isDay = isDay
    }
}

struct DailyForecast: Identifiable, Codable {
    let id: UUID
    var date: Date
    var highTemperature: Double
    var lowTemperature: Double
    var precipitationChance: Int
    var condition: WeatherCondition
    var sunrise: Date
    var sunset: Date
    var uvIndex: Int

    init(
        id: UUID = UUID(),
        date: Date,
        highTemperature: Double,
        lowTemperature: Double,
        precipitationChance: Int,
        condition: WeatherCondition,
        sunrise: Date,
        sunset: Date,
        uvIndex: Int
    ) {
        self.id = id
        self.date = date
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.precipitationChance = precipitationChance
        self.condition = condition
        self.sunrise = sunrise
        self.sunset = sunset
        self.uvIndex = uvIndex
    }

    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

struct WeatherAlert: Identifiable, Codable {
    let id: UUID
    var title: String
    var severity: AlertSeverity
    var description: String
    var startTime: Date
    var endTime: Date
    var source: String

    init(
        id: UUID = UUID(),
        title: String,
        severity: AlertSeverity,
        description: String,
        startTime: Date,
        endTime: Date,
        source: String
    ) {
        self.id = id
        self.title = title
        self.severity = severity
        self.description = description
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
    }

    enum AlertSeverity: String, Codable {
        case minor
        case moderate
        case severe
        case extreme
    }
}

enum WeatherCondition: String, Codable {
    case clear
    case partlyCloudy = "partly_cloudy"
    case cloudy
    case overcast
    case fog
    case rain
    case drizzle
    case heavyRain = "heavy_rain"
    case thunderstorm
    case snow
    case sleet
    case hail
    case wind
    case dust
    case smoke

    var icon: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy, .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .rain, .drizzle: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .sleet, .hail: return "cloud.sleet.fill"
        case .wind: return "wind"
        case .dust: return "sun.dust.fill"
        case .smoke: return "smoke.fill"
        }
    }

    var nightIcon: String {
        switch self {
        case .clear: return "moon.stars.fill"
        case .partlyCloudy: return "cloud.moon.fill"
        default: return icon
        }
    }
}
