import Foundation

/// Subscription tracking model
struct Subscription: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var category: SubscriptionCategory
    var provider: String

    var cost: Decimal
    var currency: String
    var billingCycle: BillingCycle

    var startDate: Date
    var nextBillingDate: Date
    var cancellationDate: Date?

    var paymentMethod: String?
    var accountEmail: String?

    var isActive: Bool
    var autoRenew: Bool

    var notes: String?
    var websiteUrl: String?
    var appStoreManaged: Bool // Managed through App Store

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: SubscriptionCategory = .other,
        provider: String,
        cost: Decimal,
        currency: String = "USD",
        billingCycle: BillingCycle = .monthly,
        startDate: Date = Date(),
        nextBillingDate: Date,
        cancellationDate: Date? = nil,
        paymentMethod: String? = nil,
        accountEmail: String? = nil,
        isActive: Bool = true,
        autoRenew: Bool = true,
        notes: String? = nil,
        websiteUrl: String? = nil,
        appStoreManaged: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.provider = provider
        self.cost = cost
        self.currency = currency
        self.billingCycle = billingCycle
        self.startDate = startDate
        self.nextBillingDate = nextBillingDate
        self.cancellationDate = cancellationDate
        self.paymentMethod = paymentMethod
        self.accountEmail = accountEmail
        self.isActive = isActive
        self.autoRenew = autoRenew
        self.notes = notes
        self.websiteUrl = websiteUrl
        self.appStoreManaged = appStoreManaged
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var monthlyEquivalent: Decimal {
        switch billingCycle {
        case .weekly: return cost * 52 / 12
        case .monthly: return cost
        case .quarterly: return cost / 3
        case .semiannually: return cost / 6
        case .annually: return cost / 12
        case .custom: return cost
        }
    }

    var annualCost: Decimal {
        switch billingCycle {
        case .weekly: return cost * 52
        case .monthly: return cost * 12
        case .quarterly: return cost * 4
        case .semiannually: return cost * 2
        case .annually: return cost
        case .custom: return cost * 12 // Assume monthly
        }
    }

    var daysUntilRenewal: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: nextBillingDate).day ?? 0
    }

    var isRenewingSoon: Bool {
        daysUntilRenewal <= 7 && isActive
    }

    var displayCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: cost as NSNumber) ?? "\(cost)"
    }
}

enum SubscriptionCategory: String, Codable, CaseIterable {
    case streaming
    case music
    case gaming
    case productivity
    case cloud
    case fitness
    case news
    case education
    case software
    case shopping
    case finance
    case social
    case utilities
    case other

    var icon: String {
        switch self {
        case .streaming: return "play.tv.fill"
        case .music: return "music.note"
        case .gaming: return "gamecontroller.fill"
        case .productivity: return "doc.text.fill"
        case .cloud: return "icloud.fill"
        case .fitness: return "figure.run"
        case .news: return "newspaper.fill"
        case .education: return "book.fill"
        case .software: return "app.fill"
        case .shopping: return "bag.fill"
        case .finance: return "dollarsign.circle.fill"
        case .social: return "person.2.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
}

enum BillingCycle: String, Codable {
    case weekly
    case monthly
    case quarterly
    case semiannually
    case annually
    case custom

    var displayText: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiannually: return "Every 6 months"
        case .annually: return "Annually"
        case .custom: return "Custom"
        }
    }

    var shortText: String {
        switch self {
        case .weekly: return "/wk"
        case .monthly: return "/mo"
        case .quarterly: return "/qtr"
        case .semiannually: return "/6mo"
        case .annually: return "/yr"
        case .custom: return ""
        }
    }
}

/// Subscription analytics
struct SubscriptionAnalytics: Codable {
    var totalMonthly: Decimal
    var totalAnnual: Decimal
    var activeCount: Int
    var byCategory: [SubscriptionCategory: Decimal]
    var upcomingRenewals: [Subscription]
    var potentialSavings: Decimal?
    var duplicateServices: [(String, [Subscription])]
}
