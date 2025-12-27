import Foundation

/// Banking transaction from Plaid
struct Transaction: Identifiable, Codable, Hashable {
    let id: UUID
    let plaidTransactionId: String
    let accountId: String

    var name: String
    var merchantName: String?
    var amount: Decimal
    var isoCurrencyCode: String

    var date: Date
    var authorizedDate: Date?
    var postedDate: Date?

    var category: [String] // Plaid category hierarchy
    var categoryId: String?
    var primaryCategory: TransactionCategory

    var paymentChannel: PaymentChannel
    var location: TransactionLocation?

    var isPending: Bool
    var isRecurring: Bool
    var recurringTransactionId: String?

    // AI-computed
    var customCategory: String?
    var embedding: [Float]?
    var isUnusual: Bool
    var notes: String?

    init(
        id: UUID = UUID(),
        plaidTransactionId: String,
        accountId: String,
        name: String,
        merchantName: String? = nil,
        amount: Decimal,
        isoCurrencyCode: String = "USD",
        date: Date,
        authorizedDate: Date? = nil,
        postedDate: Date? = nil,
        category: [String] = [],
        categoryId: String? = nil,
        primaryCategory: TransactionCategory = .other,
        paymentChannel: PaymentChannel = .other,
        location: TransactionLocation? = nil,
        isPending: Bool = false,
        isRecurring: Bool = false,
        recurringTransactionId: String? = nil,
        customCategory: String? = nil,
        embedding: [Float]? = nil,
        isUnusual: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.plaidTransactionId = plaidTransactionId
        self.accountId = accountId
        self.name = name
        self.merchantName = merchantName
        self.amount = amount
        self.isoCurrencyCode = isoCurrencyCode
        self.date = date
        self.authorizedDate = authorizedDate
        self.postedDate = postedDate
        self.category = category
        self.categoryId = categoryId
        self.primaryCategory = primaryCategory
        self.paymentChannel = paymentChannel
        self.location = location
        self.isPending = isPending
        self.isRecurring = isRecurring
        self.recurringTransactionId = recurringTransactionId
        self.customCategory = customCategory
        self.embedding = embedding
        self.isUnusual = isUnusual
        self.notes = notes
    }

    var displayName: String {
        merchantName ?? name
    }

    var isExpense: Bool {
        amount > 0 // Plaid uses positive for expenses
    }

    var isIncome: Bool {
        amount < 0 // Plaid uses negative for income
    }

    var absoluteAmount: Decimal {
        abs(amount)
    }
}

enum TransactionCategory: String, Codable, Hashable {
    case income
    case transfer
    case loanPayments = "loan_payments"
    case bankFees = "bank_fees"
    case entertainment
    case foodAndDrink = "food_and_drink"
    case generalMerchandise = "general_merchandise"
    case groceries
    case homeImprovement = "home_improvement"
    case medical
    case personalCare = "personal_care"
    case generalServices = "general_services"
    case governmentAndNonProfit = "government_and_non_profit"
    case transportation
    case travel
    case rentAndUtilities = "rent_and_utilities"
    case other

    var icon: String {
        switch self {
        case .income: return "arrow.down.circle"
        case .transfer: return "arrow.left.arrow.right"
        case .loanPayments: return "building.columns"
        case .bankFees: return "dollarsign.circle"
        case .entertainment: return "film"
        case .foodAndDrink: return "fork.knife"
        case .generalMerchandise: return "bag"
        case .groceries: return "cart"
        case .homeImprovement: return "hammer"
        case .medical: return "cross.case"
        case .personalCare: return "figure.walk"
        case .generalServices: return "wrench.and.screwdriver"
        case .governmentAndNonProfit: return "building.2"
        case .transportation: return "car"
        case .travel: return "airplane"
        case .rentAndUtilities: return "house"
        case .other: return "questionmark.circle"
        }
    }
}

enum PaymentChannel: String, Codable, Hashable {
    case online
    case inStore = "in_store"
    case other
}

struct TransactionLocation: Codable, Hashable {
    var address: String?
    var city: String?
    var region: String?
    var postalCode: String?
    var country: String?
    var lat: Double?
    var lon: Double?
}

/// Bank account from Plaid
struct BankAccount: Identifiable, Codable, Hashable {
    let id: UUID
    let plaidAccountId: String
    let institutionId: String
    let institutionName: String

    var name: String
    var officialName: String?
    var type: AccountType
    var subtype: String?
    var mask: String? // Last 4 digits

    var currentBalance: Decimal?
    var availableBalance: Decimal?
    var limit: Decimal? // For credit cards
    var isoCurrencyCode: String

    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        plaidAccountId: String,
        institutionId: String,
        institutionName: String,
        name: String,
        officialName: String? = nil,
        type: AccountType,
        subtype: String? = nil,
        mask: String? = nil,
        currentBalance: Decimal? = nil,
        availableBalance: Decimal? = nil,
        limit: Decimal? = nil,
        isoCurrencyCode: String = "USD",
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.plaidAccountId = plaidAccountId
        self.institutionId = institutionId
        self.institutionName = institutionName
        self.name = name
        self.officialName = officialName
        self.type = type
        self.subtype = subtype
        self.mask = mask
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.limit = limit
        self.isoCurrencyCode = isoCurrencyCode
        self.lastUpdated = lastUpdated
    }

    var displayName: String {
        if let mask = mask {
            return "\(name) (\(mask))"
        }
        return name
    }

    var utilizationPercentage: Double? {
        guard type == .credit, let balance = currentBalance, let limit = limit, limit > 0 else {
            return nil
        }
        return Double(truncating: (balance / limit) as NSNumber) * 100
    }
}

enum AccountType: String, Codable, Hashable {
    case checking
    case savings
    case credit
    case loan
    case investment
    case other
}

/// Detected recurring bill
struct RecurringBill: Identifiable, Codable, Hashable {
    let id: UUID
    let merchantName: String
    let amount: Decimal
    let frequency: BillFrequency
    var nextDueDate: Date
    var lastPaidDate: Date?
    var accountId: String
    var category: TransactionCategory
    var isAutoPay: Bool

    var isUpcoming: Bool {
        let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: nextDueDate).day ?? 0
        return daysUntilDue >= 0 && daysUntilDue <= 7
    }

    var isPastDue: Bool {
        nextDueDate < Date()
    }
}

enum BillFrequency: String, Codable, Hashable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case annually
}
