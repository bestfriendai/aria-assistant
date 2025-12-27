import Foundation
import StoreKit

/// Subscription tracking service for managing recurring expenses
actor SubscriptionService {
    // MARK: - Cache

    private var subscriptionsCache: [Subscription] = []
    private var categoriesCache: [SubscriptionCategory] = []

    // MARK: - App Store

    func getAppStoreSubscriptions() async throws -> [Subscription] {
        var subscriptions: [Subscription] = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable {
                    let subscription = Subscription(
                        name: transaction.productID,
                        provider: "App Store",
                        price: 0, // Would need to lookup from products
                        billingCycle: .monthly,
                        category: .appStore,
                        startDate: transaction.purchaseDate,
                        nextBillingDate: transaction.expirationDate,
                        isActive: transaction.revocationDate == nil,
                        appStoreProductId: transaction.productID
                    )
                    subscriptions.append(subscription)
                }
            }
        }

        return subscriptions
    }

    // MARK: - Manual Subscriptions

    func addSubscription(_ subscription: Subscription) async {
        subscriptionsCache.append(subscription)
    }

    func updateSubscription(_ subscription: Subscription) async {
        if let index = subscriptionsCache.firstIndex(where: { $0.id == subscription.id }) {
            subscriptionsCache[index] = subscription
        }
    }

    func removeSubscription(id: UUID) async {
        subscriptionsCache.removeAll { $0.id == id }
    }

    func cancelSubscription(id: UUID) async {
        if let index = subscriptionsCache.firstIndex(where: { $0.id == id }) {
            subscriptionsCache[index].isActive = false
            subscriptionsCache[index].cancelledDate = Date()
        }
    }

    // MARK: - Queries

    func getAllSubscriptions() async -> [Subscription] {
        subscriptionsCache.sorted { $0.nextBillingDate ?? Date.distantFuture < $1.nextBillingDate ?? Date.distantFuture }
    }

    func getActiveSubscriptions() async -> [Subscription] {
        subscriptionsCache.filter { $0.isActive }
    }

    func getSubscription(id: UUID) async -> Subscription? {
        subscriptionsCache.first { $0.id == id }
    }

    func searchSubscriptions(query: String) async -> [Subscription] {
        let queryLower = query.lowercased()
        return subscriptionsCache.filter {
            $0.name.lowercased().contains(queryLower) ||
            $0.provider.lowercased().contains(queryLower)
        }
    }

    func getSubscriptions(category: SubscriptionCategory) async -> [Subscription] {
        subscriptionsCache.filter { $0.category == category }
    }

    func getUpcomingRenewals(days: Int = 7) async -> [Subscription] {
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!

        return subscriptionsCache.filter { subscription in
            guard subscription.isActive,
                  let nextBilling = subscription.nextBillingDate else {
                return false
            }
            return nextBilling >= Date() && nextBilling <= futureDate
        }.sorted { ($0.nextBillingDate ?? Date()) < ($1.nextBillingDate ?? Date()) }
    }

    // MARK: - Analytics

    func getMonthlyTotal() async -> Double {
        subscriptionsCache.filter { $0.isActive }.reduce(0) { total, subscription in
            total + subscription.monthlyEquivalent
        }
    }

    func getYearlyTotal() async -> Double {
        await getMonthlyTotal() * 12
    }

    func getCategoryBreakdown() async -> [SubscriptionCategory: Double] {
        var breakdown: [SubscriptionCategory: Double] = [:]

        for subscription in subscriptionsCache where subscription.isActive {
            let category = subscription.category
            breakdown[category, default: 0] += subscription.monthlyEquivalent
        }

        return breakdown
    }

    func getSpendingTrend(months: Int = 6) async -> [MonthlySpending] {
        var spending: [MonthlySpending] = []
        let calendar = Calendar.current

        for monthOffset in (0..<months).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -monthOffset, to: Date()) else { continue }

            let components = calendar.dateComponents([.year, .month], from: date)
            guard let startOfMonth = calendar.date(from: components),
                  let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
                continue
            }

            var monthTotal: Double = 0

            for subscription in subscriptionsCache where subscription.isActive {
                guard let startDate = subscription.startDate else { continue }

                // Check if subscription was active during this month
                if startDate <= endOfMonth {
                    if let cancelDate = subscription.cancelledDate, cancelDate < startOfMonth {
                        continue
                    }

                    // Add monthly equivalent cost
                    monthTotal += subscription.monthlyEquivalent
                }
            }

            spending.append(MonthlySpending(
                month: startOfMonth,
                total: monthTotal
            ))
        }

        return spending
    }

    func getMostExpensive(limit: Int = 5) async -> [Subscription] {
        Array(
            subscriptionsCache
                .filter { $0.isActive }
                .sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
                .prefix(limit)
        )
    }

    // MARK: - Email Detection

    func detectSubscriptionFromEmail(subject: String, body: String, sender: String) -> Subscription? {
        // Common subscription email patterns
        let subscriptionPatterns: [(regex: String, provider: String, category: SubscriptionCategory)] = [
            ("netflix", "Netflix", .streaming),
            ("spotify", "Spotify", .streaming),
            ("hulu", "Hulu", .streaming),
            ("disney\\+|disneyplus", "Disney+", .streaming),
            ("hbo\\s*max", "HBO Max", .streaming),
            ("apple\\s*(music|tv|one|arcade|icloud)", "Apple", .appStore),
            ("amazon\\s*prime", "Amazon Prime", .shopping),
            ("youtube\\s*(premium|music)", "YouTube", .streaming),
            ("audible", "Audible", .streaming),
            ("adobe", "Adobe", .productivity),
            ("microsoft\\s*(365|office)", "Microsoft 365", .productivity),
            ("dropbox", "Dropbox", .productivity),
            ("1password", "1Password", .productivity),
            ("lastpass", "LastPass", .productivity),
            ("slack", "Slack", .productivity),
            ("notion", "Notion", .productivity),
            ("figma", "Figma", .productivity),
            ("gym|fitness|planet\\s*fitness|equinox", "Gym", .health),
            ("headspace|calm", "Meditation App", .health),
            ("nytimes|new\\s*york\\s*times", "NY Times", .news),
            ("wall\\s*street\\s*journal|wsj", "WSJ", .news),
            ("washington\\s*post", "Washington Post", .news),
            ("the\\s*athletic", "The Athletic", .news)
        ]

        let fullText = "\(subject) \(body) \(sender)".lowercased()

        for (pattern, provider, category) in subscriptionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)) != nil {

                // Try to extract price
                let price = extractPrice(from: body)

                return Subscription(
                    name: provider,
                    provider: provider,
                    price: price ?? 0,
                    billingCycle: detectBillingCycle(from: body),
                    category: category,
                    startDate: Date(),
                    isActive: true
                )
            }
        }

        return nil
    }

    private func extractPrice(from text: String) -> Double? {
        let patterns = [
            "\\$([0-9]+\\.?[0-9]*)",
            "([0-9]+\\.?[0-9]*)\\s*(?:USD|usd|dollars?)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return Double(text[range])
            }
        }

        return nil
    }

    private func detectBillingCycle(from text: String) -> BillingCycle {
        let lower = text.lowercased()

        if lower.contains("annual") || lower.contains("yearly") || lower.contains("per year") || lower.contains("/year") {
            return .yearly
        }
        if lower.contains("quarterly") || lower.contains("every 3 months") {
            return .quarterly
        }
        if lower.contains("weekly") || lower.contains("per week") {
            return .weekly
        }

        return .monthly
    }

    // MARK: - Reminders

    func getSubscriptionsNeedingAttention() async -> [SubscriptionAlert] {
        var alerts: [SubscriptionAlert] = []
        let calendar = Calendar.current

        for subscription in subscriptionsCache where subscription.isActive {
            // Free trial ending soon
            if let trialEnd = subscription.trialEndDate,
               trialEnd > Date(),
               let daysUntil = calendar.dateComponents([.day], from: Date(), to: trialEnd).day,
               daysUntil <= 3 {
                alerts.append(SubscriptionAlert(
                    subscription: subscription,
                    type: .trialEnding,
                    message: "\(subscription.name) free trial ends in \(daysUntil) day(s)"
                ))
            }

            // Price increase detected (would need history tracking)

            // Upcoming renewal
            if let nextBilling = subscription.nextBillingDate,
               let daysUntil = calendar.dateComponents([.day], from: Date(), to: nextBilling).day,
               daysUntil <= 7 && daysUntil > 0 {
                alerts.append(SubscriptionAlert(
                    subscription: subscription,
                    type: .upcomingRenewal,
                    message: "\(subscription.name) renews in \(daysUntil) day(s) for $\(String(format: "%.2f", subscription.price))"
                ))
            }

            // Unused subscription (would need usage tracking)
        }

        return alerts
    }

    // MARK: - Import/Export

    func exportSubscriptions() async -> Data? {
        try? JSONEncoder().encode(subscriptionsCache)
    }

    func importSubscriptions(from data: Data) async throws {
        let imported = try JSONDecoder().decode([Subscription].self, from: data)
        subscriptionsCache.append(contentsOf: imported)
    }
}

// MARK: - Models

struct Subscription: Identifiable, Codable {
    let id: UUID
    var name: String
    var provider: String
    var price: Double
    var billingCycle: BillingCycle
    var category: SubscriptionCategory
    var startDate: Date?
    var nextBillingDate: Date?
    var trialEndDate: Date?
    var cancelledDate: Date?
    var isActive: Bool
    var notes: String?
    var appStoreProductId: String?
    var websiteUrl: String?
    var cancellationUrl: String?

    init(
        id: UUID = UUID(),
        name: String,
        provider: String,
        price: Double,
        billingCycle: BillingCycle,
        category: SubscriptionCategory,
        startDate: Date? = nil,
        nextBillingDate: Date? = nil,
        trialEndDate: Date? = nil,
        cancelledDate: Date? = nil,
        isActive: Bool = true,
        notes: String? = nil,
        appStoreProductId: String? = nil,
        websiteUrl: String? = nil,
        cancellationUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.price = price
        self.billingCycle = billingCycle
        self.category = category
        self.startDate = startDate
        self.nextBillingDate = nextBillingDate
        self.trialEndDate = trialEndDate
        self.cancelledDate = cancelledDate
        self.isActive = isActive
        self.notes = notes
        self.appStoreProductId = appStoreProductId
        self.websiteUrl = websiteUrl
        self.cancellationUrl = cancellationUrl
    }

    var monthlyEquivalent: Double {
        switch billingCycle {
        case .weekly: return price * 4.33
        case .monthly: return price
        case .quarterly: return price / 3
        case .yearly: return price / 12
        }
    }

    var yearlyEquivalent: Double {
        monthlyEquivalent * 12
    }

    var isInTrial: Bool {
        guard let trialEnd = trialEndDate else { return false }
        return trialEnd > Date()
    }
}

enum BillingCycle: String, Codable, CaseIterable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }
}

enum SubscriptionCategory: String, Codable, CaseIterable {
    case streaming
    case productivity
    case shopping
    case health
    case news
    case gaming
    case appStore
    case utilities
    case finance
    case education
    case other

    var displayName: String {
        switch self {
        case .streaming: return "Streaming"
        case .productivity: return "Productivity"
        case .shopping: return "Shopping"
        case .health: return "Health & Fitness"
        case .news: return "News & Media"
        case .gaming: return "Gaming"
        case .appStore: return "App Store"
        case .utilities: return "Utilities"
        case .finance: return "Finance"
        case .education: return "Education"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .streaming: return "play.tv"
        case .productivity: return "briefcase"
        case .shopping: return "cart"
        case .health: return "heart"
        case .news: return "newspaper"
        case .gaming: return "gamecontroller"
        case .appStore: return "apple.logo"
        case .utilities: return "wrench.and.screwdriver"
        case .finance: return "dollarsign.circle"
        case .education: return "book"
        case .other: return "square.grid.2x2"
        }
    }
}

struct MonthlySpending: Identifiable {
    let id: UUID = UUID()
    let month: Date
    let total: Double

    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: month)
    }
}

struct SubscriptionAlert: Identifiable {
    let id: UUID = UUID()
    let subscription: Subscription
    let type: AlertType
    let message: String

    enum AlertType {
        case trialEnding
        case upcomingRenewal
        case priceIncrease
        case unused
    }
}
