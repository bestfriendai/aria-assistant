import Foundation

/// News aggregation service with personalization
actor NewsService {
    // MARK: - Configuration

    private var newsApiKey: String?
    private var appleNewsEnabled: Bool = true

    // MARK: - Cache

    private var articlesCache: [NewsArticle] = []
    private var topicsCache: [NewsTopic] = []
    private var sourcesCache: [NewsSource] = []
    private var lastRefresh: Date?
    private let cacheExpiry: TimeInterval = 900 // 15 minutes

    // MARK: - User Preferences

    private var followedTopics: Set<String> = []
    private var followedSources: Set<String> = []
    private var blockedSources: Set<String> = []
    private var readArticles: Set<String> = []
    private var savedArticles: [NewsArticle] = []

    // MARK: - Configuration

    func configure(newsApiKey: String? = nil, appleNewsEnabled: Bool = true) {
        self.newsApiKey = newsApiKey
        self.appleNewsEnabled = appleNewsEnabled
    }

    func setPreferences(
        topics: [String]? = nil,
        sources: [String]? = nil,
        blockedSources: [String]? = nil
    ) async {
        if let topics = topics {
            followedTopics = Set(topics)
        }
        if let sources = sources {
            followedSources = Set(sources)
        }
        if let blocked = blockedSources {
            self.blockedSources = Set(blocked)
        }
    }

    // MARK: - Fetch News

    func getTopHeadlines(
        country: String = "us",
        category: NewsCategory? = nil,
        limit: Int = 20
    ) async throws -> [NewsArticle] {
        guard let apiKey = newsApiKey else {
            throw NewsServiceError.notConfigured
        }

        var urlComponents = URLComponents(string: "https://newsapi.org/v2/top-headlines")!
        urlComponents.queryItems = [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "pageSize", value: String(limit)),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]

        if let category = category {
            urlComponents.queryItems?.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        var request = URLRequest(url: urlComponents.url!)
        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseNewsResponse(data)
    }

    func searchNews(
        query: String,
        sortBy: NewsSortBy = .relevancy,
        language: String = "en",
        limit: Int = 20
    ) async throws -> [NewsArticle] {
        guard let apiKey = newsApiKey else {
            throw NewsServiceError.notConfigured
        }

        let url = URL(string: "https://newsapi.org/v2/everything")!
            .appending(queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "sortBy", value: sortBy.rawValue),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "pageSize", value: String(limit)),
                URLQueryItem(name: "apiKey", value: apiKey)
            ])

        var request = URLRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseNewsResponse(data)
    }

    func getPersonalizedFeed(limit: Int = 30) async throws -> [NewsArticle] {
        var allArticles: [NewsArticle] = []

        // Get articles for followed topics
        for topic in followedTopics {
            let articles = try await searchNews(query: topic, limit: 10)
            allArticles.append(contentsOf: articles)
        }

        // Get articles from followed sources
        for source in followedSources {
            let articles = try await getFromSource(source, limit: 10)
            allArticles.append(contentsOf: articles)
        }

        // Filter out blocked sources and read articles
        let filtered = allArticles.filter { article in
            !blockedSources.contains(article.source) &&
            !readArticles.contains(article.id.uuidString)
        }

        // Remove duplicates and sort by date
        let unique = Array(Set(filtered))
            .sorted { $0.publishedAt > $1.publishedAt }

        return Array(unique.prefix(limit))
    }

    func getFromSource(_ source: String, limit: Int = 20) async throws -> [NewsArticle] {
        guard let apiKey = newsApiKey else {
            throw NewsServiceError.notConfigured
        }

        let url = URL(string: "https://newsapi.org/v2/everything")!
            .appending(queryItems: [
                URLQueryItem(name: "sources", value: source),
                URLQueryItem(name: "pageSize", value: String(limit)),
                URLQueryItem(name: "apiKey", value: apiKey)
            ])

        var request = URLRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseNewsResponse(data)
    }

    func getTrendingTopics() async throws -> [NewsTopic] {
        // Get headlines and extract topics
        let headlines = try await getTopHeadlines(limit: 50)

        var topicCounts: [String: Int] = [:]

        for article in headlines {
            for keyword in extractKeywords(from: article.title) {
                topicCounts[keyword, default: 0] += 1
            }
        }

        let topics = topicCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .enumerated()
            .map { index, pair in
                NewsTopic(
                    name: pair.key,
                    articleCount: pair.value,
                    isFollowed: followedTopics.contains(pair.key)
                )
            }

        topicsCache = topics
        return topics
    }

    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction - would use NLP in production
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "is", "are", "was", "were"])

        return text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0.lowercased()) }
            .map { $0.lowercased() }
    }

    // MARK: - Sources

    func getAvailableSources(category: NewsCategory? = nil) async throws -> [NewsSource] {
        guard let apiKey = newsApiKey else {
            throw NewsServiceError.notConfigured
        }

        var urlComponents = URLComponents(string: "https://newsapi.org/v2/sources")!
        urlComponents.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]

        if let category = category {
            urlComponents.queryItems?.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        var request = URLRequest(url: urlComponents.url!)
        let (data, _) = try await URLSession.shared.data(for: request)

        return try parseSourcesResponse(data)
    }

    // MARK: - Read/Save Articles

    func markAsRead(_ article: NewsArticle) async {
        readArticles.insert(article.id.uuidString)
    }

    func saveArticle(_ article: NewsArticle) async {
        if !savedArticles.contains(where: { $0.id == article.id }) {
            savedArticles.append(article)
        }
    }

    func unsaveArticle(_ article: NewsArticle) async {
        savedArticles.removeAll { $0.id == article.id }
    }

    func getSavedArticles() async -> [NewsArticle] {
        savedArticles
    }

    func isArticleSaved(_ article: NewsArticle) async -> Bool {
        savedArticles.contains { $0.id == article.id }
    }

    // MARK: - Topic Management

    func followTopic(_ topic: String) async {
        followedTopics.insert(topic)
    }

    func unfollowTopic(_ topic: String) async {
        followedTopics.remove(topic)
    }

    func getFollowedTopics() async -> [String] {
        Array(followedTopics)
    }

    // MARK: - Source Management

    func followSource(_ source: String) async {
        followedSources.insert(source)
        blockedSources.remove(source)
    }

    func unfollowSource(_ source: String) async {
        followedSources.remove(source)
    }

    func blockSource(_ source: String) async {
        blockedSources.insert(source)
        followedSources.remove(source)
    }

    func unblockSource(_ source: String) async {
        blockedSources.remove(source)
    }

    // MARK: - Brief Generation

    func generateNewsBrief(maxArticles: Int = 5) async throws -> NewsBrief {
        let headlines = try await getTopHeadlines(limit: maxArticles)

        let summaries = headlines.prefix(maxArticles).map { article in
            "\(article.source): \(article.title)"
        }

        return NewsBrief(
            date: Date(),
            articleCount: headlines.count,
            summaries: Array(summaries),
            categories: categorizeArticles(headlines)
        )
    }

    func getVoiceBriefing() async throws -> String {
        let brief = try await generateNewsBrief()

        var script = "Here's your news briefing for \(formatDate(brief.date)). "
        script += "I have \(brief.articleCount) top stories for you. "

        for (index, summary) in brief.summaries.prefix(3).enumerated() {
            script += "Story \(index + 1): \(summary). "
        }

        return script
    }

    private func categorizeArticles(_ articles: [NewsArticle]) -> [NewsCategory: Int] {
        var counts: [NewsCategory: Int] = [:]

        for article in articles {
            if let category = article.category {
                counts[category, default: 0] += 1
            }
        }

        return counts
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Parsing

    private func parseNewsResponse(_ data: Data) throws -> [NewsArticle] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let articles = json["articles"] as? [[String: Any]] else {
            throw NewsServiceError.parseError
        }

        let formatter = ISO8601DateFormatter()

        return articles.compactMap { article -> NewsArticle? in
            guard let title = article["title"] as? String,
                  let source = article["source"] as? [String: Any],
                  let sourceName = source["name"] as? String else {
                return nil
            }

            let publishedStr = article["publishedAt"] as? String ?? ""
            let publishedAt = formatter.date(from: publishedStr) ?? Date()

            return NewsArticle(
                title: title,
                description: article["description"] as? String,
                content: article["content"] as? String,
                url: article["url"] as? String ?? "",
                imageUrl: article["urlToImage"] as? String,
                source: sourceName,
                sourceId: source["id"] as? String,
                author: article["author"] as? String,
                publishedAt: publishedAt
            )
        }
    }

    private func parseSourcesResponse(_ data: Data) throws -> [NewsSource] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = json["sources"] as? [[String: Any]] else {
            throw NewsServiceError.parseError
        }

        return sources.compactMap { source -> NewsSource? in
            guard let id = source["id"] as? String,
                  let name = source["name"] as? String else {
                return nil
            }

            let categoryStr = source["category"] as? String ?? ""
            let category = NewsCategory(rawValue: categoryStr)

            return NewsSource(
                id: id,
                name: name,
                description: source["description"] as? String,
                url: source["url"] as? String,
                category: category,
                language: source["language"] as? String,
                country: source["country"] as? String,
                isFollowed: followedSources.contains(id),
                isBlocked: blockedSources.contains(id)
            )
        }
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ command: String) async throws -> String {
        let lower = command.lowercased()

        if lower.contains("headlines") || lower.contains("top news") || lower.contains("what's happening") {
            let headlines = try await getTopHeadlines(limit: 5)
            if headlines.isEmpty {
                return "No headlines available at the moment."
            }

            var response = "Here are the top headlines: "
            for (index, article) in headlines.prefix(3).enumerated() {
                response += "\(index + 1). \(article.title). "
            }
            return response
        }

        if lower.contains("news about") {
            let queryStart = lower.range(of: "news about")!.upperBound
            let query = String(command[queryStart...]).trimmingCharacters(in: .whitespaces)

            let articles = try await searchNews(query: query, limit: 5)
            if articles.isEmpty {
                return "No news found about \(query)."
            }

            var response = "Here's what I found about \(query): "
            for article in articles.prefix(2) {
                response += "\(article.source) reports: \(article.title). "
            }
            return response
        }

        if lower.contains("briefing") || lower.contains("brief me") {
            return try await getVoiceBriefing()
        }

        throw NewsServiceError.unknownCommand
    }
}

// MARK: - Models

struct NewsArticle: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String?
    var content: String?
    var url: String
    var imageUrl: String?
    var source: String
    var sourceId: String?
    var author: String?
    var publishedAt: Date
    var category: NewsCategory?

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        content: String? = nil,
        url: String,
        imageUrl: String? = nil,
        source: String,
        sourceId: String? = nil,
        author: String? = nil,
        publishedAt: Date = Date(),
        category: NewsCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.content = content
        self.url = url
        self.imageUrl = imageUrl
        self.source = source
        self.sourceId = sourceId
        self.author = author
        self.publishedAt = publishedAt
        self.category = category
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: publishedAt, relativeTo: Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: NewsArticle, rhs: NewsArticle) -> Bool {
        lhs.url == rhs.url
    }
}

struct NewsSource: Identifiable, Codable {
    let id: String
    var name: String
    var description: String?
    var url: String?
    var category: NewsCategory?
    var language: String?
    var country: String?
    var isFollowed: Bool
    var isBlocked: Bool
}

struct NewsTopic: Identifiable {
    let id: UUID = UUID()
    var name: String
    var articleCount: Int
    var isFollowed: Bool
}

struct NewsBrief {
    let date: Date
    let articleCount: Int
    let summaries: [String]
    let categories: [NewsCategory: Int]
}

enum NewsCategory: String, Codable, CaseIterable {
    case business
    case entertainment
    case general
    case health
    case science
    case sports
    case technology

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .business: return "briefcase"
        case .entertainment: return "film"
        case .general: return "newspaper"
        case .health: return "heart"
        case .science: return "atom"
        case .sports: return "sportscourt"
        case .technology: return "desktopcomputer"
        }
    }
}

enum NewsSortBy: String {
    case relevancy
    case popularity
    case publishedAt
}

// MARK: - Errors

enum NewsServiceError: Error, LocalizedError {
    case notConfigured
    case parseError
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "News service not configured"
        case .parseError: return "Failed to parse news response"
        case .unknownCommand: return "Unknown news command"
        }
    }
}
