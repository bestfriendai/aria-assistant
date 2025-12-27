import Foundation
import Accelerate

/// Vector search implementation for semantic queries
/// Uses sqlite-vec style operations with SIMD-optimized similarity
actor VectorSearch {
    static let shared = VectorSearch()

    private let dimension = 768 // Gemini embedding dimension

    private init() {}

    // MARK: - Similarity Functions

    /// Compute cosine similarity between two vectors
    /// Uses Accelerate framework for SIMD optimization
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// Compute L2 (Euclidean) distance between two vectors
    func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }

        var diff = [Float](repeating: 0, count: a.count)
        var result: Float = 0

        vDSP_vsub(b, 1, a, 1, &diff, 1, vDSP_Length(a.count))
        vDSP_svesq(diff, 1, &result, vDSP_Length(diff.count))

        return sqrt(result)
    }

    // MARK: - K-NN Search

    struct SearchResult<T> {
        let item: T
        let similarity: Float
    }

    /// Find k nearest neighbors using cosine similarity
    func knnSearch<T>(
        query: [Float],
        items: [(T, [Float])],
        k: Int = 10,
        threshold: Float = 0.7
    ) -> [SearchResult<T>] {
        let results = items.compactMap { (item, embedding) -> SearchResult<T>? in
            let similarity = cosineSimilarity(query, embedding)
            guard similarity >= threshold else { return nil }
            return SearchResult(item: item, similarity: similarity)
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(k)
            .map { $0 }
    }

    /// Hybrid search combining vector similarity with keyword matching
    func hybridSearch<T>(
        query: [Float],
        queryText: String,
        items: [(T, [Float], String)], // item, embedding, text
        k: Int = 10,
        vectorWeight: Float = 0.7,
        keywordWeight: Float = 0.3
    ) -> [SearchResult<T>] {
        let queryTerms = Set(queryText.lowercased().split(separator: " ").map { String($0) })

        let results = items.map { (item, embedding, text) -> SearchResult<T> in
            // Vector similarity score
            let vectorScore = cosineSimilarity(query, embedding)

            // Keyword matching score
            let textTerms = Set(text.lowercased().split(separator: " ").map { String($0) })
            let matchCount = queryTerms.intersection(textTerms).count
            let keywordScore = Float(matchCount) / Float(max(1, queryTerms.count))

            // Combined score
            let combinedScore = vectorScore * vectorWeight + keywordScore * keywordWeight

            return SearchResult(item: item, similarity: combinedScore)
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(k)
            .map { $0 }
    }

    // MARK: - Embedding Serialization

    /// Convert embedding to Data for storage
    func embedingToData(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Convert Data to embedding
    func dataToEmbedding(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    // MARK: - Batch Operations

    /// Compute similarities for multiple queries in batch
    func batchSimilarity(
        queries: [[Float]],
        embeddings: [[Float]]
    ) -> [[Float]] {
        queries.map { query in
            embeddings.map { embedding in
                cosineSimilarity(query, embedding)
            }
        }
    }
}

// MARK: - Embedding Cache

actor EmbeddingCache {
    private var cache: [String: [Float]] = [:]
    private let maxSize = 1000

    func get(key: String) -> [Float]? {
        cache[key]
    }

    func set(key: String, embedding: [Float]) {
        if cache.count >= maxSize {
            // Simple LRU: remove random entries
            let keysToRemove = Array(cache.keys.prefix(100))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        cache[key] = embedding
    }

    func clear() {
        cache.removeAll()
    }
}
