import SwiftUI

// MARK: - Conversation History View

/// Shows history of all conversations with Aria
struct ConversationHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var conversations: [ConversationRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedConversation: ConversationRecord?
    @State private var showDeleteConfirmation = false
    @State private var conversationToDelete: ConversationRecord?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    AriaLoadingView(message: "Loading conversations...")
                } else if filteredConversations.isEmpty {
                    if searchText.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "No conversations yet",
                            subtitle: "Start talking to Aria and your conversations will appear here."
                        )
                    } else {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No results found",
                            subtitle: "Try a different search term"
                        )
                    }
                } else {
                    conversationList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.ariaAccentBlue)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            // Export all
                        } label: {
                            Label("Export All", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            // Clear all
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.ariaAccentBlue)
                    }
                }
            }
            .onAppear {
                loadConversations()
            }
            .sheet(item: $selectedConversation) { conversation in
                ConversationDetailView(conversation: conversation)
            }
            .confirmationDialog(
                "Delete Conversation",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let conversation = conversationToDelete {
                        deleteConversation(conversation)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This conversation will be permanently deleted.")
            }
        }
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: AriaSpacing.sm) {
                ForEach(groupedConversations.keys.sorted().reversed(), id: \.self) { date in
                    Section {
                        ForEach(groupedConversations[date] ?? []) { conversation in
                            ConversationRowView(conversation: conversation)
                                .onTapGesture {
                                    HapticFeedback.shared.selection()
                                    selectedConversation = conversation
                                }
                                .contextMenu {
                                    Button {
                                        selectedConversation = conversation
                                    } label: {
                                        Label("View Details", systemImage: "eye")
                                    }

                                    Button {
                                        // Share
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        conversationToDelete = conversation
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(formatDateHeader(date))
                                .font(AriaTypography.labelMedium)
                                .foregroundColor(.ariaTextTertiary)

                            Spacer()
                        }
                        .padding(.horizontal, AriaSpacing.screenHorizontal)
                        .padding(.top, AriaSpacing.md)
                    }
                }
            }
            .padding(.bottom, AriaSpacing.xxl)
        }
    }

    private var filteredConversations: [ConversationRecord] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var groupedConversations: [Date: [ConversationRecord]] {
        Dictionary(grouping: filteredConversations) { conversation in
            Calendar.current.startOfDay(for: conversation.startedAt)
        }
    }

    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    private func loadConversations() {
        // Simulate loading - in production, load from database
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                conversations = ConversationRecord.sampleData
                isLoading = false
            }
        }
    }

    private func deleteConversation(_ conversation: ConversationRecord) {
        HapticFeedback.shared.success()
        withAnimation(AriaAnimation.springStandard) {
            conversations.removeAll { $0.id == conversation.id }
        }
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    let conversation: ConversationRecord

    var body: some View {
        HStack(spacing: AriaSpacing.sm) {
            // Intent icon
            ZStack {
                Circle()
                    .fill(intentColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: intentIcon)
                    .font(.system(size: 18))
                    .foregroundColor(intentColor)
            }

            VStack(alignment: .leading, spacing: AriaSpacing.xxs) {
                // Summary/first message
                Text(conversation.summary ?? conversation.messages.first?.content ?? "Conversation")
                    .font(AriaTypography.bodyMedium)
                    .foregroundColor(.ariaTextPrimary)
                    .lineLimit(1)

                // Time and message count
                HStack(spacing: AriaSpacing.xs) {
                    Text(formatTime(conversation.startedAt))
                        .font(AriaTypography.caption)
                        .foregroundColor(.ariaTextTertiary)

                    Text("•")
                        .foregroundColor(.ariaTextTertiary)

                    Text("\(conversation.messages.count) messages")
                        .font(AriaTypography.caption)
                        .foregroundColor(.ariaTextTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ariaTextTertiary)
        }
        .padding(AriaSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AriaRadius.lg)
                .fill(Color.ariaSurface)
        )
        .padding(.horizontal, AriaSpacing.screenHorizontal)
    }

    private var intentIcon: String {
        switch conversation.primaryIntent {
        case "email": return "envelope.fill"
        case "calendar": return "calendar"
        case "task": return "checkmark.circle.fill"
        case "weather": return "cloud.sun.fill"
        case "reminder": return "bell.fill"
        case "banking": return "creditcard.fill"
        case "music": return "music.note"
        case "navigation": return "location.fill"
        default: return "bubble.left.fill"
        }
    }

    private var intentColor: Color {
        switch conversation.primaryIntent {
        case "email": return .ariaAccentBlue
        case "calendar": return .ariaError
        case "task": return .ariaAccentPurple
        case "weather": return .ariaAccentOrange
        case "reminder": return .ariaWarning
        case "banking": return .ariaAccentGreen
        case "music": return .ariaAccentPink
        case "navigation": return .ariaAccentTeal
        default: return .ariaTextSecondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {
    let conversation: ConversationRecord
    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: AriaSpacing.md) {
                        ForEach(conversation.messages) { message in
                            MessageBubbleView(message: message)
                        }
                    }
                    .padding(AriaSpacing.screenHorizontal)
                    .padding(.bottom, AriaSpacing.xxl)
                }
            }
            .navigationTitle(conversation.summary ?? "Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.ariaAccentBlue)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.ariaAccentBlue)
                    }
                }
            }
        }
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: AriaSpacing.xxs) {
                Text(message.content)
                    .font(AriaTypography.bodyMedium)
                    .foregroundColor(message.role == .user ? .white : .ariaTextPrimary)
                    .padding(AriaSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AriaRadius.md)
                            .fill(message.role == .user ? Color.ariaAccentBlue : Color.ariaSurface)
                    )

                Text(formatTime(message.timestamp))
                    .font(AriaTypography.caption)
                    .foregroundColor(.ariaTextTertiary)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Data Models

struct ConversationRecord: Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let messages: [ConversationMessage]
    let primaryIntent: String?
    let summary: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ConversationRecord, rhs: ConversationRecord) -> Bool {
        lhs.id == rhs.id
    }
}

struct ConversationMessage: Identifiable, Hashable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }
}

// MARK: - Sample Data

extension ConversationRecord {
    static var sampleData: [ConversationRecord] {
        let now = Date()
        let calendar = Calendar.current

        return [
            ConversationRecord(
                id: UUID(),
                startedAt: now.addingTimeInterval(-3600),
                endedAt: now.addingTimeInterval(-3500),
                messages: [
                    ConversationMessage(id: UUID(), role: .user, content: "What's the weather like today?", timestamp: now.addingTimeInterval(-3600)),
                    ConversationMessage(id: UUID(), role: .assistant, content: "It's currently 72°F and sunny in San Francisco. The high today will be 78°F with clear skies throughout the day. Perfect weather for being outdoors!", timestamp: now.addingTimeInterval(-3590))
                ],
                primaryIntent: "weather",
                summary: "Weather inquiry"
            ),
            ConversationRecord(
                id: UUID(),
                startedAt: now.addingTimeInterval(-7200),
                endedAt: now.addingTimeInterval(-7100),
                messages: [
                    ConversationMessage(id: UUID(), role: .user, content: "Remind me to call mom at 5pm", timestamp: now.addingTimeInterval(-7200)),
                    ConversationMessage(id: UUID(), role: .assistant, content: "I've set a reminder to call mom at 5:00 PM today. I'll make sure to notify you when it's time.", timestamp: now.addingTimeInterval(-7190))
                ],
                primaryIntent: "reminder",
                summary: "Set reminder to call mom"
            ),
            ConversationRecord(
                id: UUID(),
                startedAt: calendar.date(byAdding: .day, value: -1, to: now)!,
                endedAt: calendar.date(byAdding: .day, value: -1, to: now)!.addingTimeInterval(300),
                messages: [
                    ConversationMessage(id: UUID(), role: .user, content: "Check my email for anything urgent", timestamp: calendar.date(byAdding: .day, value: -1, to: now)!),
                    ConversationMessage(id: UUID(), role: .assistant, content: "You have 3 urgent emails. The most important one is from your manager about the quarterly review meeting scheduled for tomorrow at 2 PM. Would you like me to read the full message?", timestamp: calendar.date(byAdding: .day, value: -1, to: now)!.addingTimeInterval(10))
                ],
                primaryIntent: "email",
                summary: "Check urgent emails"
            ),
            ConversationRecord(
                id: UUID(),
                startedAt: calendar.date(byAdding: .day, value: -2, to: now)!,
                endedAt: calendar.date(byAdding: .day, value: -2, to: now)!.addingTimeInterval(600),
                messages: [
                    ConversationMessage(id: UUID(), role: .user, content: "Play some relaxing music", timestamp: calendar.date(byAdding: .day, value: -2, to: now)!),
                    ConversationMessage(id: UUID(), role: .assistant, content: "Playing your 'Relaxing Evenings' playlist. This mix includes ambient sounds and soft jazz. Enjoy!", timestamp: calendar.date(byAdding: .day, value: -2, to: now)!.addingTimeInterval(5))
                ],
                primaryIntent: "music",
                summary: "Play relaxing music"
            )
        ]
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Conversation History") {
    ConversationHistoryView()
}

#Preview("Message Bubbles") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 16) {
            MessageBubbleView(
                message: ConversationMessage(
                    id: UUID(),
                    role: .user,
                    content: "What's the weather like today?",
                    timestamp: Date()
                )
            )

            MessageBubbleView(
                message: ConversationMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "It's currently 72°F and sunny. Perfect weather for being outdoors!",
                    timestamp: Date()
                )
            )
        }
        .padding()
    }
}
#endif
