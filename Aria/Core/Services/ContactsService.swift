import Foundation
import Contacts

/// Service for contacts with intelligence layer
actor ContactsService {
    // MARK: - Contacts Store

    private let store = CNContactStore()
    private var hasAccess = false

    // MARK: - Cache

    private var contactsCache: [AriaContact] = []
    private var lastFetchDate: Date?
    private let cacheExpiry: TimeInterval = 300 // 5 minutes

    // MARK: - Permissions

    func requestAccess() async -> Bool {
        do {
            hasAccess = try await store.requestAccess(for: .contacts)
            return hasAccess
        } catch {
            return false
        }
    }

    // MARK: - Fetch Contacts

    func getAllContacts() async throws -> [AriaContact] {
        // Check cache
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < cacheExpiry,
           !contactsCache.isEmpty {
            return contactsCache
        }

        guard hasAccess else {
            throw ContactsServiceError.accessDenied
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [AriaContact] = []

        try store.enumerateContacts(with: request) { cnContact, _ in
            let contact = self.mapContact(cnContact)
            contacts.append(contact)
        }

        // Update cache
        contactsCache = contacts
        lastFetchDate = Date()

        return contacts
    }

    private func mapContact(_ cnContact: CNContact) -> AriaContact {
        AriaContact(
            systemContactId: cnContact.identifier,
            firstName: cnContact.givenName,
            lastName: cnContact.familyName,
            nickname: cnContact.nickname.isEmpty ? nil : cnContact.nickname,
            emails: cnContact.emailAddresses.enumerated().map { index, email in
                ContactEmail(
                    email: email.value as String,
                    label: email.label ?? "other",
                    isPrimary: index == 0
                )
            },
            phones: cnContact.phoneNumbers.enumerated().map { index, phone in
                ContactPhone(
                    number: phone.value.stringValue,
                    label: phone.label ?? "other",
                    isPrimary: index == 0
                )
            },
            company: cnContact.organizationName.isEmpty ? nil : cnContact.organizationName,
            jobTitle: cnContact.jobTitle.isEmpty ? nil : cnContact.jobTitle,
            birthday: cnContact.birthday?.date,
            notes: cnContact.note.isEmpty ? nil : cnContact.note
        )
    }

    // MARK: - Search

    func searchContacts(query: String) async throws -> [AriaContact] {
        let contacts = try await getAllContacts()

        return contacts.filter { $0.matches(query: query) }
    }

    func findContact(named name: String) async throws -> AriaContact? {
        let results = try await searchContacts(query: name)
        return results.first
    }

    func findContactByEmail(_ email: String) async throws -> AriaContact? {
        let contacts = try await getAllContacts()

        return contacts.first { contact in
            contact.emails.contains { $0.email.lowercased() == email.lowercased() }
        }
    }

    func findContactByPhone(_ phone: String) async throws -> AriaContact? {
        let contacts = try await getAllContacts()
        let normalizedPhone = normalizePhoneNumber(phone)

        return contacts.first { contact in
            contact.phones.contains { normalizePhoneNumber($0.number) == normalizedPhone }
        }
    }

    private func normalizePhoneNumber(_ phone: String) -> String {
        phone.filter { $0.isNumber }
    }

    // MARK: - Intelligence

    func updateContactInteraction(_ contactId: UUID) async throws {
        // Update last contact date and interaction count
        // This would update the database
    }

    func getContactsNeedingAttention() async throws -> [AriaContact] {
        let contacts = try await getAllContacts()

        return contacts.filter { $0.shouldReachOut }
            .sorted { ($0.daysSinceLastContact ?? 0) > ($1.daysSinceLastContact ?? 0) }
    }

    func getUpcomingBirthdays(days: Int = 7) async throws -> [AriaContact] {
        let contacts = try await getAllContacts()
        let calendar = Calendar.current

        return contacts.filter { contact in
            guard let birthday = contact.birthday else { return false }

            // Get this year's birthday
            var components = calendar.dateComponents([.month, .day], from: birthday)
            components.year = calendar.component(.year, from: Date())

            guard let thisYearBirthday = calendar.date(from: components) else { return false }

            let daysUntil = calendar.dateComponents([.day], from: Date(), to: thisYearBirthday).day ?? 0
            return daysUntil >= 0 && daysUntil <= days
        }
    }

    func getFrequentContacts(limit: Int = 10) async throws -> [AriaContact] {
        let contacts = try await getAllContacts()

        return contacts
            .sorted { $0.totalInteractions > $1.totalInteractions }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Relationship Management

    func setRelationship(_ contactId: UUID, relationship: Relationship) async throws {
        // Update in database
    }

    func addContext(_ contactId: UUID, context: String) async throws {
        // Add context tag
    }
}

// MARK: - Errors

enum ContactsServiceError: Error {
    case accessDenied
    case contactNotFound
    case updateFailed
}
