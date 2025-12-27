import Foundation

/// Unified email model across all providers
struct Email: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: EmailProvider
    let providerMessageId: String
    let threadId: String?

    let from: EmailAddress
    let to: [EmailAddress]
    let cc: [EmailAddress]
    let bcc: [EmailAddress]
    let replyTo: EmailAddress?

    let subject: String
    let snippet: String // First ~200 chars
    let body: String?
    let bodyHtml: String?

    var isRead: Bool
    var isStarred: Bool
    var isArchived: Bool
    var labels: [String]

    let hasAttachments: Bool
    let attachmentCount: Int

    let receivedAt: Date
    let sentAt: Date?

    // AI-computed fields
    var priorityScore: Int // 0-100
    var embedding: [Float]?
    var extractedActions: [ExtractedAction]
    var extractedDeadlines: [Date]
    var requiresResponse: Bool
    var sentiment: Sentiment?

    init(
        id: UUID = UUID(),
        provider: EmailProvider,
        providerMessageId: String,
        threadId: String? = nil,
        from: EmailAddress,
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        replyTo: EmailAddress? = nil,
        subject: String,
        snippet: String,
        body: String? = nil,
        bodyHtml: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        isArchived: Bool = false,
        labels: [String] = [],
        hasAttachments: Bool = false,
        attachmentCount: Int = 0,
        receivedAt: Date = Date(),
        sentAt: Date? = nil,
        priorityScore: Int = 50,
        embedding: [Float]? = nil,
        extractedActions: [ExtractedAction] = [],
        extractedDeadlines: [Date] = [],
        requiresResponse: Bool = false,
        sentiment: Sentiment? = nil
    ) {
        self.id = id
        self.provider = provider
        self.providerMessageId = providerMessageId
        self.threadId = threadId
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.subject = subject
        self.snippet = snippet
        self.body = body
        self.bodyHtml = bodyHtml
        self.isRead = isRead
        self.isStarred = isStarred
        self.isArchived = isArchived
        self.labels = labels
        self.hasAttachments = hasAttachments
        self.attachmentCount = attachmentCount
        self.receivedAt = receivedAt
        self.sentAt = sentAt
        self.priorityScore = priorityScore
        self.embedding = embedding
        self.extractedActions = extractedActions
        self.extractedDeadlines = extractedDeadlines
        self.requiresResponse = requiresResponse
        self.sentiment = sentiment
    }

    /// Calculate urgency for attention items
    var urgency: Double {
        var score = Double(priorityScore) / 100.0 * 0.4

        // Unread bonus
        if !isRead { score += 0.2 }

        // Requires response bonus
        if requiresResponse { score += 0.2 }

        // Recency bonus
        let hoursAgo = Date().timeIntervalSince(receivedAt) / 3600
        if hoursAgo < 1 { score += 0.2 }
        else if hoursAgo < 6 { score += 0.1 }

        return min(1.0, score)
    }
}

enum EmailProvider: String, Codable, Hashable {
    case gmail
    case outlook
    case icloud
    case other
}

struct EmailAddress: Codable, Hashable {
    let email: String
    let name: String?

    var displayName: String {
        name ?? email
    }
}

struct ExtractedAction: Codable, Hashable {
    let description: String
    let dueDate: Date?
    let confidence: Double
}

enum Sentiment: String, Codable {
    case positive
    case neutral
    case negative
    case urgent
}

// MARK: - Priority Scoring
extension Email {
    /// Calculate priority using multiple signals
    static func calculatePriority(
        senderImportance: Double, // 0-1 based on history
        hasDeadline: Bool,
        requiresResponse: Bool,
        isThread: Bool,
        unreadInThread: Int,
        keywords: [String]
    ) -> Int {
        var score: Double = 0

        // Sender importance (0.35)
        score += senderImportance * 0.35

        // Content urgency (0.35)
        var contentScore = 0.0
        if hasDeadline { contentScore += 0.4 }
        if requiresResponse { contentScore += 0.3 }

        let urgentKeywords = ["urgent", "asap", "immediately", "deadline", "critical", "important"]
        for keyword in keywords {
            if urgentKeywords.contains(keyword.lowercased()) {
                contentScore += 0.1
            }
        }
        score += min(1.0, contentScore) * 0.35

        // Thread activity (0.15)
        if isThread {
            let threadScore = min(1.0, Double(unreadInThread) * 0.2)
            score += threadScore * 0.15
        }

        // Time sensitivity (0.15)
        // This would be calculated based on extractedDeadlines
        score += 0.5 * 0.15 // Default medium

        return Int(score * 100)
    }
}
