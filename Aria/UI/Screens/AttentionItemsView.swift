import SwiftUI

/// Displays attention items that need user focus
struct AttentionItemsView: View {
    @EnvironmentObject var attentionEngine: AttentionEngine

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(attentionEngine.items) { item in
                    AttentionItemCard(item: item)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxHeight: 350)
    }
}

/// Individual attention item card
struct AttentionItemCard: View {
    let item: AttentionItem
    @EnvironmentObject var attentionEngine: AttentionEngine

    @State private var offset: CGFloat = 0
    @State private var showActions = false

    var body: some View {
        ZStack {
            // Background actions
            HStack {
                // Dismiss (right swipe)
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                    Text("Done")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)

                Spacer()

                // Snooze (left swipe)
                HStack {
                    Text("Snooze")
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "clock.fill")
                        .font(.system(size: 24))
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
            }

            // Main card
            HStack(spacing: 12) {
                // Icon
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundColor(item.color)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(item.color.opacity(0.2))
                    )

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Time indicator
                Text(timeAgo(item.createdAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(item.color.opacity(0.3), lineWidth: 1)
                    )
            )
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
            .onTapGesture {
                showActions = true
            }
            .onLongPressGesture {
                HapticFeedback.shared.selection()
                showActions = true
            }
        }
        .sheet(isPresented: $showActions) {
            AttentionItemActionsView(item: item)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleSwipe(_ translation: CGFloat) {
        if translation > 100 {
            // Dismiss
            HapticFeedback.shared.success()
            withAnimation(.spring()) {
                offset = 400
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task {
                    await attentionEngine.dismiss(item)
                }
            }
        } else if translation < -100 {
            // Snooze
            HapticFeedback.shared.selection()
            withAnimation(.spring()) {
                offset = -400
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task {
                    await attentionEngine.snooze(item, duration: 3600) // 1 hour
                }
            }
        } else {
            // Snap back
            withAnimation(.spring()) {
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

/// Quick actions sheet for an attention item
struct AttentionItemActionsView: View {
    let item: AttentionItem
    @EnvironmentObject var attentionEngine: AttentionEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 32))
                    .foregroundColor(item.color)

                Text(item.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 24)

            Divider()

            // Actions
            VStack(spacing: 0) {
                ForEach(item.actions) { action in
                    Button {
                        handleAction(action)
                    } label: {
                        HStack {
                            Image(systemName: action.icon)
                                .font(.system(size: 18))
                                .frame(width: 24)

                            Text(action.title)
                                .font(.system(size: 16, weight: .medium))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .foregroundColor(.primary)

                    Divider()
                        .padding(.leading, 64)
                }

                // Snooze options
                Menu {
                    Button("1 hour") { snooze(3600) }
                    Button("3 hours") { snooze(10800) }
                    Button("Tomorrow") { snooze(86400) }
                } label: {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 18))
                            .frame(width: 24)

                        Text("Snooze")
                            .font(.system(size: 16, weight: .medium))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .foregroundColor(.primary)

                Divider()
                    .padding(.leading, 64)

                // Dismiss
                Button {
                    Task {
                        await attentionEngine.dismiss(item)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 18))
                            .frame(width: 24)

                        Text("Dismiss")
                            .font(.system(size: 16, weight: .medium))

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .foregroundColor(.red)
            }

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    private func handleAction(_ action: QuickAction) {
        HapticFeedback.shared.selection()
        // Handle action based on type
        dismiss()
    }

    private func snooze(_ duration: TimeInterval) {
        Task {
            await attentionEngine.snooze(item, duration: duration)
            dismiss()
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        AttentionItemsView()
            .environmentObject(AttentionEngine())
    }
}
