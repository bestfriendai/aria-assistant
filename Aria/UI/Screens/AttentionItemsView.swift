import SwiftUI

/// Displays attention items that need user focus
struct AttentionItemsView: View {
    @EnvironmentObject var attentionEngine: AttentionEngine

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AriaSpacing.sm) {
                ForEach(attentionEngine.items) { item in
                    AttentionItemCard(item: item)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                }
            }
            .padding(.horizontal, AriaSpacing.screenHorizontal)
            .animation(AriaAnimation.springStandard, value: attentionEngine.items.count)
        }
        .frame(maxHeight: 350)
    }
}

/// Individual attention item card with enhanced interactions
struct AttentionItemCard: View {
    let item: AttentionItem
    @EnvironmentObject var attentionEngine: AttentionEngine

    @State private var offset: CGFloat = 0
    @State private var showActions = false
    @State private var isPressed = false

    // Thresholds for swipe actions
    private let dismissThreshold: CGFloat = 100
    private let snoozeThreshold: CGFloat = -100

    var body: some View {
        ZStack {
            // Background actions (revealed on swipe)
            backgroundActions

            // Main card
            mainCard
        }
        .sheet(isPresented: $showActions) {
            AttentionItemActionsView(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Background Actions

    private var backgroundActions: some View {
        HStack {
            // Dismiss action (right swipe)
            HStack(spacing: AriaSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                Text("Done")
                    .font(AriaTypography.labelMedium)
            }
            .foregroundColor(.ariaSuccess)
            .opacity(offset > 50 ? min(1, (offset - 50) / 50) : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, AriaSpacing.lg)

            Spacer()

            // Snooze action (left swipe)
            HStack(spacing: AriaSpacing.xs) {
                Text("Snooze")
                    .font(AriaTypography.labelMedium)
                Image(systemName: "clock.fill")
                    .font(.system(size: 24))
            }
            .foregroundColor(.ariaWarning)
            .opacity(offset < -50 ? min(1, (-offset - 50) / 50) : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, AriaSpacing.lg)
        }
    }

    // MARK: - Main Card

    private var mainCard: some View {
        HStack(spacing: AriaSpacing.sm) {
            // Icon with urgency indicator
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundColor(item.color)

                // Urgency badge
                if item.urgency > 0.7 {
                    Circle()
                        .fill(Color.ariaError)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .offset(x: 14, y: -14)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: AriaSpacing.xxs) {
                Text(item.title)
                    .font(AriaTypography.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.ariaTextPrimary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AriaTypography.bodySmall)
                        .foregroundColor(.ariaTextSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Time indicator
            VStack(alignment: .trailing, spacing: AriaSpacing.xxs) {
                Text(timeAgo(item.createdAt))
                    .font(AriaTypography.labelSmall)
                    .foregroundColor(.ariaTextTertiary)

                // Quick action count
                if !item.actions.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text("\(item.actions.count)")
                            .font(AriaTypography.caption)
                    }
                    .foregroundColor(.ariaTextTertiary)
                }
            }
        }
        .padding(AriaSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AriaRadius.lg)
                .fill(Color.ariaSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: AriaRadius.lg)
                        .stroke(
                            item.urgency > 0.7
                                ? item.color.opacity(0.5)
                                : item.color.opacity(0.2),
                            lineWidth: item.urgency > 0.7 ? 2 : 1
                        )
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .offset(x: offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation.width
                }
                .onEnded { gesture in
                    handleSwipe(gesture.translation.width)
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.1)
                .onChanged { _ in
                    withAnimation(AriaAnimation.quick) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(AriaAnimation.quick) {
                        isPressed = false
                    }
                }
        )
        .onTapGesture {
            HapticFeedback.shared.selection()
            showActions = true
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            HapticFeedback.shared.selection()
            showActions = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AriaAccessibility.attentionItemLabel(
            title: item.title,
            subtitle: item.subtitle,
            urgency: item.urgency
        ))
        .accessibilityHint("\(AriaAccessibility.swipeRightHint). \(AriaAccessibility.swipeLeftHint). Double tap for more options.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Helpers

    private func handleSwipe(_ translation: CGFloat) {
        if translation > dismissThreshold {
            // Dismiss
            HapticFeedback.shared.success()
            withAnimation(AriaAnimation.springStandard) {
                offset = 400
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task {
                    await attentionEngine.dismiss(item)
                }
            }
        } else if translation < snoozeThreshold {
            // Snooze
            HapticFeedback.shared.selection()
            withAnimation(AriaAnimation.springStandard) {
                offset = -400
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task {
                    await attentionEngine.snooze(item, duration: 3600) // 1 hour
                }
            }
        } else {
            // Snap back
            withAnimation(AriaAnimation.springStandard) {
                offset = 0
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

/// Enhanced quick actions sheet for an attention item
struct AttentionItemActionsView: View {
    let item: AttentionItem
    @EnvironmentObject var attentionEngine: AttentionEngine
    @Environment(\.dismiss) var dismiss

    @State private var isPerformingAction = false
    @State private var selectedSnoozeOption: SnoozeOption?

    enum SnoozeOption: String, CaseIterable {
        case oneHour = "1 hour"
        case threeHours = "3 hours"
        case tomorrow = "Tomorrow"
        case nextWeek = "Next week"

        var duration: TimeInterval {
            switch self {
            case .oneHour: return 3600
            case .threeHours: return 10800
            case .tomorrow: return 86400
            case .nextWeek: return 604800
            }
        }

        var icon: String {
            switch self {
            case .oneHour: return "clock"
            case .threeHours: return "clock.badge"
            case .tomorrow: return "sun.max"
            case .nextWeek: return "calendar"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                header
                    .padding(.vertical, AriaSpacing.lg)

                Divider()

                // Actions list
                ScrollView {
                    VStack(spacing: 0) {
                        // Quick actions
                        if !item.actions.isEmpty {
                            ForEach(item.actions) { action in
                                ActionButton(
                                    icon: action.icon,
                                    title: action.title,
                                    isLoading: isPerformingAction
                                ) {
                                    performAction(action)
                                }
                            }

                            Divider()
                                .padding(.vertical, AriaSpacing.sm)
                        }

                        // Snooze options
                        VStack(alignment: .leading, spacing: AriaSpacing.xs) {
                            Text("Snooze")
                                .font(AriaTypography.labelMedium)
                                .foregroundColor(.ariaTextTertiary)
                                .padding(.horizontal, AriaSpacing.lg)
                                .padding(.top, AriaSpacing.sm)

                            ForEach(SnoozeOption.allCases, id: \.self) { option in
                                ActionButton(
                                    icon: option.icon,
                                    title: option.rawValue,
                                    color: .ariaWarning
                                ) {
                                    snooze(option.duration)
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, AriaSpacing.sm)

                        // Dismiss
                        ActionButton(
                            icon: "xmark.circle",
                            title: "Dismiss",
                            color: .ariaError,
                            isDestructive: true
                        ) {
                            dismissItem()
                        }
                    }
                    .padding(.bottom, AriaSpacing.xxl)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AriaTypography.labelLarge)
                    .foregroundColor(.ariaAccentBlue)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AriaSpacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: item.icon)
                    .font(.system(size: 28))
                    .foregroundColor(item.color)
            }

            // Title
            Text(item.title)
                .font(AriaTypography.headlineSmall)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            // Subtitle
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(AriaTypography.bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            // Time
            Text(formatDate(item.createdAt))
                .font(AriaTypography.caption)
                .foregroundColor(.ariaTextTertiary)
        }
        .padding(.horizontal, AriaSpacing.lg)
    }

    // MARK: - Actions

    private func performAction(_ action: QuickAction) {
        HapticFeedback.shared.selection()
        isPerformingAction = true

        // Simulate action execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isPerformingAction = false
            HapticFeedback.shared.success()
            dismiss()
        }
    }

    private func snooze(_ duration: TimeInterval) {
        HapticFeedback.shared.selection()
        Task {
            await attentionEngine.snooze(item, duration: duration)
            dismiss()
        }
    }

    private func dismissItem() {
        HapticFeedback.shared.success()
        Task {
            await attentionEngine.dismiss(item)
            dismiss()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    var color: Color = .primary
    var isDestructive: Bool = false
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: AriaSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isDestructive ? .ariaError : color)
                    .frame(width: 24)

                Text(title)
                    .font(AriaTypography.bodyMedium)
                    .foregroundColor(isDestructive ? .ariaError : .primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, AriaSpacing.lg)
            .padding(.vertical, AriaSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Previews

#Preview("Attention Items") {
    ZStack {
        Color.black.ignoresSafeArea()

        AttentionItemsView()
            .environmentObject(AttentionEngine())
    }
}

#Preview("Attention Item Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 16) {
            AttentionItemCard(
                item: AttentionItem(
                    type: .urgentEmail,
                    title: "Urgent: Project deadline tomorrow",
                    subtitle: "From: manager@company.com",
                    urgency: 0.9,
                    source: .email,
                    actions: [
                        QuickAction(title: "Reply", icon: "arrowshape.turn.up.left", actionType: .reply(emailId: "123")),
                        QuickAction(title: "Archive", icon: "archivebox", actionType: .dismiss)
                    ]
                )
            )
            .environmentObject(AttentionEngine())

            AttentionItemCard(
                item: AttentionItem(
                    type: .paymentDue,
                    title: "Credit card payment due",
                    subtitle: "Chase Sapphire - $1,234.56",
                    urgency: 0.6,
                    source: .banking,
                    actions: [
                        QuickAction(title: "Pay Now", icon: "creditcard", actionType: .pay(paymentId: "456"))
                    ]
                )
            )
            .environmentObject(AttentionEngine())
        }
        .padding()
    }
}

#Preview("Actions Sheet") {
    AttentionItemActionsView(
        item: AttentionItem(
            type: .urgentEmail,
            title: "Urgent: Project deadline tomorrow",
            subtitle: "Please review the attached document and provide your feedback by EOD.",
            urgency: 0.9,
            source: .email,
            actions: [
                QuickAction(title: "Reply", icon: "arrowshape.turn.up.left", actionType: .reply(emailId: "123")),
                QuickAction(title: "Forward", icon: "arrowshape.turn.up.right", actionType: .custom(action: "forward")),
                QuickAction(title: "Archive", icon: "archivebox", actionType: .dismiss)
            ]
        )
    )
    .environmentObject(AttentionEngine())
}
