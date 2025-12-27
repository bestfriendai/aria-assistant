import Foundation

/// Banking service using Plaid for account aggregation
actor BankingService {
    // MARK: - Plaid Configuration

    private var plaidClientId: String?
    private var plaidSecret: String?
    private var plaidEnvironment: PlaidEnvironment = .sandbox

    private var accessTokens: [String: String] = [:] // institutionId -> accessToken

    // MARK: - Cache

    private var accountsCache: [BankAccount] = []
    private var transactionsCache: [Transaction] = []
    private var lastRefresh: Date?

    // MARK: - Configuration

    func configure(clientId: String, secret: String, environment: PlaidEnvironment = .sandbox) {
        self.plaidClientId = clientId
        self.plaidSecret = secret
        self.plaidEnvironment = environment
    }

    // MARK: - Link

    /// Get link token to start Plaid Link flow
    func getLinkToken() async throws -> String {
        guard let clientId = plaidClientId, let secret = plaidSecret else {
            throw BankingServiceError.notConfigured
        }

        // Call Plaid API to get link token
        let url = plaidEnvironment.baseURL.appendingPathComponent("/link/token/create")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": clientId,
            "secret": secret,
            "user": ["client_user_id": UUID().uuidString],
            "client_name": "Aria",
            "products": ["transactions"],
            "country_codes": ["US"],
            "language": "en"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(PlaidLinkTokenResponse.self, from: data)

        return response.linkToken
    }

    /// Exchange public token from Plaid Link for access token
    func exchangePublicToken(_ publicToken: String, institutionId: String) async throws {
        guard let clientId = plaidClientId, let secret = plaidSecret else {
            throw BankingServiceError.notConfigured
        }

        let url = plaidEnvironment.baseURL.appendingPathComponent("/item/public_token/exchange")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": clientId,
            "secret": secret,
            "public_token": publicToken
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(PlaidExchangeResponse.self, from: data)

        accessTokens[institutionId] = response.accessToken
    }

    // MARK: - Accounts

    func getAccounts() async throws -> [BankAccount] {
        var allAccounts: [BankAccount] = []

        for (institutionId, accessToken) in accessTokens {
            let accounts = try await fetchAccounts(accessToken: accessToken, institutionId: institutionId)
            allAccounts.append(contentsOf: accounts)
        }

        accountsCache = allAccounts
        return allAccounts
    }

    private func fetchAccounts(accessToken: String, institutionId: String) async throws -> [BankAccount] {
        guard let clientId = plaidClientId, let secret = plaidSecret else {
            throw BankingServiceError.notConfigured
        }

        let url = plaidEnvironment.baseURL.appendingPathComponent("/accounts/get")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": clientId,
            "secret": secret,
            "access_token": accessToken
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        // Parse response and map to BankAccount
        // Simplified for now
        return []
    }

    func getTotalBalance() async throws -> Decimal {
        let accounts = try await getAccounts()

        return accounts
            .filter { $0.type == .checking || $0.type == .savings }
            .compactMap { $0.availableBalance ?? $0.currentBalance }
            .reduce(0, +)
    }

    // MARK: - Transactions

    func getTransactions(
        accountId: String? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        limit: Int = 100
    ) async throws -> [Transaction] {
        var allTransactions: [Transaction] = []

        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let end = endDate ?? Date()

        for (_, accessToken) in accessTokens {
            let transactions = try await fetchTransactions(
                accessToken: accessToken,
                startDate: start,
                endDate: end
            )
            allTransactions.append(contentsOf: transactions)
        }

        // Filter by account if specified
        if let accountId = accountId {
            allTransactions = allTransactions.filter { $0.accountId == accountId }
        }

        // Sort by date descending
        allTransactions.sort { $0.date > $1.date }

        transactionsCache = allTransactions
        return Array(allTransactions.prefix(limit))
    }

    private func fetchTransactions(
        accessToken: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [Transaction] {
        // Plaid API call
        return []
    }

    func getRecentTransactions(limit: Int = 10) async throws -> [Transaction] {
        try await getTransactions(limit: limit)
    }

    // MARK: - Spending Analysis

    func getSpending(
        category: TransactionCategory? = nil,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async throws -> Decimal {
        let transactions = try await getTransactions(from: startDate, to: endDate)

        var filtered = transactions.filter { $0.isExpense }

        if let category = category {
            filtered = filtered.filter { $0.primaryCategory == category }
        }

        return filtered.map { $0.absoluteAmount }.reduce(0, +)
    }

    func getSpendingByCategory(
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) async throws -> [TransactionCategory: Decimal] {
        let transactions = try await getTransactions(from: startDate, to: endDate)
            .filter { $0.isExpense }

        var byCategory: [TransactionCategory: Decimal] = [:]

        for transaction in transactions {
            byCategory[transaction.primaryCategory, default: 0] += transaction.absoluteAmount
        }

        return byCategory
    }

    // MARK: - Bill Detection

    func detectRecurringBills() async throws -> [RecurringBill] {
        let transactions = try await getTransactions(limit: 500)

        // Group by merchant
        var byMerchant: [String: [Transaction]] = [:]
        for transaction in transactions {
            let key = transaction.merchantName ?? transaction.name
            byMerchant[key, default: []].append(transaction)
        }

        // Find recurring patterns
        var bills: [RecurringBill] = []

        for (merchant, merchantTransactions) in byMerchant {
            guard merchantTransactions.count >= 2 else { continue }

            let sorted = merchantTransactions.sorted { $0.date < $1.date }
            let intervals = zip(sorted, sorted.dropFirst()).map { next, prev in
                Calendar.current.dateComponents([.day], from: prev.date, to: next.date).day ?? 0
            }

            // Check for monthly pattern (25-35 days)
            let avgInterval = intervals.reduce(0, +) / max(1, intervals.count)
            if avgInterval >= 25 && avgInterval <= 35 {
                let avgAmount = merchantTransactions.map { $0.absoluteAmount }.reduce(0, +) / Decimal(merchantTransactions.count)

                let bill = RecurringBill(
                    id: UUID(),
                    merchantName: merchant,
                    amount: avgAmount,
                    frequency: .monthly,
                    nextDueDate: Calendar.current.date(
                        byAdding: .day,
                        value: avgInterval,
                        to: sorted.last!.date
                    )!,
                    lastPaidDate: sorted.last?.date,
                    accountId: sorted.last?.accountId ?? "",
                    category: sorted.last?.primaryCategory ?? .other,
                    isAutoPay: true
                )
                bills.append(bill)
            }
        }

        return bills
    }

    func getUpcomingBills(days: Int = 7) async throws -> [RecurringBill] {
        let bills = try await detectRecurringBills()

        return bills.filter { $0.isUpcoming }
    }

    // MARK: - Alerts

    func getUnusualTransactions(threshold: Decimal = 500) async throws -> [Transaction] {
        let transactions = try await getRecentTransactions(limit: 50)

        return transactions.filter { $0.absoluteAmount >= threshold || $0.isUnusual }
    }

    func checkLowBalance(threshold: Decimal = 100) async throws -> [BankAccount] {
        let accounts = try await getAccounts()

        return accounts.filter { account in
            guard let balance = account.availableBalance ?? account.currentBalance else {
                return false
            }
            return balance < threshold && account.type == .checking
        }
    }
}

// MARK: - Plaid Types

enum PlaidEnvironment {
    case sandbox
    case development
    case production

    var baseURL: URL {
        switch self {
        case .sandbox:
            return URL(string: "https://sandbox.plaid.com")!
        case .development:
            return URL(string: "https://development.plaid.com")!
        case .production:
            return URL(string: "https://production.plaid.com")!
        }
    }
}

struct PlaidLinkTokenResponse: Decodable {
    let linkToken: String

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
    }
}

struct PlaidExchangeResponse: Decodable {
    let accessToken: String
    let itemId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case itemId = "item_id"
    }
}

// MARK: - Errors

enum BankingServiceError: Error {
    case notConfigured
    case authenticationFailed
    case accountNotFound
    case fetchFailed
}
