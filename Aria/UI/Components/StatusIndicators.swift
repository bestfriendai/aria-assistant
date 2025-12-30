import SwiftUI

// MARK: - Connection Status Indicator

/// Shows the current connection status (online/offline/connecting)
struct ConnectionStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var isAnimating = false
    @State private var showFullStatus = false

    var body: some View {
        Button {
            withAnimation(AriaAnimation.springStandard) {
                showFullStatus.toggle()
            }
            HapticFeedback.shared.softImpact()
        } label: {
            HStack(spacing: AriaSpacing.xs) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 4)
                    .scaleEffect(isAnimating && !appState.isConnected ? 1.2 : 1.0)

                // Status text (expanded)
                if showFullStatus {
                    Text(statusText)
                        .font(AriaTypography.labelSmall)
                        .foregroundColor(.ariaTextSecondary)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, showFullStatus ? AriaSpacing.sm : AriaSpacing.xs)
            .padding(.vertical, AriaSpacing.xxs)
            .background(
                Capsule()
                    .fill(Color.ariaSurface.opacity(showFullStatus ? 0.8 : 0))
            )
        }
        .ariaAccessibility(
            label: "Connection status: \(statusText)",
            hint: "Tap to see connection details"
        )
        .onAppear {
            startAnimationIfNeeded()
        }
        .onChange(of: appState.isConnected) { _, connected in
            if !connected {
                startAnimationIfNeeded()
            }
        }
    }

    private var statusColor: Color {
        if appState.isOffline {
            return .ariaError
        } else if appState.isConnected {
            return .ariaSuccess
        } else {
            return .ariaWarning
        }
    }

    private var statusText: String {
        if appState.isOffline {
            return "Offline"
        } else if appState.isConnected {
            return "Connected"
        } else {
            return "Connecting..."
        }
    }

    private func startAnimationIfNeeded() {
        if !appState.isConnected && !appState.isOffline {
            withAnimation(AriaAnimation.pulse) {
                isAnimating = true
            }
        } else {
            isAnimating = false
        }
    }
}

// MARK: - Offline Banner

/// Full-width banner shown when offline
struct OfflineBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible = false
    let onRetry: () -> Void

    var body: some View {
        if appState.isOffline && isVisible {
            HStack(spacing: AriaSpacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.ariaError)

                VStack(alignment: .leading, spacing: 2) {
                    Text("You're offline")
                        .font(AriaTypography.labelMedium)
                        .foregroundColor(.ariaTextPrimary)

                    Text("Some features may be unavailable")
                        .font(AriaTypography.caption)
                        .foregroundColor(.ariaTextTertiary)
                }

                Spacer()

                Button("Retry") {
                    HapticFeedback.shared.selection()
                    onRetry()
                }
                .font(AriaTypography.labelMedium)
                .foregroundColor(.ariaAccentBlue)
            }
            .padding(AriaSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AriaRadius.md)
                    .fill(Color.ariaSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AriaRadius.md)
                            .stroke(Color.ariaError.opacity(0.3), lineWidth: 1)
                    )
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
}

// MARK: - Loading Indicator

/// Animated loading indicator with optional message
struct AriaLoadingView: View {
    var message: String?
    var size: CGFloat = 40
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: AriaSpacing.md) {
            // Animated orb
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.ariaListening.opacity(0.2), lineWidth: 3)
                    .frame(width: size, height: size)

                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        LinearGradient(
                            colors: [.ariaListening, .ariaProcessing],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))

                // Center dot
                Circle()
                    .fill(Color.ariaListening)
                    .frame(width: size * 0.25, height: size * 0.25)
            }

            // Message
            if let message = message {
                Text(message)
                    .font(AriaTypography.bodySmall)
                    .foregroundColor(.ariaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .ariaAccessibility(label: message ?? "Loading")
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Skeleton Loading Views

/// Skeleton placeholder for loading content
struct SkeletonView: View {
    var width: CGFloat?
    var height: CGFloat = 16
    var cornerRadius: CGFloat = AriaRadius.sm

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.ariaSurface)
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// Skeleton card for attention items
struct SkeletonAttentionCard: View {
    var body: some View {
        HStack(spacing: AriaSpacing.sm) {
            // Icon placeholder
            Circle()
                .fill(Color.ariaSurface)
                .frame(width: 40, height: 40)
                .shimmer()

            VStack(alignment: .leading, spacing: AriaSpacing.xs) {
                // Title placeholder
                SkeletonView(width: 150, height: 14)

                // Subtitle placeholder
                SkeletonView(width: 200, height: 12)
            }

            Spacer()

            // Time placeholder
            SkeletonView(width: 30, height: 12)
        }
        .padding(AriaSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AriaRadius.lg)
                .fill(Color.ariaSurface.opacity(0.5))
        )
    }
}

// MARK: - Empty States

/// Empty state view with icon, title, and optional action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AriaSpacing.lg) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.ariaSurface)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.05 : 1.0)

                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.ariaTextTertiary)
            }

            VStack(spacing: AriaSpacing.xs) {
                Text(title)
                    .font(AriaTypography.headlineSmall)
                    .foregroundColor(.ariaTextPrimary)
                    .multilineTextAlignment(.center)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AriaTypography.bodySmall)
                        .foregroundColor(.ariaTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle) {
                    HapticFeedback.shared.selection()
                    action()
                }
                .buttonStyle(AriaButtonStyle(style: .secondary))
            }
        }
        .padding(AriaSpacing.xxl)
        .onAppear {
            withAnimation(AriaAnimation.breathe) {
                isAnimating = true
            }
        }
    }
}

/// Empty state specifically for attention items
struct EmptyAttentionView: View {
    var body: some View {
        EmptyStateView(
            icon: "checkmark.circle",
            title: "All caught up!",
            subtitle: "Nothing needs your attention right now.\nI'll let you know when something comes up."
        )
    }
}

// MARK: - Error States

/// Error view with retry option
struct ErrorStateView: View {
    let title: String
    let message: String?
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: AriaSpacing.lg) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.ariaError.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.ariaError)
            }

            VStack(spacing: AriaSpacing.xs) {
                Text(title)
                    .font(AriaTypography.headlineSmall)
                    .foregroundColor(.ariaTextPrimary)
                    .multilineTextAlignment(.center)

                if let message = message {
                    Text(message)
                        .font(AriaTypography.bodySmall)
                        .foregroundColor(.ariaTextTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            if let onRetry = onRetry {
                Button(retryTitle) {
                    HapticFeedback.shared.selection()
                    onRetry()
                }
                .buttonStyle(AriaButtonStyle(style: .primary))
            }
        }
        .padding(AriaSpacing.xxl)
    }
}

// MARK: - Progress Indicators

/// Circular progress indicator
struct CircularProgressView: View {
    let progress: Double
    var lineWidth: CGFloat = 4
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.ariaSurface, lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.ariaAccentBlue, .ariaAccentPurple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(AriaAnimation.smooth, value: progress)

            // Percentage text
            Text("\(Int(progress * 100))%")
                .font(AriaTypography.labelSmall)
                .foregroundColor(.ariaTextSecondary)
        }
        .frame(width: size, height: size)
    }
}

/// Linear progress bar
struct LinearProgressView: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.ariaSurface)

                // Progress
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [.ariaAccentBlue, .ariaAccentPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress)
                    .animation(AriaAnimation.smooth, value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Toast/Snackbar

/// Toast notification view
struct ToastView: View {
    enum ToastType {
        case success
        case error
        case warning
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .ariaSuccess
            case .error: return .ariaError
            case .warning: return .ariaWarning
            case .info: return .ariaAccentBlue
            }
        }
    }

    let type: ToastType
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: AriaSpacing.sm) {
            Image(systemName: type.icon)
                .font(.system(size: 20))
                .foregroundColor(type.color)

            Text(message)
                .font(AriaTypography.bodySmall)
                .foregroundColor(.ariaTextPrimary)
                .lineLimit(2)

            Spacer()

            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ariaTextTertiary)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding(AriaSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AriaRadius.md)
                .fill(Color.ariaSurfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AriaRadius.md)
                        .stroke(type.color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}

// MARK: - Toast Manager

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: ToastData?
    private var dismissTask: Task<Void, Never>?

    struct ToastData: Identifiable {
        let id = UUID()
        let type: ToastView.ToastType
        let message: String
    }

    func show(_ type: ToastView.ToastType, message: String, duration: TimeInterval = 3.0) {
        dismissTask?.cancel()

        withAnimation(AriaAnimation.springStandard) {
            currentToast = ToastData(type: type, message: message)
        }

        // Haptic feedback based on type
        switch type {
        case .success:
            HapticFeedback.shared.success()
        case .error:
            HapticFeedback.shared.error()
        case .warning:
            HapticFeedback.shared.warning()
        case .info:
            HapticFeedback.shared.selection()
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    self.dismiss()
                }
            }
        }
    }

    func dismiss() {
        withAnimation(AriaAnimation.springStandard) {
            currentToast = nil
        }
    }
}

/// Container view that shows toasts
struct ToastContainer<Content: View>: View {
    @StateObject private var toastManager = ToastManager.shared
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            VStack {
                if let toast = toastManager.currentToast {
                    ToastView(
                        type: toast.type,
                        message: toast.message,
                        onDismiss: { toastManager.dismiss() }
                    )
                    .padding(.horizontal, AriaSpacing.screenHorizontal)
                    .padding(.top, AriaSpacing.xl)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                Spacer()
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Loading States") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            AriaLoadingView(message: "Connecting to Aria...")

            HStack(spacing: 20) {
                CircularProgressView(progress: 0.65)
                LinearProgressView(progress: 0.65)
                    .frame(width: 100)
            }
        }
    }
}

#Preview("Empty & Error States") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            EmptyAttentionView()

            ErrorStateView(
                title: "Something went wrong",
                message: "We couldn't load your data. Please try again.",
                onRetry: {}
            )
        }
    }
}

#Preview("Toasts") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 16) {
            ToastView(type: .success, message: "Email sent successfully!")
            ToastView(type: .error, message: "Failed to connect to the server")
            ToastView(type: .warning, message: "Your session will expire soon")
            ToastView(type: .info, message: "New update available")
        }
        .padding()
    }
}
#endif
