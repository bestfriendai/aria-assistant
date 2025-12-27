import Foundation

/// Extended contact model with intelligence layer
struct AriaContact: Identifiable, Codable, Hashable {
    let id: UUID
    let systemContactId: String? // iOS Contacts identifier

    var firstName: String
    var lastName: String
    var nickname: String?

    var emails: [ContactEmail]
    var phones: [ContactPhone]

    var company: String?
    var jobTitle: String?

    var birthday: Date?
    var anniversary: Date?

    var notes: String?
    var tags: [String]

    // Intelligence layer
    var relationship: Relationship
    var communicationFrequency: CommunicationFrequency
    var preferredContactMethod: ContactMethod
    var lastContactDate: Date?
    var totalInteractions: Int

    // Context awareness
    var contexts: [String] // "work", "family", "friend", etc.
    var embedding: [Float]?

    init(
        id: UUID = UUID(),
        systemContactId: String? = nil,
        firstName: String,
        lastName: String,
        nickname: String? = nil,
        emails: [ContactEmail] = [],
        phones: [ContactPhone] = [],
        company: String? = nil,
        jobTitle: String? = nil,
        birthday: Date? = nil,
        anniversary: Date? = nil,
        notes: String? = nil,
        tags: [String] = [],
        relationship: Relationship = .acquaintance,
        communicationFrequency: CommunicationFrequency = .occasional,
        preferredContactMethod: ContactMethod = .email,
        lastContactDate: Date? = nil,
        totalInteractions: Int = 0,
        contexts: [String] = [],
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.systemContactId = systemContactId
        self.firstName = firstName
        self.lastName = lastName
        self.nickname = nickname
        self.emails = emails
        self.phones = phones
        self.company = company
        self.jobTitle = jobTitle
        self.birthday = birthday
        self.anniversary = anniversary
        self.notes = notes
        self.tags = tags
        self.relationship = relationship
        self.communicationFrequency = communicationFrequency
        self.preferredContactMethod = preferredContactMethod
        self.lastContactDate = lastContactDate
        self.totalInteractions = totalInteractions
        self.contexts = contexts
        self.embedding = embedding
    }

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var displayName: String {
        nickname ?? fullName
    }

    var primaryEmail: String? {
        emails.first(where: { $0.isPrimary })?.email ?? emails.first?.email
    }

    var primaryPhone: String? {
        phones.first(where: { $0.isPrimary })?.number ?? phones.first?.number
    }

    /// Days since last contact
    var daysSinceLastContact: Int? {
        guard let lastContact = lastContactDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day
    }

    /// Check if we should suggest reaching out
    var shouldReachOut: Bool {
        guard let days = daysSinceLastContact else { return false }
        let threshold: Int = switch communicationFrequency {
        case .daily: 3
        case .weekly: 10
        case .biweekly: 21
        case .monthly: 45
        case .occasional: 90
        case .rare: 180
        }
        return days > threshold
    }
}

struct ContactEmail: Codable, Hashable {
    let email: String
    var label: String // home, work, other
    var isPrimary: Bool
}

struct ContactPhone: Codable, Hashable {
    let number: String
    var label: String // mobile, home, work
    var isPrimary: Bool
}

enum Relationship: String, Codable, Hashable, CaseIterable {
    case family
    case closeFriend = "close_friend"
    case friend
    case colleague
    case professional
    case acquaintance
    case other

    var importance: Double {
        switch self {
        case .family: return 1.0
        case .closeFriend: return 0.9
        case .friend: return 0.7
        case .colleague: return 0.6
        case .professional: return 0.5
        case .acquaintance: return 0.3
        case .other: return 0.2
        }
    }
}

enum CommunicationFrequency: String, Codable, Hashable {
    case daily
    case weekly
    case biweekly
    case monthly
    case occasional
    case rare
}

enum ContactMethod: String, Codable, Hashable {
    case call
    case text
    case email
    case other
}

// MARK: - Matching
extension AriaContact {
    /// Match contact by name (fuzzy matching)
    func matches(query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return fullName.lowercased().contains(lowercasedQuery)
            || (nickname?.lowercased().contains(lowercasedQuery) ?? false)
            || emails.contains { $0.email.lowercased().contains(lowercasedQuery) }
    }
}
