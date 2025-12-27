import Foundation
import Combine

/// Manages conversations with Gemini, racing local vs cloud responses
@MainActor
class ConversationManager: ObservableObject {
    // MARK: - Published State

    @Published var isConnected = false
    @Published var isProcessing = false
    @Published var currentTranscript = ""
    @Published var lastResponse = ""
    @Published var error: Error?

    // MARK: - Components

    private var geminiClient: GeminiLiveClient?
    private let localClassifier = LocalIntentClassifier()
    private var embeddingService: EmbeddingService?
    private let responseCache = ResponseCache()

    // MARK: - Audio

    private var audioPlayer: AVAudioPlayerNode?
    private var audioEngine: AVAudioEngine?

    // MARK: - Configuration

    private let apiKey: String

    // MARK: - Callbacks

    var onResponse: ((String) -> Void)?
    var onAudioResponse: ((Data) -> Void)?
    var onToolCall: ((String, [String: String]) -> Void)?

    init() {
        // Load API key from keychain or environment
        self.apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }

    // MARK: - Connection

    func connect() async {
        guard !apiKey.isEmpty else {
            error = ConversationError.missingAPIKey
            return
        }

        geminiClient = GeminiLiveClient(apiKey: apiKey)
        embeddingService = EmbeddingService(apiKey: apiKey)

        await geminiClient?.setCallbacks(
            onTranscript: { [weak self] transcript in
                Task { @MainActor in
                    self?.currentTranscript = transcript
                }
            },
            onResponse: { [weak self] chunk in
                Task { @MainActor in
                    self?.handleResponseChunk(chunk)
                }
            },
            onAudio: { [weak self] audio in
                self?.onAudioResponse?(audio)
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.error = error
                }
            },
            onConnectionChange: { [weak self] connected in
                Task { @MainActor in
                    self?.isConnected = connected
                }
            }
        )

        do {
            try await geminiClient?.connect()
            await localClassifier.preloadCommonQueries()
        } catch {
            self.error = error
        }
    }

    func disconnect() async {
        await geminiClient?.disconnect()
        isConnected = false
    }

    // MARK: - Voice Processing

    func processVoice(_ audioData: Data) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Stream audio to Gemini
            try await geminiClient?.streamAudio(audioData)
        } catch {
            self.error = error
        }
    }

    func endVoiceInput() async {
        do {
            try await geminiClient?.endAudioStream()
        } catch {
            self.error = error
        }
    }

    // MARK: - Text Processing

    func processText(_ text: String) async {
        isProcessing = true
        currentTranscript = text
        defer { isProcessing = false }

        // Race: local classification vs cloud
        async let localResult = raceLocal(text)
        async let cloudResult = raceCloud(text)

        // Use whichever responds first with high confidence
        let local = await localResult
        if local.confidence > 0.9, let cachedResponse = await responseCache.get(for: local.intent) {
            lastResponse = cachedResponse
            onResponse?(cachedResponse)
            return
        }

        // Otherwise wait for cloud
        await cloudResult
    }

    private func raceLocal(_ text: String) async -> LocalIntentClassifier.ClassificationResult {
        await localClassifier.classify(text)
    }

    private func raceCloud(_ text: String) async {
        do {
            try await geminiClient?.sendText(text)
        } catch {
            self.error = error
        }
    }

    // MARK: - Context

    func injectContext(_ context: ConversationContext) async {
        let contextString = """
        Current context:
        - Time: \(context.currentTime)
        - Location: \(context.location ?? "Unknown")
        - Upcoming events: \(context.upcomingEvents.joined(separator: ", "))
        - Recent emails: \(context.recentEmailSummary ?? "None")
        - Pending tasks: \(context.pendingTasksSummary ?? "None")
        """

        do {
            try await geminiClient?.injectContext(contextString)
        } catch {
            self.error = error
        }
    }

    // MARK: - Response Handling

    private func handleResponseChunk(_ chunk: ResponseChunk) {
        switch chunk.type {
        case .text:
            if let content = chunk.content {
                lastResponse += content
                onResponse?(content)
            }

        case .audio:
            // Audio handled by callback
            break

        case .toolCall:
            if let toolCall = chunk.toolCall,
               let functionCall = toolCall.functionCalls?.first {
                onToolCall?(functionCall.name, functionCall.args ?? [:])
            }

        case .turnComplete:
            isProcessing = false
            // Cache successful response
            Task {
                let classification = await localClassifier.classify(currentTranscript)
                if classification.confidence > 0.7 {
                    await responseCache.cache(lastResponse, for: classification.intent)
                }
            }

        case .error:
            // Error handled elsewhere
            break
        }
    }
}

// MARK: - Supporting Types

struct ConversationContext {
    let currentTime: String
    let location: String?
    let upcomingEvents: [String]
    let recentEmailSummary: String?
    let pendingTasksSummary: String?
}

enum ConversationError: Error, LocalizedError {
    case missingAPIKey
    case notConnected
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured"
        case .notConnected:
            return "Not connected to Gemini"
        case .processingFailed:
            return "Failed to process input"
        }
    }
}

// MARK: - Response Cache

actor ResponseCache {
    private var cache: [LocalIntentClassifier.Intent: String] = [:]
    private var timestamps: [LocalIntentClassifier.Intent: Date] = [:]
    private let maxAge: TimeInterval = 300 // 5 minutes

    func get(for intent: LocalIntentClassifier.Intent) -> String? {
        guard let response = cache[intent],
              let timestamp = timestamps[intent],
              Date().timeIntervalSince(timestamp) < maxAge else {
            return nil
        }
        return response
    }

    func cache(_ response: String, for intent: LocalIntentClassifier.Intent) {
        cache[intent] = response
        timestamps[intent] = Date()
    }

    func invalidate(_ intent: LocalIntentClassifier.Intent) {
        cache.removeValue(forKey: intent)
        timestamps.removeValue(forKey: intent)
    }

    func invalidateAll() {
        cache.removeAll()
        timestamps.removeAll()
    }
}

// MARK: - Audio Import

import AVFoundation
