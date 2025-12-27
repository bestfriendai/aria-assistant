import Foundation
import CoreML
import NaturalLanguage

/// On-device intent classifier for common queries
/// Provides <25ms response for cached intents
actor LocalIntentClassifier {
    // MARK: - Intent Categories

    enum Intent: String, CaseIterable {
        // Communication
        case readEmail = "read_email"
        case sendEmail = "send_email"
        case call = "call"
        case text = "text"

        // Calendar
        case checkCalendar = "check_calendar"
        case scheduleEvent = "schedule_event"
        case cancelEvent = "cancel_event"

        // Tasks & Reminders
        case addTask = "add_task"
        case listTasks = "list_tasks"
        case completeTask = "complete_task"
        case addReminder = "add_reminder"
        case listReminders = "list_reminders"

        // Banking
        case checkBalance = "check_balance"
        case recentTransactions = "recent_transactions"
        case spendingSummary = "spending_summary"

        // Shopping
        case addToCart = "add_to_cart"
        case orderStatus = "order_status"
        case reorder = "reorder"

        // Package Tracking
        case trackPackage = "track_package"
        case packageStatus = "package_status"
        case addTracking = "add_tracking"

        // Smart Home
        case controlLight = "control_light"
        case controlThermostat = "control_thermostat"
        case lockDoor = "lock_door"
        case homeStatus = "home_status"
        case runScene = "run_scene"

        // Travel
        case checkFlight = "check_flight"
        case flightStatus = "flight_status"
        case tripInfo = "trip_info"
        case addFlight = "add_flight"

        // Ride Sharing
        case orderRide = "order_ride"
        case rideEstimate = "ride_estimate"
        case rideStatus = "ride_status"

        // Music
        case playMusic = "play_music"
        case pauseMusic = "pause_music"
        case skipTrack = "skip_track"
        case whatPlaying = "what_playing"

        // Weather
        case checkWeather = "check_weather"
        case weatherForecast = "weather_forecast"
        case willRain = "will_rain"

        // Notes
        case createNote = "create_note"
        case searchNotes = "search_notes"
        case readNote = "read_note"

        // Work Communications
        case checkSlack = "check_slack"
        case sendSlackMessage = "send_slack_message"
        case workStatus = "work_status"
        case setStatus = "set_status"

        // Health
        case healthSummary = "health_summary"
        case checkSteps = "check_steps"
        case checkSleep = "check_sleep"
        case logWater = "log_water"
        case medicationReminder = "medication_reminder"

        // Subscriptions
        case listSubscriptions = "list_subscriptions"
        case subscriptionCost = "subscription_cost"

        // Reservations
        case findRestaurant = "find_restaurant"
        case makeReservation = "make_reservation"
        case checkReservation = "check_reservation"

        // Parking
        case findParking = "find_parking"
        case parkingStatus = "parking_status"
        case whereParked = "where_parked"

        // News
        case getNews = "get_news"
        case newsHeadlines = "news_headlines"
        case newsBriefing = "news_briefing"

        // Location
        case whereAmI = "where_am_i"
        case etaTo = "eta_to"
        case directionsTo = "directions_to"
        case nearbyPlaces = "nearby_places"

        // Photos
        case recentPhotos = "recent_photos"
        case findPhotos = "find_photos"

        // Shortcuts
        case runShortcut = "run_shortcut"

        // Meta
        case briefing = "briefing"
        case attention = "attention"
        case cancel = "cancel"
        case confirm = "confirm"

        // Fallback
        case unknown = "unknown"
    }

    struct ClassificationResult {
        let intent: Intent
        let confidence: Double
        let entities: [String: String]
    }

    // MARK: - Pattern Matching

    private let intentPatterns: [Intent: [String]] = [
        // Communication
        .readEmail: [
            "read my email", "check email", "any new emails", "important emails",
            "read messages", "check my inbox", "what emails"
        ],
        .sendEmail: [
            "send email", "email to", "reply to", "write email", "compose email"
        ],
        .call: [
            "call", "phone", "dial", "ring"
        ],
        .text: [
            "text", "message", "send a text", "sms"
        ],

        // Calendar
        .checkCalendar: [
            "what's on my calendar", "my schedule", "what's my day", "meetings today",
            "when am I free", "calendar", "what's next", "upcoming events"
        ],
        .scheduleEvent: [
            "schedule", "add to calendar", "create event", "book", "set up a meeting"
        ],
        .cancelEvent: [
            "cancel meeting", "cancel event", "remove from calendar", "delete event"
        ],

        // Tasks & Reminders
        .addTask: [
            "add task", "add to my list", "create a task", "todo"
        ],
        .listTasks: [
            "what should I do", "my tasks", "todo list", "what's on my list",
            "what's overdue", "pending tasks"
        ],
        .completeTask: [
            "mark done", "complete task", "finished", "done with"
        ],
        .addReminder: [
            "remind me", "set reminder", "don't let me forget"
        ],
        .listReminders: [
            "my reminders", "what reminders", "reminders today", "reminders due"
        ],

        // Banking
        .checkBalance: [
            "balance", "how much in my account", "account balance", "how much do I have"
        ],
        .recentTransactions: [
            "recent transactions", "what did I spend", "purchases", "charges"
        ],
        .spendingSummary: [
            "spending", "how much spent", "expenses", "budget"
        ],

        // Shopping
        .addToCart: [
            "add to cart", "order", "buy", "get me", "need to buy"
        ],
        .orderStatus: [
            "order status", "where's my order", "delivery status"
        ],
        .reorder: [
            "reorder", "order again", "same as last time", "usual order"
        ],

        // Package Tracking
        .trackPackage: [
            "track package", "track my package", "where's my package", "package tracking"
        ],
        .packageStatus: [
            "package status", "delivery update", "when will my package arrive"
        ],
        .addTracking: [
            "add tracking", "track this", "add tracking number"
        ],

        // Smart Home
        .controlLight: [
            "turn on lights", "turn off lights", "dim the lights", "lights on",
            "lights off", "turn on the", "turn off the", "set brightness"
        ],
        .controlThermostat: [
            "set temperature", "turn up heat", "turn down heat", "set thermostat",
            "make it warmer", "make it cooler", "what's the temperature"
        ],
        .lockDoor: [
            "lock door", "unlock door", "lock up", "lock the house", "is door locked"
        ],
        .homeStatus: [
            "home status", "house status", "are all doors locked", "security status"
        ],
        .runScene: [
            "run scene", "activate scene", "movie mode", "bedtime", "good night",
            "good morning", "i'm home", "i'm leaving"
        ],

        // Travel
        .checkFlight: [
            "my flight", "flight status", "when's my flight", "flight info"
        ],
        .flightStatus: [
            "is my flight on time", "flight delayed", "gate change"
        ],
        .tripInfo: [
            "my trip", "trip details", "upcoming trip", "travel plans"
        ],
        .addFlight: [
            "add flight", "track flight", "add my flight"
        ],

        // Ride Sharing
        .orderRide: [
            "get me a ride", "call uber", "call lyft", "order a ride",
            "get an uber", "get a lyft", "i need a ride"
        ],
        .rideEstimate: [
            "how much is an uber", "ride estimate", "uber price", "lyft price"
        ],
        .rideStatus: [
            "where's my ride", "ride status", "when will driver arrive", "driver eta"
        ],

        // Music
        .playMusic: [
            "play music", "play song", "play artist", "play album", "play playlist",
            "put on some music", "play"
        ],
        .pauseMusic: [
            "pause", "stop music", "pause music", "stop playing"
        ],
        .skipTrack: [
            "skip", "next song", "skip track", "play next", "previous song"
        ],
        .whatPlaying: [
            "what's playing", "what song is this", "who is this", "what's this song"
        ],

        // Weather
        .checkWeather: [
            "what's the weather", "how's the weather", "weather today", "current weather",
            "is it cold", "is it hot", "temperature outside"
        ],
        .weatherForecast: [
            "weather forecast", "weather tomorrow", "weekend weather", "weather this week"
        ],
        .willRain: [
            "will it rain", "do I need umbrella", "rain today", "chance of rain"
        ],

        // Notes
        .createNote: [
            "create note", "new note", "make a note", "write note", "take a note"
        ],
        .searchNotes: [
            "find note", "search notes", "note about", "where's my note"
        ],
        .readNote: [
            "read note", "show note", "open note"
        ],

        // Work Communications
        .checkSlack: [
            "check slack", "slack messages", "new messages on slack", "slack notifications"
        ],
        .sendSlackMessage: [
            "message on slack", "slack message to", "send slack"
        ],
        .workStatus: [
            "work messages", "unread work messages", "teams messages"
        ],
        .setStatus: [
            "set status", "set my status", "update status", "change status",
            "set away", "set do not disturb"
        ],

        // Health
        .healthSummary: [
            "health summary", "how am I doing", "health stats", "my health"
        ],
        .checkSteps: [
            "how many steps", "step count", "steps today", "did I hit my steps"
        ],
        .checkSleep: [
            "how did I sleep", "sleep last night", "sleep quality", "hours slept"
        ],
        .logWater: [
            "log water", "drank water", "add water", "water intake"
        ],
        .medicationReminder: [
            "medication", "take medicine", "did I take my pills", "medication reminder"
        ],

        // Subscriptions
        .listSubscriptions: [
            "my subscriptions", "what subscriptions", "recurring charges"
        ],
        .subscriptionCost: [
            "subscription cost", "how much on subscriptions", "subscription spending"
        ],

        // Reservations
        .findRestaurant: [
            "find restaurant", "restaurants nearby", "where to eat", "good restaurant"
        ],
        .makeReservation: [
            "make reservation", "book a table", "reserve table", "dinner reservation"
        ],
        .checkReservation: [
            "my reservation", "reservation details", "upcoming reservation"
        ],

        // Parking
        .findParking: [
            "find parking", "parking nearby", "where to park", "parking options"
        ],
        .parkingStatus: [
            "parking status", "parking expires", "extend parking"
        ],
        .whereParked: [
            "where did I park", "find my car", "where's my car", "parked car"
        ],

        // News
        .getNews: [
            "news", "what's in the news", "latest news", "news about"
        ],
        .newsHeadlines: [
            "headlines", "top headlines", "top stories", "breaking news"
        ],
        .newsBriefing: [
            "news briefing", "news summary", "catch me up on news"
        ],

        // Location
        .whereAmI: [
            "where am I", "my location", "current location"
        ],
        .etaTo: [
            "how long to get to", "eta to", "time to", "how far is"
        ],
        .directionsTo: [
            "directions to", "navigate to", "how do I get to", "take me to"
        ],
        .nearbyPlaces: [
            "what's nearby", "nearby", "places near me", "around here"
        ],

        // Photos
        .recentPhotos: [
            "recent photos", "latest photos", "photos from today"
        ],
        .findPhotos: [
            "find photos", "photos from", "photos of", "search photos"
        ],

        // Shortcuts
        .runShortcut: [
            "run shortcut", "run workflow", "execute shortcut"
        ],

        // Meta
        .briefing: [
            "give me the rundown", "morning briefing", "what's happening",
            "catch me up", "summary", "daily briefing"
        ],
        .attention: [
            "what needs attention", "what's important", "priorities", "urgent"
        ],
        .cancel: [
            "cancel", "never mind", "stop", "forget it"
        ],
        .confirm: [
            "yes", "confirm", "do it", "go ahead", "sounds good", "that's right"
        ]
    ]

    // MARK: - NLP Components

    private let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
    private var frequentQueryCache: [String: ClassificationResult] = [:]

    // MARK: - Classification

    func classify(_ text: String) async -> ClassificationResult {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check cache first
        if let cached = frequentQueryCache[normalizedText] {
            return cached
        }

        // Pattern matching
        var bestMatch: (Intent, Double) = (.unknown, 0.0)

        for (intent, patterns) in intentPatterns {
            for pattern in patterns {
                let similarity = calculateSimilarity(normalizedText, pattern)
                if similarity > bestMatch.1 {
                    bestMatch = (intent, similarity)
                }
            }
        }

        // Extract entities
        let entities = extractEntities(from: text)

        let result = ClassificationResult(
            intent: bestMatch.0,
            confidence: bestMatch.1,
            entities: entities
        )

        // Cache high-confidence results
        if result.confidence > 0.8 {
            frequentQueryCache[normalizedText] = result
        }

        return result
    }

    // MARK: - Similarity

    private func calculateSimilarity(_ text: String, _ pattern: String) -> Double {
        // Simple word overlap similarity
        let textWords = Set(text.split(separator: " ").map { String($0) })
        let patternWords = Set(pattern.split(separator: " ").map { String($0) })

        guard !patternWords.isEmpty else { return 0 }

        // Check for exact pattern match
        if text.contains(pattern) {
            return 1.0
        }

        // Word overlap
        let intersection = textWords.intersection(patternWords)
        let overlapScore = Double(intersection.count) / Double(patternWords.count)

        return overlapScore
    }

    // MARK: - Entity Extraction

    private func extractEntities(from text: String) -> [String: String] {
        var entities: [String: String] = [:]

        tagger.string = text

        // Extract named entities
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            if let tag = tag {
                let value = String(text[range])
                switch tag {
                case .personalName:
                    entities["person"] = value
                case .organizationName:
                    entities["organization"] = value
                case .placeName:
                    entities["location"] = value
                default:
                    break
                }
            }
            return true
        }

        // Extract time expressions
        let timePatterns = [
            "today", "tomorrow", "tonight", "this morning", "this afternoon",
            "this evening", "next week", "monday", "tuesday", "wednesday",
            "thursday", "friday", "saturday", "sunday"
        ]

        let lowercased = text.lowercased()
        for pattern in timePatterns {
            if lowercased.contains(pattern) {
                entities["time"] = pattern
                break
            }
        }

        // Extract money amounts
        let moneyPattern = try? NSRegularExpression(pattern: "\\$[\\d,]+(?:\\.\\d{2})?")
        if let match = moneyPattern?.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) {
            if let range = Range(match.range, in: text) {
                entities["amount"] = String(text[range])
            }
        }

        return entities
    }

    // MARK: - Cache Management

    func clearCache() {
        frequentQueryCache.removeAll()
    }

    func preloadCommonQueries() {
        // Pre-classify common queries
        let commonQueries = [
            "what's my day look like",
            "read my emails",
            "what needs my attention",
            "check my balance",
            "what's on my calendar today"
        ]

        Task {
            for query in commonQueries {
                _ = await classify(query)
            }
        }
    }
}
