import Foundation
import Combine

/// Engine that computes and manages attention items
@MainActor
class AttentionEngine: ObservableObject {
    // MARK: - Published State

    @Published var items: [AttentionItem] = []
    @Published var isLoading = false

    // MARK: - Configuration

    private let maxItems = 5
    private let refreshInterval: TimeInterval = 60 // 1 minute
    private let urgencyThreshold = 0.5

    // MARK: - Sources

    private var sources: [AttentionSource] = []
    private var refreshTimer: Timer?

    // MARK: - Priority Scorer

    private let scorer = PriorityScorer()

    // MARK: - Lifecycle

    func start() async {
        // Initialize sources
        sources = [
            EmailAttentionSource(),
            CalendarAttentionSource(),
            TaskAttentionSource(),
            BankingAttentionSource(),
            ShoppingAttentionSource()
        ]

        // Initial refresh
        await refresh()

        // Start periodic refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Gather items from all sources
        var allItems: [AttentionItem] = []

        for source in sources {
            let sourceItems = await source.getItems()
            allItems.append(contentsOf: sourceItems)
        }

        // Score and filter
        let scored = scorer.score(allItems)

        // Filter and sort
        items = scored
            .filter { $0.urgency >= urgencyThreshold }
            .sorted { $0.urgency > $1.urgency }
            .prefix(maxItems)
            .map { $0 }
    }

    // MARK: - Actions

    func dismiss(_ item: AttentionItem) async {
        withAnimation {
            items.removeAll { $0.id == item.id }
        }

        // Persist dismissal
        await persistDismissal(item)
    }

    func snooze(_ item: AttentionItem, duration: TimeInterval) async {
        withAnimation {
            items.removeAll { $0.id == item.id }
        }

        // Schedule reappearance
        await scheduleSnooze(item, duration: duration)
    }

    private func persistDismissal(_ item: AttentionItem) async {
        // Store in database
    }

    private func scheduleSnooze(_ item: AttentionItem, duration: TimeInterval) async {
        // Schedule notification to bring back item
    }
}

// MARK: - Attention Source Protocol

protocol AttentionSource {
    func getItems() async -> [AttentionItem]
}

// MARK: - Email Attention Source

class EmailAttentionSource: AttentionSource {
    func getItems() async -> [AttentionItem] {
        // Fetch urgent/unread emails
        // For now, return sample data
        return [
            AttentionItem(
                type: .urgentEmail,
                title: "Flight confirmation",
                subtitle: "Delta 1247 to NYC, Gate B12",
                urgency: 0.8,
                source: .email,
                actions: [
                    QuickAction(title: "Reply", icon: "arrowshape.turn.up.left", actionType: .reply(emailId: "1")),
                    QuickAction(title: "Archive", icon: "archivebox", actionType: .dismiss)
                ]
            )
        ]
    }
}

// MARK: - Calendar Attention Source

class CalendarAttentionSource: AttentionSource {
    func getItems() async -> [AttentionItem] {
        // Fetch upcoming events needing attention
        return []
    }
}

// MARK: - Task Attention Source

class TaskAttentionSource: AttentionSource {
    func getItems() async -> [AttentionItem] {
        // Fetch overdue/urgent tasks
        return []
    }
}

// MARK: - Banking Attention Source

class BankingAttentionSource: AttentionSource {
    func getItems() async -> [AttentionItem] {
        // Fetch bills due, low balance alerts
        return [
            AttentionItem(
                type: .paymentDue,
                title: "Rent due tomorrow",
                subtitle: "$2,450 to Chase Checking",
                urgency: 0.9,
                source: .banking,
                actions: [
                    QuickAction(title: "Pay Now", icon: "creditcard", actionType: .pay(paymentId: "rent")),
                    QuickAction(title: "Snooze", icon: "clock", actionType: .snooze(duration: 3600))
                ]
            )
        ]
    }
}

// MARK: - Shopping Attention Source

class ShoppingAttentionSource: AttentionSource {
    func getItems() async -> [AttentionItem] {
        // Fetch delivery updates
        return []
    }
}

// MARK: - Priority Scorer

class PriorityScorer {
    func score(_ items: [AttentionItem]) -> [AttentionItem] {
        // Apply additional scoring logic
        items.map { item in
            var scored = item

            // Boost based on type
            var boost: Double = 0
            switch item.type {
            case .missedCall:
                boost = 0.1 // Calls are time-sensitive
            case .paymentDue:
                boost = 0.05 // Financial matters are important
            case .calendarReminder:
                boost = 0.05
            default:
                break
            }

            // Create new item with adjusted urgency
            return AttentionItem(
                id: item.id,
                type: item.type,
                title: item.title,
                subtitle: item.subtitle,
                urgency: min(1.0, item.urgency + boost),
                source: item.source,
                sourceRef: item.sourceRef,
                actions: item.actions,
                createdAt: item.createdAt,
                expiresAt: item.expiresAt
            )
        }
    }
}
