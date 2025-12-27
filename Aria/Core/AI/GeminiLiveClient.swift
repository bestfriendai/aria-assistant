import Foundation
import Starscream
import AVFoundation

/// Real-time bidirectional voice client for Gemini Live API
/// Uses Gemini 3 Flash Preview for native audio processing
actor GeminiLiveClient {
    // MARK: - Configuration

    private let model = "gemini-3.0-flash-preview"
    private let apiKey: String
    private let baseURL = "wss://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - State

    private var socket: WebSocket?
    private var isConnected = false
    private var sessionId: String?

    // MARK: - Callbacks

    private var onTranscript: ((String) -> Void)?
    private var onResponse: ((ResponseChunk) -> Void)?
    private var onAudio: ((Data) -> Void)?
    private var onError: ((Error) -> Void)?
    private var onConnectionChange: ((Bool) -> Void)?

    // MARK: - System Prompt

    private let systemPrompt = """
    You are Aria, a personal AI assistant. You are helpful, concise, and proactive.

    Key behaviors:
    - Respond conversationally but efficiently
    - When asked about tasks, emails, calendar, or finances, use the provided context
    - Suggest actions when appropriate ("Would you like me to...")
    - If you can complete a task autonomously, offer to do so
    - Keep responses brief for voice - expand only when asked

    Available capabilities:
    - Email: Read, search, reply, compose
    - Calendar: View events, create/modify/delete appointments
    - Tasks: Create, complete, prioritize
    - Contacts: Look up, call, text
    - Banking: Check balances, view transactions, track spending
    - Shopping: Add to cart, reorder, track deliveries

    Always prioritize user safety and privacy. Never share sensitive information.
    """

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Connection Management

    func connect() async throws {
        guard !isConnected else { return }

        let urlString = "\(baseURL)/\(model):streamGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        socket = WebSocket(request: request)
        socket?.delegate = WebSocketHandler(client: self)
        socket?.connect()

        // Wait for connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                for _ in 0..<30 { // 3 second timeout
                    if isConnected {
                        continuation.resume()
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
                continuation.resume(throwing: GeminiError.connectionTimeout)
            }
        }

        // Send system prompt
        try await sendSetup()
    }

    func disconnect() {
        socket?.disconnect()
        isConnected = false
        sessionId = nil
    }

    // MARK: - Session Setup

    private func sendSetup() async throws {
        let setup = GeminiSetupMessage(
            setup: .init(
                model: "models/\(model)",
                generationConfig: .init(
                    responseModalities: ["AUDIO", "TEXT"],
                    speechConfig: .init(
                        voiceConfig: .init(
                            prebuiltVoiceConfig: .init(voiceName: "Aria")
                        )
                    )
                ),
                systemInstruction: .init(
                    parts: [.init(text: systemPrompt)]
                )
            )
        )

        try await send(setup)
    }

    // MARK: - Audio Streaming

    func streamAudio(_ audioData: Data) async throws {
        guard isConnected else {
            throw GeminiError.notConnected
        }

        let message = GeminiRealtimeInput(
            realtimeInput: .init(
                mediaChunks: [
                    .init(
                        mimeType: "audio/pcm",
                        data: audioData.base64EncodedString()
                    )
                ]
            )
        )

        try await send(message)
    }

    func endAudioStream() async throws {
        let message = GeminiClientContent(
            clientContent: .init(turnComplete: true)
        )
        try await send(message)
    }

    // MARK: - Text Input

    func sendText(_ text: String) async throws {
        guard isConnected else {
            throw GeminiError.notConnected
        }

        let message = GeminiClientContent(
            clientContent: .init(
                turns: [
                    .init(role: "user", parts: [.init(text: text)])
                ],
                turnComplete: true
            )
        )

        try await send(message)
    }

    // MARK: - Context Injection

    func injectContext(_ context: String) async throws {
        // Send context as a tool response or system message
        let message = GeminiToolResponse(
            toolResponse: .init(
                functionResponses: [
                    .init(
                        id: "context_\(UUID().uuidString)",
                        name: "context_update",
                        response: ["context": context]
                    )
                ]
            )
        )

        try await send(message)
    }

    // MARK: - Callbacks

    func setCallbacks(
        onTranscript: @escaping (String) -> Void,
        onResponse: @escaping (ResponseChunk) -> Void,
        onAudio: @escaping (Data) -> Void,
        onError: @escaping (Error) -> Void,
        onConnectionChange: @escaping (Bool) -> Void
    ) {
        self.onTranscript = onTranscript
        self.onResponse = onResponse
        self.onAudio = onAudio
        self.onError = onError
        self.onConnectionChange = onConnectionChange
    }

    // MARK: - Internal Methods

    private func send<T: Encodable>(_ message: T) async throws {
        let data = try JSONEncoder().encode(message)
        socket?.write(data: data)
    }

    fileprivate func handleMessage(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)

            if let serverContent = response.serverContent {
                // Handle text response
                if let text = serverContent.modelTurn?.parts?.first?.text {
                    onResponse?(ResponseChunk(type: .text, content: text))
                }

                // Handle audio response
                if let audioData = serverContent.modelTurn?.parts?.first?.inlineData?.data,
                   let audio = Data(base64Encoded: audioData) {
                    onAudio?(audio)
                    onResponse?(ResponseChunk(type: .audio, content: nil, audioData: audio))
                }

                // Handle turn completion
                if serverContent.turnComplete == true {
                    onResponse?(ResponseChunk(type: .turnComplete, content: nil))
                }
            }

            // Handle transcription
            if let transcript = response.serverContent?.inputTranscript {
                onTranscript?(transcript)
            }

            // Handle tool calls
            if let toolCall = response.toolCall {
                onResponse?(ResponseChunk(
                    type: .toolCall,
                    content: nil,
                    toolCall: toolCall
                ))
            }

        } catch {
            onError?(error)
        }
    }

    fileprivate func handleConnect() {
        isConnected = true
        onConnectionChange?(true)
    }

    fileprivate func handleDisconnect(_ error: Error?) {
        isConnected = false
        onConnectionChange?(false)
        if let error = error {
            onError?(error)
        }
    }
}

// MARK: - WebSocket Handler

private class WebSocketHandler: WebSocketDelegate {
    private let client: GeminiLiveClient

    init(client: GeminiLiveClient) {
        self.client = client
    }

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        Task {
            switch event {
            case .connected:
                await self.client.handleConnect()

            case .disconnected(let reason, let code):
                await self.client.handleDisconnect(
                    GeminiError.disconnected(reason: reason, code: code)
                )

            case .binary(let data):
                await self.client.handleMessage(data)

            case .text(let string):
                if let data = string.data(using: .utf8) {
                    await self.client.handleMessage(data)
                }

            case .error(let error):
                await self.client.handleDisconnect(error)

            case .cancelled:
                await self.client.handleDisconnect(nil)

            default:
                break
            }
        }
    }
}

// MARK: - Response Types

struct ResponseChunk {
    enum ChunkType {
        case text
        case audio
        case toolCall
        case turnComplete
        case error
    }

    let type: ChunkType
    let content: String?
    var audioData: Data?
    var toolCall: GeminiToolCall?
}

// MARK: - Request Messages

struct GeminiSetupMessage: Encodable {
    let setup: Setup

    struct Setup: Encodable {
        let model: String
        let generationConfig: GenerationConfig
        let systemInstruction: SystemInstruction
    }

    struct GenerationConfig: Encodable {
        let responseModalities: [String]
        let speechConfig: SpeechConfig
    }

    struct SpeechConfig: Encodable {
        let voiceConfig: VoiceConfig
    }

    struct VoiceConfig: Encodable {
        let prebuiltVoiceConfig: PrebuiltVoiceConfig
    }

    struct PrebuiltVoiceConfig: Encodable {
        let voiceName: String
    }

    struct SystemInstruction: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }
}

struct GeminiRealtimeInput: Encodable {
    let realtimeInput: RealtimeInput

    struct RealtimeInput: Encodable {
        let mediaChunks: [MediaChunk]
    }

    struct MediaChunk: Encodable {
        let mimeType: String
        let data: String // base64
    }
}

struct GeminiClientContent: Encodable {
    let clientContent: ClientContent

    struct ClientContent: Encodable {
        var turns: [Turn]?
        var turnComplete: Bool?
    }

    struct Turn: Encodable {
        let role: String
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }
}

struct GeminiToolResponse: Encodable {
    let toolResponse: ToolResponse

    struct ToolResponse: Encodable {
        let functionResponses: [FunctionResponse]
    }

    struct FunctionResponse: Encodable {
        let id: String
        let name: String
        let response: [String: String]
    }
}

// MARK: - Response Messages

struct GeminiResponse: Decodable {
    let serverContent: ServerContent?
    let toolCall: GeminiToolCall?

    struct ServerContent: Decodable {
        let modelTurn: ModelTurn?
        let turnComplete: Bool?
        let inputTranscript: String?
    }

    struct ModelTurn: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
        let inlineData: InlineData?
    }

    struct InlineData: Decodable {
        let mimeType: String?
        let data: String? // base64
    }
}

struct GeminiToolCall: Decodable {
    let functionCalls: [FunctionCall]?

    struct FunctionCall: Decodable {
        let id: String
        let name: String
        let args: [String: String]?
    }
}

// MARK: - Errors

enum GeminiError: Error, LocalizedError {
    case invalidURL
    case connectionTimeout
    case notConnected
    case disconnected(reason: String, code: UInt16)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Gemini API URL"
        case .connectionTimeout:
            return "Connection to Gemini timed out"
        case .notConnected:
            return "Not connected to Gemini"
        case .disconnected(let reason, let code):
            return "Disconnected: \(reason) (code: \(code))"
        case .invalidResponse:
            return "Invalid response from Gemini"
        }
    }
}
