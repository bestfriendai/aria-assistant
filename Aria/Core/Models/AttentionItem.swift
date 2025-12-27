import Foundation
import SwiftUI

/// Represents an item that demands the user's attention
struct AttentionItem: Identifiable, Codable, Hashable {
    let id: UUID
    let type: AttentionType
    let title: String
    let subtitle: String?
    let urgency: Double // 0-1, determines display order
    let source: DataSource
    let sourceRef: String? // ID in source system
    let actions: [QuickAction]
    let createdAt: Date
    let expiresAt: Date?

    init(
        id: UUID = UUID(),
        type: AttentionType,
        title: String,
        subtitle: String? = nil,
        urgency: Double,
        source: DataSource,
        sourceRef: String? = nil,
        actions: [QuickAction] = [],
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.urgency = min(1, max(0, urgency))
        self.source = source
        self.sourceRef = sourceRef
        self.actions = actions
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var icon: String {
        switch type {
        case .missedCall: return "phone.arrow.down.left"
        case .urgentEmail: return "envelope.badge"
        case .taskDue: return "checklist"
        case .paymentDue: return "creditcard"
        case .calendarReminder: return "calendar"
        case .deliveryUpdate: return "shippingbox"
        case .custom(let icon, _): return icon
        }
    }

    var color: Color {
        switch type {
        case .missedCall: return .orange
        case .urgentEmail: return .blue
        case .taskDue: return .purple
        case .paymentDue: return .green
        case .calendarReminder: return .red
        case .deliveryUpdate: return .teal
        case .custom(_, let color): return color
        }
    }
}

enum AttentionType: Codable, Hashable {
    case missedCall
    case urgentEmail
    case taskDue
    case paymentDue
    case calendarReminder
    case deliveryUpdate
    case custom(icon: String, color: Color)

    // Custom Codable implementation for Color
    enum CodingKeys: String, CodingKey {
        case type, icon, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "missedCall": self = .missedCall
        case "urgentEmail": self = .urgentEmail
        case "taskDue": self = .taskDue
        case "paymentDue": self = .paymentDue
        case "calendarReminder": self = .calendarReminder
        case "deliveryUpdate": self = .deliveryUpdate
        case "custom":
            let icon = try container.decode(String.self, forKey: .icon)
            let colorHex = try container.decode(String.self, forKey: .colorHex)
            self = .custom(icon: icon, color: Color(hex: colorHex) ?? .gray)
        default:
            self = .custom(icon: "questionmark.circle", color: .gray)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .missedCall: try container.encode("missedCall", forKey: .type)
        case .urgentEmail: try container.encode("urgentEmail", forKey: .type)
        case .taskDue: try container.encode("taskDue", forKey: .type)
        case .paymentDue: try container.encode("paymentDue", forKey: .type)
        case .calendarReminder: try container.encode("calendarReminder", forKey: .type)
        case .deliveryUpdate: try container.encode("deliveryUpdate", forKey: .type)
        case .custom(let icon, _):
            try container.encode("custom", forKey: .type)
            try container.encode(icon, forKey: .icon)
            try container.encode("#808080", forKey: .colorHex) // Default gray
        }
    }
}

enum DataSource: String, Codable, Hashable {
    case email
    case calendar
    case task
    case banking
    case shopping
    case contacts
    case voice
    case manual
}

struct QuickAction: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let icon: String
    let actionType: ActionType

    init(id: UUID = UUID(), title: String, icon: String, actionType: ActionType) {
        self.id = id
        self.title = title
        self.icon = icon
        self.actionType = actionType
    }

    enum ActionType: Codable, Hashable {
        case call(phoneNumber: String)
        case reply(emailId: String)
        case complete(taskId: String)
        case pay(paymentId: String)
        case open(url: String)
        case dismiss
        case snooze(duration: TimeInterval)
        case custom(action: String)
    }
}

// Color extension for hex support
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
