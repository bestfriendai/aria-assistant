import Foundation

/// Shopping order from Instacart
struct ShoppingOrder: Identifiable, Codable, Hashable {
    let id: UUID
    let instacartOrderId: String

    var status: OrderStatus
    var items: [OrderItem]

    var storeName: String
    var storeId: String

    var subtotal: Decimal
    var serviceFee: Decimal
    var deliveryFee: Decimal
    var tip: Decimal
    var tax: Decimal
    var total: Decimal

    var deliveryAddress: String
    var deliveryInstructions: String?

    var scheduledDeliveryStart: Date?
    var scheduledDeliveryEnd: Date?
    var estimatedDeliveryTime: Date?
    var actualDeliveryTime: Date?

    var shopperName: String?
    var shopperPhotoUrl: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        instacartOrderId: String,
        status: OrderStatus = .pending,
        items: [OrderItem] = [],
        storeName: String,
        storeId: String,
        subtotal: Decimal = 0,
        serviceFee: Decimal = 0,
        deliveryFee: Decimal = 0,
        tip: Decimal = 0,
        tax: Decimal = 0,
        total: Decimal = 0,
        deliveryAddress: String,
        deliveryInstructions: String? = nil,
        scheduledDeliveryStart: Date? = nil,
        scheduledDeliveryEnd: Date? = nil,
        estimatedDeliveryTime: Date? = nil,
        actualDeliveryTime: Date? = nil,
        shopperName: String? = nil,
        shopperPhotoUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.instacartOrderId = instacartOrderId
        self.status = status
        self.items = items
        self.storeName = storeName
        self.storeId = storeId
        self.subtotal = subtotal
        self.serviceFee = serviceFee
        self.deliveryFee = deliveryFee
        self.tip = tip
        self.tax = tax
        self.total = total
        self.deliveryAddress = deliveryAddress
        self.deliveryInstructions = deliveryInstructions
        self.scheduledDeliveryStart = scheduledDeliveryStart
        self.scheduledDeliveryEnd = scheduledDeliveryEnd
        self.estimatedDeliveryTime = estimatedDeliveryTime
        self.actualDeliveryTime = actualDeliveryTime
        self.shopperName = shopperName
        self.shopperPhotoUrl = shopperPhotoUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var isActive: Bool {
        switch status {
        case .pending, .confirmed, .shopping, .checkout, .delivering:
            return true
        case .delivered, .cancelled:
            return false
        }
    }
}

enum OrderStatus: String, Codable, Hashable {
    case pending
    case confirmed
    case shopping
    case checkout
    case delivering
    case delivered
    case cancelled

    var displayText: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .shopping: return "Shopping"
        case .checkout: return "Checking Out"
        case .delivering: return "On the Way"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .confirmed: return "checkmark.circle"
        case .shopping: return "cart"
        case .checkout: return "creditcard"
        case .delivering: return "car"
        case .delivered: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        }
    }
}

struct OrderItem: Identifiable, Codable, Hashable {
    let id: UUID
    let productId: String
    var name: String
    var quantity: Int
    var unit: String // "each", "lb", "oz", etc.
    var unitPrice: Decimal
    var totalPrice: Decimal
    var imageUrl: String?

    var status: ItemStatus
    var replacementProductId: String?
    var replacementName: String?

    init(
        id: UUID = UUID(),
        productId: String,
        name: String,
        quantity: Int = 1,
        unit: String = "each",
        unitPrice: Decimal,
        totalPrice: Decimal? = nil,
        imageUrl: String? = nil,
        status: ItemStatus = .pending,
        replacementProductId: String? = nil,
        replacementName: String? = nil
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice ?? (unitPrice * Decimal(quantity))
        self.imageUrl = imageUrl
        self.status = status
        self.replacementProductId = replacementProductId
        self.replacementName = replacementName
    }
}

enum ItemStatus: String, Codable, Hashable {
    case pending
    case found
    case replaced
    case refunded
}

/// Shopping cart for building orders
struct ShoppingCart: Codable {
    var items: [CartItem]
    var storeId: String?
    var storeName: String?

    var isEmpty: Bool { items.isEmpty }

    var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    var estimatedTotal: Decimal {
        items.reduce(0) { $0 + $1.estimatedPrice }
    }

    mutating func add(_ item: CartItem) {
        if let index = items.firstIndex(where: { $0.productId == item.productId }) {
            items[index].quantity += item.quantity
        } else {
            items.append(item)
        }
    }

    mutating func remove(productId: String) {
        items.removeAll { $0.productId == productId }
    }

    mutating func clear() {
        items.removeAll()
    }
}

struct CartItem: Identifiable, Codable, Hashable {
    let id: UUID
    let productId: String
    var name: String
    var quantity: Int
    var unit: String
    var estimatedPrice: Decimal
    var imageUrl: String?

    init(
        id: UUID = UUID(),
        productId: String,
        name: String,
        quantity: Int = 1,
        unit: String = "each",
        estimatedPrice: Decimal,
        imageUrl: String? = nil
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.estimatedPrice = estimatedPrice
        self.imageUrl = imageUrl
    }
}

/// Purchase pattern for suggestions
struct PurchasePattern: Codable {
    let productId: String
    let productName: String
    var averageFrequencyDays: Int
    var lastPurchaseDate: Date
    var averageQuantity: Int
    var totalPurchases: Int

    var daysSinceLastPurchase: Int {
        Calendar.current.dateComponents([.day], from: lastPurchaseDate, to: Date()).day ?? 0
    }

    var shouldSuggestReorder: Bool {
        daysSinceLastPurchase >= averageFrequencyDays - 2
    }
}
