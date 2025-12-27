import Foundation

/// Shopping service for Instacart integration
actor ShoppingService {
    // MARK: - Configuration

    private var apiKey: String?
    private var baseURL = URL(string: "https://api.instacart.com/v1")!

    // MARK: - State

    private var currentCart = ShoppingCart(items: [])
    private var purchaseHistory: [PurchasePattern] = []

    // MARK: - Configuration

    func configure(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Product Search

    func searchProducts(query: String, storeId: String? = nil) async throws -> [Product] {
        guard apiKey != nil else {
            throw ShoppingServiceError.notConfigured
        }

        // Instacart API call
        // This is a placeholder - actual implementation requires Instacart Developer Platform access
        return []
    }

    func getProductDetails(productId: String) async throws -> Product {
        guard apiKey != nil else {
            throw ShoppingServiceError.notConfigured
        }

        // Instacart API call
        throw ShoppingServiceError.productNotFound
    }

    // MARK: - Store

    func getNearbyStores(latitude: Double, longitude: Double) async throws -> [Store] {
        // Instacart API call
        return []
    }

    func getPreferredStore() async -> Store? {
        // Load from preferences
        return nil
    }

    // MARK: - Cart Management

    func getCart() -> ShoppingCart {
        currentCart
    }

    func addToCart(productId: String, name: String, quantity: Int = 1, price: Decimal) async throws {
        let item = CartItem(
            productId: productId,
            name: name,
            quantity: quantity,
            unit: "each",
            estimatedPrice: price * Decimal(quantity)
        )

        currentCart.add(item)
    }

    func removeFromCart(productId: String) async {
        currentCart.remove(productId: productId)
    }

    func updateQuantity(productId: String, quantity: Int) async throws {
        guard let index = currentCart.items.firstIndex(where: { $0.productId == productId }) else {
            throw ShoppingServiceError.itemNotInCart
        }

        if quantity <= 0 {
            currentCart.items.remove(at: index)
        } else {
            currentCart.items[index].quantity = quantity
            let unitPrice = currentCart.items[index].estimatedPrice / Decimal(currentCart.items[index].quantity)
            currentCart.items[index].estimatedPrice = unitPrice * Decimal(quantity)
        }
    }

    func clearCart() async {
        currentCart.clear()
    }

    // MARK: - Checkout

    func checkout(
        deliveryAddress: String,
        scheduledTime: Date? = nil,
        tip: Decimal = 0
    ) async throws -> ShoppingOrder {
        guard apiKey != nil else {
            throw ShoppingServiceError.notConfigured
        }

        guard !currentCart.isEmpty else {
            throw ShoppingServiceError.emptyCart
        }

        // Create order via Instacart API
        let order = ShoppingOrder(
            instacartOrderId: UUID().uuidString,
            status: .pending,
            items: currentCart.items.map { cartItem in
                OrderItem(
                    productId: cartItem.productId,
                    name: cartItem.name,
                    quantity: cartItem.quantity,
                    unit: cartItem.unit,
                    unitPrice: cartItem.estimatedPrice / Decimal(cartItem.quantity)
                )
            },
            storeName: currentCart.storeName ?? "Grocery Store",
            storeId: currentCart.storeId ?? "",
            subtotal: currentCart.estimatedTotal,
            serviceFee: currentCart.estimatedTotal * Decimal(0.05),
            deliveryFee: Decimal(3.99),
            tip: tip,
            tax: currentCart.estimatedTotal * Decimal(0.08),
            total: currentCart.estimatedTotal * Decimal(1.13) + tip + Decimal(3.99),
            deliveryAddress: deliveryAddress,
            scheduledDeliveryStart: scheduledTime,
            scheduledDeliveryEnd: scheduledTime?.addingTimeInterval(7200) // 2 hour window
        )

        // Clear cart after successful order
        await clearCart()

        // Record purchase for patterns
        await recordPurchase(order)

        return order
    }

    // MARK: - Order Tracking

    func getActiveOrders() async throws -> [ShoppingOrder] {
        guard apiKey != nil else {
            throw ShoppingServiceError.notConfigured
        }

        // Fetch from Instacart API
        return []
    }

    func getOrderStatus(orderId: String) async throws -> ShoppingOrder {
        guard apiKey != nil else {
            throw ShoppingServiceError.notConfigured
        }

        // Fetch from Instacart API
        throw ShoppingServiceError.orderNotFound
    }

    func getOrderHistory(limit: Int = 20) async throws -> [ShoppingOrder] {
        // Fetch from local database + Instacart API
        return []
    }

    // MARK: - Reorder

    func reorderLastOrder() async throws -> ShoppingCart {
        let orders = try await getOrderHistory(limit: 1)

        guard let lastOrder = orders.first else {
            throw ShoppingServiceError.noOrderHistory
        }

        return try await prepareReorder(from: lastOrder)
    }

    func prepareReorder(from order: ShoppingOrder) async throws -> ShoppingCart {
        var cart = ShoppingCart(items: [], storeId: order.storeId, storeName: order.storeName)

        for item in order.items {
            cart.add(CartItem(
                productId: item.productId,
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                estimatedPrice: item.totalPrice
            ))
        }

        currentCart = cart
        return cart
    }

    // MARK: - Purchase Patterns

    func getSuggestedReorders() async throws -> [PurchasePattern] {
        purchaseHistory.filter { $0.shouldSuggestReorder }
    }

    func getFrequentItems(limit: Int = 10) async throws -> [PurchasePattern] {
        purchaseHistory
            .sorted { $0.totalPurchases > $1.totalPurchases }
            .prefix(limit)
            .map { $0 }
    }

    private func recordPurchase(_ order: ShoppingOrder) async {
        for item in order.items {
            if let index = purchaseHistory.firstIndex(where: { $0.productId == item.productId }) {
                // Update existing pattern
                let existing = purchaseHistory[index]
                let daysSinceLast = existing.daysSinceLastPurchase

                purchaseHistory[index] = PurchasePattern(
                    productId: item.productId,
                    productName: item.name,
                    averageFrequencyDays: (existing.averageFrequencyDays * existing.totalPurchases + daysSinceLast) / (existing.totalPurchases + 1),
                    lastPurchaseDate: Date(),
                    averageQuantity: (existing.averageQuantity * existing.totalPurchases + item.quantity) / (existing.totalPurchases + 1),
                    totalPurchases: existing.totalPurchases + 1
                )
            } else {
                // New pattern
                purchaseHistory.append(PurchasePattern(
                    productId: item.productId,
                    productName: item.name,
                    averageFrequencyDays: 14, // Default 2 weeks
                    lastPurchaseDate: Date(),
                    averageQuantity: item.quantity,
                    totalPurchases: 1
                ))
            }
        }
    }

    // MARK: - Recipe Shopping

    func createListFromRecipe(_ recipe: String) async throws -> [CartItem] {
        // Use Gemini to parse recipe and extract ingredients
        // Then search for products
        return []
    }
}

// MARK: - Supporting Types

struct Product: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let price: Decimal
    let unit: String
    let imageUrl: String?
    let category: String
    let inStock: Bool
}

struct Store: Identifiable, Codable {
    let id: String
    let name: String
    let address: String
    let distance: Double? // miles
    let rating: Double?
    let logoUrl: String?
}

// MARK: - Errors

enum ShoppingServiceError: Error {
    case notConfigured
    case productNotFound
    case itemNotInCart
    case emptyCart
    case orderNotFound
    case noOrderHistory
    case checkoutFailed
}
