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

        // Tasks
        case addTask = "add_task"
        case listTasks = "list_tasks"
        case completeTask = "complete_task"

        // Banking
        case checkBalance = "check_balance"
        case recentTransactions = "recent_transactions"
        case spendingSummary = "spending_summary"

        // Shopping
        case addToCart = "add_to_cart"
        case orderStatus = "order_status"
        case reorder = "reorder"

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
        .addTask: [
            "add task", "remind me", "add to my list", "create a task", "todo"
        ],
        .listTasks: [
            "what should I do", "my tasks", "todo list", "what's on my list",
            "what's overdue", "pending tasks"
        ],
        .completeTask: [
            "mark done", "complete task", "finished", "done with"
        ],
        .checkBalance: [
            "balance", "how much in my account", "account balance", "how much do I have"
        ],
        .recentTransactions: [
            "recent transactions", "what did I spend", "purchases", "charges"
        ],
        .spendingSummary: [
            "spending", "how much spent", "expenses", "budget"
        ],
        .addToCart: [
            "add to cart", "order", "buy", "get me", "need to buy"
        ],
        .orderStatus: [
            "order status", "where's my order", "delivery status", "tracking"
        ],
        .reorder: [
            "reorder", "order again", "same as last time", "usual order"
        ],
        .briefing: [
            "give me the rundown", "morning briefing", "what's happening",
            "catch me up", "summary"
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
