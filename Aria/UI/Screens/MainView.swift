import SwiftUI

/// Main view with idle state and attention items
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var attentionEngine: AttentionEngine

    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar area
                HStack {
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // Attention items (when present)
                if !attentionEngine.items.isEmpty {
                    AttentionItemsView()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Central orb
                VoiceOrbView()
                    .frame(height: 200)

                // Transcript/response area
                if !conversationManager.currentTranscript.isEmpty ||
                   !conversationManager.lastResponse.isEmpty {
                    TranscriptView()
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                }

                Spacer()

                // Settings button
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: Date())
    }
}

/// Voice orb with animations
struct VoiceOrbView: View {
    @EnvironmentObject var appState: AppState
    @State private var animationPhase: Double = 0

    var body: some View {
        ZStack {
            // Outer glow (when listening)
            if appState.voiceState == .listening {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(1.0 + sin(animationPhase) * 0.1)
            }

            // Main orb
            Circle()
                .fill(orbGradient)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: orbColor.opacity(0.5), radius: 20)
                .scaleEffect(orbScale)
                .onTapGesture {
                    handleTap()
                }

            // Waveform (when listening/responding)
            if appState.voiceState == .listening || appState.voiceState == .responding {
                WaveformView(isResponding: appState.voiceState == .responding)
                    .frame(width: 120, height: 40)
                    .offset(y: 60)
            }

            // State label
            Text(stateLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .offset(y: appState.voiceState == .idle ? 55 : 100)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animationPhase = .pi * 2
            }
        }
    }

    private var orbColor: Color {
        switch appState.voiceState {
        case .idle: return .white.opacity(0.5)
        case .listening: return .blue
        case .processing: return .purple
        case .responding: return .green
        }
    }

    private var orbGradient: LinearGradient {
        LinearGradient(
            colors: [orbColor, orbColor.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var orbScale: Double {
        switch appState.voiceState {
        case .idle: return 1.0
        case .listening: return 1.0 + sin(animationPhase * 2) * 0.05
        case .processing: return 0.95
        case .responding: return 1.05
        }
    }

    private var stateLabel: String {
        switch appState.voiceState {
        case .idle: return "\"Aria...\""
        case .listening: return "Listening"
        case .processing: return "Thinking"
        case .responding: return "Speaking"
        }
    }

    private func handleTap() {
        HapticFeedback.shared.listeningStarted()
        if appState.voiceState == .idle {
            appState.voiceState = .listening
        } else if appState.voiceState == .listening || appState.voiceState == .responding {
            appState.voiceState = .idle
        }
    }
}

/// Waveform visualization
struct WaveformView: View {
    let isResponding: Bool
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 5)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isResponding ? Color.green : Color.blue)
                    .frame(width: 4, height: levels[index] * 40)
                    .animation(
                        .easeInOut(duration: 0.15).delay(Double(index) * 0.05),
                        value: levels[index]
                    )
            }
        }
        .onAppear {
            animateWaveform()
        }
    }

    private func animateWaveform() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation {
                levels = (0..<5).map { _ in CGFloat.random(in: 0.2...1.0) }
            }
        }
    }
}

/// Transcript and response display
struct TranscriptView: View {
    @EnvironmentObject var conversationManager: ConversationManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // User transcript
            if !conversationManager.currentTranscript.isEmpty {
                Text(conversationManager.currentTranscript)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
            }

            // Assistant response
            if !conversationManager.lastResponse.isEmpty &&
               appState.voiceState == .responding {
                Text(conversationManager.lastResponse)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
        .environmentObject(ConversationManager())
        .environmentObject(AttentionEngine())
}
