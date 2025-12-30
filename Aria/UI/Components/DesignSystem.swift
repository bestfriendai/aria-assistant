import SwiftUI

// MARK: - Design System
/// Centralized design system for consistent UI/UX across Aria

// MARK: - Color Palette
extension Color {
    // MARK: Primary Colors
    static let ariaPrimary = Color("AriaPrimary", bundle: nil)
    static let ariaSecondary = Color("AriaSecondary", bundle: nil)

    // MARK: Semantic Colors
    static let ariaBackground = Color(uiColor: .systemBackground)
    static let ariaSurface = Color(white: 0.1)
    static let ariaSurfaceElevated = Color(white: 0.15)

    // MARK: Text Colors
    static let ariaTextPrimary = Color.white
    static let ariaTextSecondary = Color.white.opacity(0.7)
    static let ariaTextTertiary = Color.white.opacity(0.5)
    static let ariaTextDisabled = Color.white.opacity(0.3)

    // MARK: State Colors
    static let ariaListening = Color(red: 0.2, green: 0.5, blue: 1.0)
    static let ariaProcessing = Color(red: 0.6, green: 0.3, blue: 1.0)
    static let ariaResponding = Color(red: 0.2, green: 0.8, blue: 0.5)
    static let ariaIdle = Color.white.opacity(0.6)
    static let ariaError = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let ariaWarning = Color(red: 1.0, green: 0.7, blue: 0.2)
    static let ariaSuccess = Color(red: 0.3, green: 0.85, blue: 0.4)

    // MARK: Accent Colors
    static let ariaAccentBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let ariaAccentPurple = Color(red: 0.6, green: 0.35, blue: 1.0)
    static let ariaAccentGreen = Color(red: 0.2, green: 0.8, blue: 0.5)
    static let ariaAccentOrange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let ariaAccentPink = Color(red: 1.0, green: 0.4, blue: 0.6)
    static let ariaAccentTeal = Color(red: 0.2, green: 0.75, blue: 0.8)

    // MARK: Gradient Backgrounds
    static var ariaGradientBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.black,
                Color(white: 0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var ariaGradientSurface: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.12),
                Color(white: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography
struct AriaTypography {
    // MARK: Display Styles
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 24, weight: .semibold, design: .rounded)

    // MARK: Heading Styles
    static let headlineLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let headlineMedium = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let headlineSmall = Font.system(size: 16, weight: .semibold, design: .rounded)

    // MARK: Body Styles
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .rounded)
    static let bodyMedium = Font.system(size: 15, weight: .regular, design: .rounded)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .rounded)

    // MARK: Label Styles
    static let labelLarge = Font.system(size: 14, weight: .medium, design: .rounded)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .rounded)
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .rounded)

    // MARK: Caption Styles
    static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    static let captionBold = Font.system(size: 12, weight: .semibold, design: .rounded)

    // MARK: Monospace (for times, codes)
    static let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .medium, design: .monospaced)
}

// MARK: - Spacing
struct AriaSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    // Screen edges
    static let screenHorizontal: CGFloat = 20
    static let screenVertical: CGFloat = 16

    // Card padding
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
}

// MARK: - Corner Radius
struct AriaRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let full: CGFloat = 9999
}

// MARK: - Shadows
struct AriaShadow {
    static let small = Shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    static let medium = Shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    static let large = Shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    static let glow = { (color: Color) in Shadow(color: color.opacity(0.5), radius: 20, x: 0, y: 0) }

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - Animation
struct AriaAnimation {
    static let quick = Animation.easeInOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.easeInOut(duration: 0.35)
    static let slow = Animation.easeInOut(duration: 0.5)

    static let springQuick = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let springStandard = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.6)
    static let springSmooth = Animation.spring(response: 0.6, dampingFraction: 0.85)

    // Pulse animation
    static let pulse = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    static let breathe = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}

// MARK: - View Modifiers

/// Card style modifier
struct AriaCardStyle: ViewModifier {
    var color: Color = .ariaSurface
    var borderColor: Color? = nil
    var hasShadow: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(AriaSpacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: AriaRadius.lg)
                    .fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: AriaRadius.lg)
                            .stroke(borderColor ?? .clear, lineWidth: 1)
                    )
            )
            .if(hasShadow) { view in
                view.shadow(
                    color: AriaShadow.medium.color,
                    radius: AriaShadow.medium.radius,
                    x: AriaShadow.medium.x,
                    y: AriaShadow.medium.y
                )
            }
    }
}

/// Glass morphism style
struct AriaGlassStyle: ViewModifier {
    var opacity: Double = 0.1
    var blur: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AriaRadius.lg)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity * 10)
            )
    }
}

/// Button style
struct AriaButtonStyle: ButtonStyle {
    enum Style {
        case primary
        case secondary
        case tertiary
        case destructive
    }

    var style: Style = .primary
    var isFullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AriaTypography.labelLarge)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, AriaSpacing.lg)
            .padding(.vertical, AriaSpacing.sm)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(backgroundColor)
            .cornerRadius(AriaRadius.md)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(AriaAnimation.quick, value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return .ariaAccentBlue
        case .tertiary: return .ariaTextSecondary
        case .destructive: return .ariaError
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return .ariaAccentBlue
        case .secondary: return .ariaAccentBlue.opacity(0.15)
        case .tertiary: return .clear
        case .destructive: return .ariaError.opacity(0.15)
        }
    }
}

/// Icon button style
struct AriaIconButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var backgroundColor: Color = .ariaSurface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(AriaAnimation.quick, value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply card style
    func ariaCard(color: Color = .ariaSurface, borderColor: Color? = nil, hasShadow: Bool = false) -> some View {
        modifier(AriaCardStyle(color: color, borderColor: borderColor, hasShadow: hasShadow))
    }

    /// Apply glass style
    func ariaGlass(opacity: Double = 0.1, blur: CGFloat = 10) -> some View {
        modifier(AriaGlassStyle(opacity: opacity, blur: blur))
    }

    /// Conditional modifier
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Accessibility label with hint
    func ariaAccessibility(label: String, hint: String? = nil, traits: AccessibilityTraits = []) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
    }

    /// Shimmer loading effect
    func shimmer(isActive: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}

/// Shimmer loading effect modifier
struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isActive {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .white.opacity(0.3),
                                .clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                        .onAppear {
                            withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                }
                .mask(content)
            )
    }
}

// MARK: - Accessibility Helpers

struct AriaAccessibility {
    /// Standard button hint
    static let buttonHint = "Double tap to activate"

    /// Voice orb accessibility
    static let voiceOrbLabel = "Voice input"
    static let voiceOrbIdleHint = "Double tap to start listening"
    static let voiceOrbListeningHint = "Listening. Double tap to stop"
    static let voiceOrbProcessingHint = "Processing your request"
    static let voiceOrbRespondingHint = "Speaking. Double tap to stop"

    /// Settings accessibility
    static let settingsLabel = "Settings"
    static let settingsHint = "Open app settings"

    /// Attention item accessibility
    static func attentionItemLabel(title: String, subtitle: String?, urgency: Double) -> String {
        var label = title
        if let subtitle = subtitle {
            label += ". \(subtitle)"
        }
        if urgency > 0.7 {
            label = "Urgent: \(label)"
        }
        return label
    }

    static let swipeRightHint = "Swipe right to mark as done"
    static let swipeLeftHint = "Swipe left to snooze"
}

// MARK: - Haptic Feedback Enhancements

extension HapticFeedback {
    /// Light selection feedback for scroll/navigation
    func lightSelection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Warning feedback
    func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Soft impact for subtle interactions
    func softImpact() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Rigid impact for confirmations
    func rigidImpact() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct DesignSystemPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AriaSpacing.xl) {
                // Colors
                VStack(alignment: .leading, spacing: AriaSpacing.sm) {
                    Text("Colors")
                        .font(AriaTypography.headlineLarge)
                        .foregroundColor(.ariaTextPrimary)

                    HStack(spacing: AriaSpacing.sm) {
                        ColorSwatch(color: .ariaListening, name: "Listening")
                        ColorSwatch(color: .ariaProcessing, name: "Processing")
                        ColorSwatch(color: .ariaResponding, name: "Responding")
                        ColorSwatch(color: .ariaError, name: "Error")
                    }
                }

                // Typography
                VStack(alignment: .leading, spacing: AriaSpacing.sm) {
                    Text("Typography")
                        .font(AriaTypography.headlineLarge)
                        .foregroundColor(.ariaTextPrimary)

                    Text("Display Large")
                        .font(AriaTypography.displayLarge)
                        .foregroundColor(.ariaTextPrimary)

                    Text("Headline Medium")
                        .font(AriaTypography.headlineMedium)
                        .foregroundColor(.ariaTextSecondary)

                    Text("Body Medium")
                        .font(AriaTypography.bodyMedium)
                        .foregroundColor(.ariaTextTertiary)
                }

                // Buttons
                VStack(alignment: .leading, spacing: AriaSpacing.sm) {
                    Text("Buttons")
                        .font(AriaTypography.headlineLarge)
                        .foregroundColor(.ariaTextPrimary)

                    Button("Primary Button") {}
                        .buttonStyle(AriaButtonStyle(style: .primary))

                    Button("Secondary Button") {}
                        .buttonStyle(AriaButtonStyle(style: .secondary))

                    Button("Destructive Button") {}
                        .buttonStyle(AriaButtonStyle(style: .destructive))
                }

                // Cards
                VStack(alignment: .leading, spacing: AriaSpacing.sm) {
                    Text("Cards")
                        .font(AriaTypography.headlineLarge)
                        .foregroundColor(.ariaTextPrimary)

                    Text("Card content goes here")
                        .font(AriaTypography.bodyMedium)
                        .foregroundColor(.ariaTextSecondary)
                        .ariaCard(borderColor: .ariaAccentBlue.opacity(0.3))
                }
            }
            .padding(AriaSpacing.screenHorizontal)
        }
        .background(Color.black)
    }
}

struct ColorSwatch: View {
    let color: Color
    let name: String

    var body: some View {
        VStack(spacing: AriaSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
            Text(name)
                .font(AriaTypography.caption)
                .foregroundColor(.ariaTextTertiary)
        }
    }
}

#Preview {
    DesignSystemPreview()
}
#endif
