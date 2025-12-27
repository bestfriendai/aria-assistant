import SwiftUI

@main
struct AriaApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var conversationManager = ConversationManager()
    @StateObject private var attentionEngine = AttentionEngine()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .environmentObject(conversationManager)
                .environmentObject(attentionEngine)
                .preferredColorScheme(.dark)
                .onAppear {
                    setupApp()
                }
        }
    }

    private func setupApp() {
        Task {
            // Initialize database
            try? await DatabaseManager.shared.initialize()

            // Pre-warm Gemini connection
            await conversationManager.connect()

            // Start attention engine
            await attentionEngine.start()
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var isListening = false
    @Published var isResponding = false
    @Published var isConnected = false
    @Published var isOffline = false

    enum VoiceState {
        case idle
        case listening
        case processing
        case responding
    }

    @Published var voiceState: VoiceState = .idle
}
