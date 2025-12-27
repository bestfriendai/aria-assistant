import Foundation

/// Unified email service supporting Gmail, Outlook, and iCloud
actor EmailService {
    // MARK: - Providers

    private var providers: [EmailProvider: EmailProviderClient] = [:]
    private let database = DatabaseManager.shared
    private var embeddingService: EmbeddingService?

    // MARK: - Configuration

    func configure(apiKey: String) {
        embeddingService = EmbeddingService(apiKey: apiKey)
    }

    // MARK: - Provider Management

    func addProvider(_ provider: EmailProvider, credentials: OAuthCredentials) async throws {
        let client: EmailProviderClient

        switch provider {
        case .gmail:
            client = GmailClient(credentials: credentials)
        case .outlook:
            client = OutlookClient(credentials: credentials)
        case .icloud:
            client = ICloudMailClient(credentials: credentials)
        case .other:
            throw EmailServiceError.unsupportedProvider
        }

        providers[provider] = client
        try await client.authenticate()
    }

    func removeProvider(_ provider: EmailProvider) async {
        providers.removeValue(forKey: provider)
    }

    // MARK: - Email Operations

    func fetchEmails(
        provider: EmailProvider? = nil,
        folder: String = "INBOX",
        limit: Int = 50,
        since: Date? = nil
    ) async throws -> [Email] {
        var allEmails: [Email] = []

        let targetProviders = provider.map { [$0] } ?? Array(providers.keys)

        for p in targetProviders {
            guard let client = providers[p] else { continue }

            let emails = try await client.fetchEmails(
                folder: folder,
                limit: limit,
                since: since
            )

            allEmails.append(contentsOf: emails)
        }

        // Sort by received date
        allEmails.sort { $0.receivedAt > $1.receivedAt }

        // Generate embeddings for new emails
        await generateEmbeddings(for: allEmails)

        return allEmails
    }

    func searchEmails(query: String, limit: Int = 20) async throws -> [Email] {
        // First, try semantic search with embeddings
        guard let embeddingService = embeddingService else {
            return try await keywordSearch(query: query, limit: limit)
        }

        let queryEmbedding = try await embeddingService.embed(query)

        // Load emails with embeddings from database
        let emails = try await loadEmailsWithEmbeddings()

        // Perform vector search
        let vectorSearch = VectorSearch.shared
        let results = await vectorSearch.knnSearch(
            query: queryEmbedding,
            items: emails.compactMap { email -> (Email, [Float])? in
                guard let embedding = email.embedding else { return nil }
                return (email, embedding)
            },
            k: limit,
            threshold: 0.6
        )

        return results.map { $0.item }
    }

    private func keywordSearch(query: String, limit: Int) async throws -> [Email] {
        // Fallback keyword search
        let allEmails = try await fetchEmails(limit: 100)

        let queryTerms = Set(query.lowercased().split(separator: " ").map { String($0) })

        return allEmails
            .filter { email in
                let text = "\(email.subject) \(email.snippet)".lowercased()
                return queryTerms.contains { text.contains($0) }
            }
            .prefix(limit)
            .map { $0 }
    }

    func markAsRead(_ emailId: UUID) async throws {
        // Find provider and mark as read
    }

    func archive(_ emailId: UUID) async throws {
        // Find provider and archive
    }

    func sendEmail(
        to: [String],
        cc: [String] = [],
        subject: String,
        body: String,
        provider: EmailProvider
    ) async throws {
        guard let client = providers[provider] else {
            throw EmailServiceError.providerNotConfigured
        }

        try await client.sendEmail(to: to, cc: cc, subject: subject, body: body)
    }

    func replyToEmail(_ emailId: UUID, body: String) async throws {
        // Find email, compose reply, send
    }

    // MARK: - Intelligence

    func analyzeEmail(_ email: Email) async throws -> EmailAnalysis {
        // Extract action items, deadlines, sentiment
        return EmailAnalysis(
            actions: [],
            deadlines: [],
            sentiment: .neutral,
            requiresResponse: false,
            suggestedReplies: []
        )
    }

    func getUrgentEmails(limit: Int = 5) async throws -> [Email] {
        let emails = try await fetchEmails(limit: 50)

        return emails
            .filter { $0.priorityScore >= 70 && !$0.isRead }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Embeddings

    private func generateEmbeddings(for emails: [Email]) async {
        guard let embeddingService = embeddingService else { return }

        for email in emails where email.embedding == nil {
            do {
                let embedding = try await embeddingService.embedEmail(
                    subject: email.subject,
                    body: email.body ?? email.snippet,
                    from: email.from.displayName
                )

                // Store embedding in database
                // ...
            } catch {
                // Log error, continue
            }
        }
    }

    private func loadEmailsWithEmbeddings() async throws -> [Email] {
        // Load from database
        return []
    }
}

// MARK: - Provider Protocol

protocol EmailProviderClient {
    func authenticate() async throws
    func fetchEmails(folder: String, limit: Int, since: Date?) async throws -> [Email]
    func sendEmail(to: [String], cc: [String], subject: String, body: String) async throws
    func markAsRead(_ messageId: String) async throws
    func archive(_ messageId: String) async throws
}

// MARK: - Gmail Client

class GmailClient: EmailProviderClient {
    private let credentials: OAuthCredentials
    private var accessToken: String?

    init(credentials: OAuthCredentials) {
        self.credentials = credentials
    }

    func authenticate() async throws {
        // OAuth flow
        accessToken = credentials.accessToken
    }

    func fetchEmails(folder: String, limit: Int, since: Date?) async throws -> [Email] {
        // Gmail API call
        return []
    }

    func sendEmail(to: [String], cc: [String], subject: String, body: String) async throws {
        // Gmail API call
    }

    func markAsRead(_ messageId: String) async throws {
        // Gmail API call
    }

    func archive(_ messageId: String) async throws {
        // Gmail API call
    }
}

// MARK: - Outlook Client

class OutlookClient: EmailProviderClient {
    private let credentials: OAuthCredentials

    init(credentials: OAuthCredentials) {
        self.credentials = credentials
    }

    func authenticate() async throws {
        // OAuth flow
    }

    func fetchEmails(folder: String, limit: Int, since: Date?) async throws -> [Email] {
        return []
    }

    func sendEmail(to: [String], cc: [String], subject: String, body: String) async throws {}
    func markAsRead(_ messageId: String) async throws {}
    func archive(_ messageId: String) async throws {}
}

// MARK: - iCloud Client

class ICloudMailClient: EmailProviderClient {
    private let credentials: OAuthCredentials

    init(credentials: OAuthCredentials) {
        self.credentials = credentials
    }

    func authenticate() async throws {}
    func fetchEmails(folder: String, limit: Int, since: Date?) async throws -> [Email] { [] }
    func sendEmail(to: [String], cc: [String], subject: String, body: String) async throws {}
    func markAsRead(_ messageId: String) async throws {}
    func archive(_ messageId: String) async throws {}
}

// MARK: - Supporting Types

struct OAuthCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

struct EmailAnalysis {
    let actions: [ExtractedAction]
    let deadlines: [Date]
    let sentiment: Sentiment
    let requiresResponse: Bool
    let suggestedReplies: [String]
}

enum EmailServiceError: Error {
    case unsupportedProvider
    case providerNotConfigured
    case authenticationFailed
    case sendFailed
}
