import SwiftUI

@main
struct AriaApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var conversationManager = ConversationManager()
    @StateObject private var attentionEngine = AttentionEngine()

    @State private var showOnboarding = false
    @State private var isInitialized = false
    @State private var initializationError: AppInitializationError?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !isInitialized {
                    // Splash/Loading screen
                    SplashView(error: initializationError) {
                        Task {
                            await retryInitialization()
                        }
                    }
                } else {
                    // Main app with toast container
                    ToastContainer {
                        MainView()
                            .environmentObject(appState)
                            .environmentObject(conversationManager)
                            .environmentObject(attentionEngine)
                    }
                    .transition(.opacity)
                }

                // Onboarding overlay
                if showOnboarding {
                    OnboardingView(isPresented: $showOnboarding)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                checkOnboardingStatus()
                Task {
                    await setupApp()
                }
            }
        }
    }

    // MARK: - Initialization

    private func checkOnboardingStatus() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        showOnboarding = !hasCompleted
    }

    private func setupApp() async {
        do {
            // Initialize database
            try await DatabaseManager.shared.initialize()

            // Pre-warm Gemini connection
            await conversationManager.connect()

            // Start attention engine
            await attentionEngine.start()

            // Mark as initialized
            await MainActor.run {
                withAnimation(AriaAnimation.smooth) {
                    isInitialized = true
                }
            }
        } catch {
            await MainActor.run {
                initializationError = AppInitializationError(
                    title: "Failed to Initialize",
                    message: error.localizedDescription,
                    isRecoverable: true
                )
            }
        }
    }

    private func retryInitialization() async {
        initializationError = nil
        await setupApp()
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var isListening = false
    @Published var isResponding = false
    @Published var isConnected = false
    @Published var isOffline = false
    @Published var errorMessage: String?

    enum VoiceState: Equatable {
        case idle
        case listening
        case processing
        case responding
    }

    @Published var voiceState: VoiceState = .idle

    // MARK: - Error Handling

    func showError(_ message: String) {
        errorMessage = message
        ToastManager.shared.show(.error, message: message)
    }

    func showSuccess(_ message: String) {
        ToastManager.shared.show(.success, message: message)
    }

    func showInfo(_ message: String) {
        ToastManager.shared.show(.info, message: message)
    }
}

// MARK: - App Initialization Error

struct AppInitializationError {
    let title: String
    let message: String
    let isRecoverable: Bool
}

// MARK: - Splash View

struct SplashView: View {
    let error: AppInitializationError?
    let onRetry: () -> Void

    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var showProgress = false

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: AriaSpacing.xxl) {
                Spacer()

                // Logo/Icon
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color.ariaAccentBlue.opacity(0.15))
                        .frame(width: 150, height: 150)
                        .blur(radius: 30)

                    // Logo circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ariaAccentBlue, Color.ariaAccentPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 50, weight: .light))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color.ariaAccentBlue.opacity(0.5), radius: 20)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // App name
                VStack(spacing: AriaSpacing.xs) {
                    Text("Aria")
                        .font(AriaTypography.displayLarge)
                        .foregroundColor(.ariaTextPrimary)

                    Text("Your Personal Assistant")
                        .font(AriaTypography.bodyMedium)
                        .foregroundColor(.ariaTextTertiary)
                }
                .opacity(logoOpacity)

                Spacer()

                // Loading or error state
                if let error = error {
                    // Error state
                    VStack(spacing: AriaSpacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.ariaError)

                        Text(error.title)
                            .font(AriaTypography.headlineSmall)
                            .foregroundColor(.ariaTextPrimary)

                        Text(error.message)
                            .font(AriaTypography.bodySmall)
                            .foregroundColor(.ariaTextTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AriaSpacing.xxl)

                        if error.isRecoverable {
                            Button("Try Again") {
                                HapticFeedback.shared.selection()
                                onRetry()
                            }
                            .buttonStyle(AriaButtonStyle(style: .primary))
                            .padding(.top, AriaSpacing.sm)
                        }
                    }
                    .padding(.bottom, AriaSpacing.xxxl)
                } else if showProgress {
                    // Loading state
                    VStack(spacing: AriaSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .ariaAccentBlue))
                            .scaleEffect(1.2)

                        Text("Starting up...")
                            .font(AriaTypography.bodySmall)
                            .foregroundColor(.ariaTextTertiary)
                    }
                    .padding(.bottom, AriaSpacing.xxxl)
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            withAnimation(AriaAnimation.springBouncy.delay(0.2)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(AriaAnimation.smooth) {
                    showProgress = true
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Splash Screen") {
    SplashView(error: nil, onRetry: {})
}

#Preview("Splash Screen - Error") {
    SplashView(
        error: AppInitializationError(
            title: "Connection Failed",
            message: "Unable to connect to Aria's servers. Please check your internet connection and try again.",
            isRecoverable: true
        ),
        onRetry: {}
    )
}

#Preview("App") {
    MainView()
        .environmentObject(AppState())
        .environmentObject(ConversationManager())
        .environmentObject(AttentionEngine())
        .preferredColorScheme(.dark)
}
