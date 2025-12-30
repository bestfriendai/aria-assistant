import SwiftUI

/// Main view with idle state and attention items
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var attentionEngine: AttentionEngine

    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showQuickTip = true
    @State private var isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @AppStorage("hasSeenVoiceTip") private var hasSeenVoiceTip = false

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with status and time
                topBar

                Spacer()

                // Attention items or empty state
                attentionSection

                Spacer()

                // Central orb
                VoiceOrbView()
                    .frame(height: 200)

                // Transcript/response area
                if !conversationManager.currentTranscript.isEmpty ||
                   !conversationManager.lastResponse.isEmpty {
                    TranscriptView()
                        .padding(.horizontal, AriaSpacing.xxl)
                        .padding(.top, AriaSpacing.lg)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }

                Spacer()

                // Bottom bar
                bottomBar
            }

            // Quick tip overlay for first-time users
            if showQuickTip && !hasSeenVoiceTip && !isFirstLaunch {
                VStack {
                    Spacer()
                    QuickTipView(
                        tip: QuickTip(
                            icon: "hand.tap.fill",
                            title: "Tap the orb to speak",
                            message: "Just tap and say \"Aria\" followed by your request.",
                            showDontShowAgain: true,
                            onDontShowAgain: {
                                hasSeenVoiceTip = true
                            }
                        ),
                        isPresented: $showQuickTip
                    )
                    .padding(.horizontal, AriaSpacing.screenHorizontal)
                    .padding(.bottom, 180)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                }
                .animation(AriaAnimation.springStandard, value: showQuickTip)
            }

            // Offline banner
            if appState.isOffline {
                VStack {
                    OfflineBanner {
                        Task {
                            await conversationManager.connect()
                        }
                    }
                    .padding(.horizontal, AriaSpacing.screenHorizontal)
                    .padding(.top, AriaSpacing.xl)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(AriaAnimation.springStandard, value: appState.isOffline)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistoryView()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Connection status
            ConnectionStatusView()
                .padding(.leading, AriaSpacing.xs)

            Spacer()

            // Time display
            Text(timeString)
                .font(AriaTypography.labelMedium)
                .foregroundColor(.ariaTextTertiary)
                .accessibilityLabel("Current time: \(timeString)")
        }
        .padding(.horizontal, AriaSpacing.screenHorizontal)
        .padding(.top, AriaSpacing.xs)
        .frame(height: 44)
    }

    // MARK: - Attention Section

    @ViewBuilder
    private var attentionSection: some View {
        if attentionEngine.isLoading {
            // Loading state
            VStack(spacing: AriaSpacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonAttentionCard()
                }
            }
            .padding(.horizontal, AriaSpacing.screenHorizontal)
            .transition(.opacity)
        } else if attentionEngine.items.isEmpty {
            // Empty state
            EmptyAttentionView()
                .transition(.opacity)
        } else {
            // Attention items
            AttentionItemsView()
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // History button
            Button {
                HapticFeedback.shared.selection()
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20))
                    .foregroundColor(.ariaTextTertiary)
                    .frame(width: 44, height: 44)
            }
            .ariaAccessibility(
                label: "Conversation history",
                hint: AriaAccessibility.buttonHint
            )

            Spacer()

            // Settings button
            Button {
                HapticFeedback.shared.selection()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(.ariaTextTertiary)
                    .frame(width: 44, height: 44)
            }
            .ariaAccessibility(
                label: AriaAccessibility.settingsLabel,
                hint: AriaAccessibility.settingsHint
            )
        }
        .padding(.horizontal, AriaSpacing.screenHorizontal)
        .padding(.bottom, AriaSpacing.md)
    }

    // MARK: - Helpers

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: Date())
    }
}

// MARK: - Voice Orb View

/// Voice orb with animations and accessibility
struct VoiceOrbView: View {
    @EnvironmentObject var appState: AppState
    @State private var animationPhase: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Outer pulsing rings (when listening)
            if appState.voiceState == .listening {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.ariaListening.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                        .frame(width: CGFloat(100 + index * 30), height: CGFloat(100 + index * 30))
                        .scaleEffect(pulseScale + CGFloat(index) * 0.1)
                }
            }

            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(appState.voiceState == .listening ? 1.2 : 1.0)
                .animation(AriaAnimation.breathe, value: appState.voiceState)

            // Main orb
            Circle()
                .fill(orbGradient)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: orbColor.opacity(0.6), radius: orbShadowRadius, x: 0, y: 0)
                .scaleEffect(orbScale * (isPressed ? 0.95 : 1.0))
                .animation(AriaAnimation.springQuick, value: isPressed)

            // Center icon (when processing)
            if appState.voiceState == .processing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }

            // Waveform (when listening/responding)
            if appState.voiceState == .listening || appState.voiceState == .responding {
                WaveformView(isResponding: appState.voiceState == .responding)
                    .frame(width: 120, height: 40)
                    .offset(y: 65)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // State label
            Text(stateLabel)
                .font(AriaTypography.labelMedium)
                .foregroundColor(.ariaTextTertiary)
                .offset(y: appState.voiceState == .idle ? 55 : 105)
                .animation(AriaAnimation.springStandard, value: appState.voiceState)
        }
        .contentShape(Circle().size(width: 120, height: 120))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    handleTap()
                }
        )
        .ariaAccessibility(
            label: AriaAccessibility.voiceOrbLabel,
            hint: voiceOrbHint,
            traits: .isButton
        )
        .onAppear {
            startAnimations()
        }
        .onChange(of: appState.voiceState) { oldState, newState in
            // Provide haptic feedback on state changes
            switch newState {
            case .listening:
                HapticFeedback.shared.listeningStarted()
            case .processing:
                HapticFeedback.shared.processing()
            case .responding:
                HapticFeedback.shared.responseStarted()
            case .idle:
                if oldState == .responding {
                    HapticFeedback.shared.success()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var orbColor: Color {
        switch appState.voiceState {
        case .idle: return .ariaIdle
        case .listening: return .ariaListening
        case .processing: return .ariaProcessing
        case .responding: return .ariaResponding
        }
    }

    private var orbGradient: LinearGradient {
        LinearGradient(
            colors: [orbColor, orbColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var orbScale: Double {
        switch appState.voiceState {
        case .idle: return 1.0
        case .listening: return 1.0 + sin(animationPhase * 2) * 0.05
        case .processing: return 0.95 + sin(animationPhase * 4) * 0.02
        case .responding: return 1.05 + sin(animationPhase * 3) * 0.03
        }
    }

    private var orbShadowRadius: CGFloat {
        switch appState.voiceState {
        case .idle: return 15
        case .listening: return 25
        case .processing: return 20
        case .responding: return 30
        }
    }

    private var stateLabel: String {
        switch appState.voiceState {
        case .idle: return "Say \"Aria...\""
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .responding: return "Speaking..."
        }
    }

    private var voiceOrbHint: String {
        switch appState.voiceState {
        case .idle: return AriaAccessibility.voiceOrbIdleHint
        case .listening: return AriaAccessibility.voiceOrbListeningHint
        case .processing: return AriaAccessibility.voiceOrbProcessingHint
        case .responding: return AriaAccessibility.voiceOrbRespondingHint
        }
    }

    // MARK: - Methods

    private func startAnimations() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            animationPhase = .pi * 2
        }

        withAnimation(AriaAnimation.breathe) {
            pulseScale = 1.15
        }
    }

    private func handleTap() {
        if appState.voiceState == .idle {
            appState.voiceState = .listening
        } else if appState.voiceState == .listening || appState.voiceState == .responding {
            appState.voiceState = .idle
        }
    }
}

// MARK: - Waveform View

/// Waveform visualization with improved animations
struct WaveformView: View {
    let isResponding: Bool
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 5)
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: isResponding
                                ? [.ariaResponding, .ariaResponding.opacity(0.7)]
                                : [.ariaListening, .ariaListening.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: max(8, levels[index] * 40))
                    .animation(
                        .easeInOut(duration: 0.12).delay(Double(index) * 0.03),
                        value: levels[index]
                    )
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            levels = (0..<5).map { _ in CGFloat.random(in: 0.3...1.0) }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Transcript View

/// Transcript and response display with improved styling
struct TranscriptView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: AriaSpacing.sm) {
            // User transcript
            if !conversationManager.currentTranscript.isEmpty {
                HStack {
                    Spacer()
                    Text(conversationManager.currentTranscript)
                        .font(AriaTypography.bodyMedium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, AriaSpacing.md)
                        .padding(.vertical, AriaSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AriaRadius.lg)
                                .fill(Color.ariaAccentBlue.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AriaRadius.lg)
                                        .stroke(Color.ariaAccentBlue.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .accessibilityLabel("You said: \(conversationManager.currentTranscript)")
                }
            }

            // Assistant response
            if !conversationManager.lastResponse.isEmpty &&
               (appState.voiceState == .responding || appState.voiceState == .processing) {
                HStack {
                    Text(conversationManager.lastResponse)
                        .font(AriaTypography.bodySmall)
                        .foregroundColor(.ariaTextSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .padding(.horizontal, AriaSpacing.md)
                        .padding(.vertical, AriaSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AriaRadius.lg)
                                .fill(Color.ariaSurface)
                        )
                        .accessibilityLabel("Aria says: \(conversationManager.lastResponse)")
                    Spacer()
                }
            }
        }
        .animation(AriaAnimation.springStandard, value: conversationManager.currentTranscript)
        .animation(AriaAnimation.springStandard, value: conversationManager.lastResponse)
    }
}

// MARK: - Previews

#Preview("Main View") {
    MainView()
        .environmentObject(AppState())
        .environmentObject(ConversationManager())
        .environmentObject(AttentionEngine())
}

#Preview("Main View - Listening") {
    let appState = AppState()
    appState.voiceState = .listening

    return MainView()
        .environmentObject(appState)
        .environmentObject(ConversationManager())
        .environmentObject(AttentionEngine())
}

#Preview("Voice Orb States") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 60) {
            // Idle
            let idleState = AppState()
            VoiceOrbView()
                .environmentObject(idleState)

            // Listening
            let listeningState = AppState()
            let _ = { listeningState.voiceState = .listening }()
            VoiceOrbView()
                .environmentObject(listeningState)
        }
    }
}
