import SwiftUI

// MARK: - Onboarding View

/// Welcome and onboarding experience for new users
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var isAnimating = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "waveform.circle.fill",
            iconColor: .ariaAccentBlue,
            title: "Meet Aria",
            subtitle: "Your intelligent personal assistant",
            description: "Aria helps you stay on top of everything that matters. Just speak naturally and she'll understand."
        ),
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: .ariaAccentPurple,
            title: "Smart Attention",
            subtitle: "Never miss what's important",
            description: "Aria prioritizes your emails, tasks, payments, and more—surfacing what needs your attention right now."
        ),
        OnboardingPage(
            icon: "link.circle.fill",
            iconColor: .ariaAccentGreen,
            title: "Connected Life",
            subtitle: "All your services in one place",
            description: "Connect your email, calendar, bank accounts, and more. Aria brings everything together seamlessly."
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            iconColor: .ariaAccentTeal,
            title: "Private & Secure",
            subtitle: "Your data stays yours",
            description: "All data is stored securely on your device. You're always in control of what Aria can access."
        )
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            skipToEnd()
                        }
                        .font(AriaTypography.labelMedium)
                        .foregroundColor(.ariaTextTertiary)
                        .padding()
                    }
                }
                .frame(height: 60)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index], isActive: currentPage == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AriaAnimation.springStandard, value: currentPage)

                // Page indicators
                HStack(spacing: AriaSpacing.sm) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.ariaAccentBlue : Color.ariaSurface)
                            .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                            .animation(AriaAnimation.springQuick, value: currentPage)
                    }
                }
                .padding(.vertical, AriaSpacing.lg)

                // Action button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(AriaAnimation.springStandard) {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                    HapticFeedback.shared.selection()
                } label: {
                    HStack {
                        Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                            .font(AriaTypography.headlineSmall)

                        Image(systemName: currentPage < pages.count - 1 ? "arrow.right" : "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AriaSpacing.md)
                    .background(
                        LinearGradient(
                            colors: [.ariaAccentBlue, .ariaAccentPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(AriaRadius.lg)
                }
                .padding(.horizontal, AriaSpacing.screenHorizontal)
                .padding(.bottom, AriaSpacing.xxl)
            }
        }
    }

    private func skipToEnd() {
        HapticFeedback.shared.selection()
        withAnimation(AriaAnimation.springStandard) {
            currentPage = pages.count - 1
        }
    }

    private func completeOnboarding() {
        HapticFeedback.shared.success()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation(AriaAnimation.smooth) {
            isPresented = false
        }
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    @State private var iconScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: AriaSpacing.xxl) {
            Spacer()

            // Icon with animation
            ZStack {
                // Background glow
                Circle()
                    .fill(page.iconColor.opacity(0.15))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)

                // Icon container
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [page.iconColor.opacity(0.2), page.iconColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(page.iconColor.opacity(0.3), lineWidth: 1)
                    )

                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(page.iconColor)
            }
            .scaleEffect(iconScale)
            .animation(AriaAnimation.springBouncy, value: iconScale)

            // Text content
            VStack(spacing: AriaSpacing.md) {
                Text(page.title)
                    .font(AriaTypography.displayMedium)
                    .foregroundColor(.ariaTextPrimary)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(AriaTypography.headlineSmall)
                    .foregroundColor(page.iconColor)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(AriaTypography.bodyMedium)
                    .foregroundColor(.ariaTextTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, AriaSpacing.lg)
            }
            .opacity(contentOpacity)
            .animation(AriaAnimation.smooth.delay(0.1), value: contentOpacity)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AriaSpacing.screenHorizontal)
        .onChange(of: isActive) { _, active in
            if active {
                iconScale = 1.0
                contentOpacity = 1.0
            } else {
                iconScale = 0.8
                contentOpacity = 0
            }
        }
        .onAppear {
            if isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    iconScale = 1.0
                    contentOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - Welcome Back View

/// Shown when user returns after some time
struct WelcomeBackView: View {
    let userName: String?
    @Binding var isPresented: Bool
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.9

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: AriaSpacing.xl) {
                // Greeting icon
                ZStack {
                    Circle()
                        .fill(Color.ariaAccentBlue.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: timeBasedIcon)
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.ariaAccentBlue)
                }

                VStack(spacing: AriaSpacing.sm) {
                    Text(greeting)
                        .font(AriaTypography.displaySmall)
                        .foregroundColor(.ariaTextPrimary)

                    if let userName = userName {
                        Text(userName)
                            .font(AriaTypography.headlineLarge)
                            .foregroundColor(.ariaAccentBlue)
                    }

                    Text("How can I help you today?")
                        .font(AriaTypography.bodyMedium)
                        .foregroundColor(.ariaTextTertiary)
                        .padding(.top, AriaSpacing.xs)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Let's go")
                        .font(AriaTypography.labelLarge)
                        .foregroundColor(.white)
                        .padding(.horizontal, AriaSpacing.xxl)
                        .padding(.vertical, AriaSpacing.sm)
                        .background(Color.ariaAccentBlue)
                        .cornerRadius(AriaRadius.full)
                }
                .padding(.top, AriaSpacing.md)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(AriaAnimation.springStandard) {
                opacity = 1
                scale = 1
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    private var timeBasedIcon: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "moon.stars.fill"
        case 6..<12: return "sun.horizon.fill"
        case 12..<17: return "sun.max.fill"
        case 17..<21: return "sunset.fill"
        default: return "moon.fill"
        }
    }

    private func dismiss() {
        HapticFeedback.shared.selection()
        withAnimation(AriaAnimation.smooth) {
            isPresented = false
        }
    }
}

// MARK: - Quick Tips Overlay

/// Shows contextual tips for first-time users
struct QuickTipView: View {
    let tip: QuickTip
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AriaSpacing.sm) {
            HStack {
                Image(systemName: tip.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.ariaAccentBlue)

                Text(tip.title)
                    .font(AriaTypography.labelLarge)
                    .foregroundColor(.ariaTextPrimary)

                Spacer()

                Button {
                    HapticFeedback.shared.selection()
                    withAnimation(AriaAnimation.springQuick) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ariaTextTertiary)
                        .frame(width: 24, height: 24)
                }
            }

            Text(tip.message)
                .font(AriaTypography.bodySmall)
                .foregroundColor(.ariaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if tip.showDontShowAgain {
                Button {
                    tip.onDontShowAgain?()
                    withAnimation(AriaAnimation.springQuick) {
                        isPresented = false
                    }
                } label: {
                    Text("Don't show again")
                        .font(AriaTypography.caption)
                        .foregroundColor(.ariaTextTertiary)
                }
            }
        }
        .padding(AriaSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AriaRadius.md)
                .fill(Color.ariaSurfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AriaRadius.md)
                        .stroke(Color.ariaAccentBlue.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}

struct QuickTip {
    let icon: String
    let title: String
    let message: String
    var showDontShowAgain: Bool = false
    var onDontShowAgain: (() -> Void)?
}

// MARK: - First Time Feature Highlights

/// Highlights a feature for first-time users
struct FeatureHighlightView: View {
    let title: String
    let description: String
    let position: CGPoint
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Spotlight effect
            Circle()
                .fill(.clear)
                .frame(width: 120, height: 120)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .blur(radius: 20)
                )
                .position(position)

            // Tooltip
            VStack(alignment: .leading, spacing: AriaSpacing.xs) {
                Text(title)
                    .font(AriaTypography.headlineSmall)
                    .foregroundColor(.ariaTextPrimary)

                Text(description)
                    .font(AriaTypography.bodySmall)
                    .foregroundColor(.ariaTextSecondary)

                Button("Got it") {
                    dismiss()
                }
                .buttonStyle(AriaButtonStyle(style: .secondary))
                .padding(.top, AriaSpacing.xs)
            }
            .padding(AriaSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AriaRadius.md)
                    .fill(Color.ariaSurfaceElevated)
            )
            .position(
                x: position.x,
                y: position.y + 100
            )
        }
    }

    private func dismiss() {
        HapticFeedback.shared.selection()
        withAnimation(AriaAnimation.smooth) {
            isPresented = false
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Onboarding") {
    OnboardingView(isPresented: .constant(true))
}

#Preview("Welcome Back") {
    WelcomeBackView(userName: "Sarah", isPresented: .constant(true))
}

#Preview("Quick Tip") {
    ZStack {
        Color.black.ignoresSafeArea()

        QuickTipView(
            tip: QuickTip(
                icon: "hand.tap.fill",
                title: "Tap the orb to speak",
                message: "Just tap the voice orb and say \"Aria\" followed by your request. I'll take care of the rest!"
            ),
            isPresented: .constant(true)
        )
        .padding()
    }
}
#endif
