import Foundation
import GoogleGenerativeAI

/// Service for generating text embeddings using Gemini
actor EmbeddingService {
    private let model: GenerativeModel
    private let cache = EmbeddingCache()

    init(apiKey: String) {
        self.model = GenerativeModel(
            name: "text-embedding-004",
            apiKey: apiKey
        )
    }

    // MARK: - Single Embedding

    /// Generate embedding for a single text
    func embed(_ text: String) async throws -> [Float] {
        // Check cache first
        let cacheKey = text.prefix(200).description
        if let cached = await cache.get(key: cacheKey) {
            return cached
        }

        let response = try await model.embedContent(text)

        guard let embedding = response.embedding?.values else {
            throw EmbeddingError.noEmbedding
        }

        let floatEmbedding = embedding.map { Float($0) }

        // Cache the result
        await cache.set(key: cacheKey, embedding: floatEmbedding)

        return floatEmbedding
    }

    // MARK: - Batch Embedding

    /// Generate embeddings for multiple texts in batch
    func embedBatch(_ texts: [String], batchSize: Int = 100) async throws -> [[Float]] {
        var allEmbeddings: [[Float]] = []

        for startIndex in stride(from: 0, to: texts.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, texts.count)
            let batch = Array(texts[startIndex..<endIndex])

            let batchEmbeddings = try await embedBatchInternal(batch)
            allEmbeddings.append(contentsOf: batchEmbeddings)
        }

        return allEmbeddings
    }

    private func embedBatchInternal(_ texts: [String]) async throws -> [[Float]] {
        // Process in parallel with concurrency limit
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let embedding = try await self.embed(text)
                    return (index, embedding)
                }
            }

            var results: [(Int, [Float])] = []
            for try await result in group {
                results.append(result)
            }

            return results
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }
    }

    // MARK: - Specialized Embeddings

    /// Create embedding optimized for email search
    func embedEmail(subject: String, body: String, from: String) async throws -> [Float] {
        let text = "Email from \(from): \(subject). \(body.prefix(500))"
        return try await embed(text)
    }

    /// Create embedding optimized for task search
    func embedTask(title: String, notes: String?, context: [String]) async throws -> [Float] {
        var text = "Task: \(title)"
        if let notes = notes { text += ". \(notes)" }
        if !context.isEmpty { text += ". Context: \(context.joined(separator: ", "))" }
        return try await embed(text)
    }

    /// Create embedding optimized for contact search
    func embedContact(name: String, company: String?, contexts: [String]) async throws -> [Float] {
        var text = "Contact: \(name)"
        if let company = company { text += " at \(company)" }
        if !contexts.isEmpty { text += ". \(contexts.joined(separator: ", "))" }
        return try await embed(text)
    }

    /// Create embedding for a conversation turn
    func embedConversation(role: String, content: String) async throws -> [Float] {
        let text = "\(role): \(content)"
        return try await embed(text)
    }
}

enum EmbeddingError: Error, LocalizedError {
    case noEmbedding
    case batchTooLarge
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noEmbedding:
            return "No embedding returned from API"
        case .batchTooLarge:
            return "Batch size exceeds maximum"
        case .rateLimited:
            return "Rate limited by embedding API"
        }
    }
}
