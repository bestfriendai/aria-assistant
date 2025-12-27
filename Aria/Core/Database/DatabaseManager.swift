import Foundation
import GRDB

/// Central database manager for Aria
/// Uses GRDB with SQLCipher for encrypted storage
actor DatabaseManager {
    static let shared = DatabaseManager()

    private var dbPool: DatabasePool?

    private init() {}

    // MARK: - Initialization

    func initialize() async throws {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dbDirectory = appSupport.appendingPathComponent("Aria", isDirectory: true)
        try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)

        let dbPath = dbDirectory.appendingPathComponent("aria.db").path

        // Configure for SQLCipher encryption
        var config = Configuration()
        config.prepareDatabase { db in
            // Would use SQLCipher key here in production
            // try db.usePassphrase("encryption-key-from-keychain")
        }

        dbPool = try DatabasePool(path: dbPath, configuration: config)

        // Run migrations
        try await migrate()
    }

    // MARK: - Migrations

    private func migrate() async throws {
        guard let dbPool = dbPool else { return }

        var migrator = DatabaseMigrator()

        // v1: Initial schema
        migrator.registerMigration("v1") { db in
            // Tasks table
            try db.create(table: "tasks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("source", .text).notNull()
                t.column("source_ref", .text)
                t.column("due_date", .datetime)
                t.column("priority", .integer).notNull().defaults(to: 50)
                t.column("context", .text) // JSON array
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("embedding", .blob)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("completed_at", .datetime)
            }

            // Emails table
            try db.create(table: "emails") { t in
                t.column("id", .text).primaryKey()
                t.column("provider", .text).notNull()
                t.column("provider_message_id", .text).notNull()
                t.column("thread_id", .text)
                t.column("from_email", .text).notNull()
                t.column("from_name", .text)
                t.column("to_addresses", .text) // JSON
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("body", .text)
                t.column("is_read", .boolean).notNull().defaults(to: false)
                t.column("is_starred", .boolean).notNull().defaults(to: false)
                t.column("is_archived", .boolean).notNull().defaults(to: false)
                t.column("labels", .text) // JSON array
                t.column("has_attachments", .boolean).notNull().defaults(to: false)
                t.column("received_at", .datetime).notNull()
                t.column("priority_score", .integer).notNull().defaults(to: 50)
                t.column("embedding", .blob)
                t.column("requires_response", .boolean).notNull().defaults(to: false)
            }
            try db.create(indexOn: "emails", columns: ["provider_message_id"])
            try db.create(indexOn: "emails", columns: ["received_at"])

            // Calendar events table
            try db.create(table: "calendar_events") { t in
                t.column("id", .text).primaryKey()
                t.column("provider", .text).notNull()
                t.column("provider_event_id", .text).notNull()
                t.column("calendar_id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("notes", .text)
                t.column("location", .text)
                t.column("start_date", .datetime).notNull()
                t.column("end_date", .datetime).notNull()
                t.column("is_all_day", .boolean).notNull().defaults(to: false)
                t.column("attendees", .text) // JSON
                t.column("status", .text).notNull().defaults(to: "confirmed")
                t.column("embedding", .blob)
            }
            try db.create(indexOn: "calendar_events", columns: ["start_date"])

            // Contacts table
            try db.create(table: "contacts") { t in
                t.column("id", .text).primaryKey()
                t.column("system_contact_id", .text)
                t.column("first_name", .text).notNull()
                t.column("last_name", .text).notNull()
                t.column("nickname", .text)
                t.column("emails", .text) // JSON
                t.column("phones", .text) // JSON
                t.column("company", .text)
                t.column("job_title", .text)
                t.column("relationship", .text).notNull().defaults(to: "acquaintance")
                t.column("communication_frequency", .text).defaults(to: "occasional")
                t.column("preferred_contact_method", .text).defaults(to: "email")
                t.column("last_contact_date", .datetime)
                t.column("total_interactions", .integer).notNull().defaults(to: 0)
                t.column("contexts", .text) // JSON array
                t.column("embedding", .blob)
            }

            // Transactions table
            try db.create(table: "transactions") { t in
                t.column("id", .text).primaryKey()
                t.column("plaid_transaction_id", .text).notNull()
                t.column("account_id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("merchant_name", .text)
                t.column("amount", .double).notNull()
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.column("date", .datetime).notNull()
                t.column("category", .text) // JSON array
                t.column("primary_category", .text).notNull()
                t.column("is_pending", .boolean).notNull().defaults(to: false)
                t.column("is_recurring", .boolean).notNull().defaults(to: false)
                t.column("is_unusual", .boolean).notNull().defaults(to: false)
                t.column("embedding", .blob)
            }
            try db.create(indexOn: "transactions", columns: ["date"])
            try db.create(indexOn: "transactions", columns: ["account_id"])

            // Bank accounts table
            try db.create(table: "bank_accounts") { t in
                t.column("id", .text).primaryKey()
                t.column("plaid_account_id", .text).notNull()
                t.column("institution_id", .text).notNull()
                t.column("institution_name", .text).notNull()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("subtype", .text)
                t.column("mask", .text)
                t.column("current_balance", .double)
                t.column("available_balance", .double)
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.column("last_updated", .datetime).notNull()
            }

            // Shopping orders table
            try db.create(table: "shopping_orders") { t in
                t.column("id", .text).primaryKey()
                t.column("instacart_order_id", .text).notNull()
                t.column("status", .text).notNull()
                t.column("items", .text) // JSON
                t.column("store_name", .text).notNull()
                t.column("total", .double).notNull()
                t.column("delivery_address", .text).notNull()
                t.column("scheduled_delivery_start", .datetime)
                t.column("scheduled_delivery_end", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Attention items table (cached)
            try db.create(table: "attention_items") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("urgency", .double).notNull()
                t.column("source", .text).notNull()
                t.column("source_ref", .text)
                t.column("actions", .text) // JSON
                t.column("created_at", .datetime).notNull()
                t.column("expires_at", .datetime)
                t.column("dismissed_at", .datetime)
            }

            // Conversation log table
            try db.create(table: "conversation_log") { t in
                t.column("id", .text).primaryKey()
                t.column("role", .text).notNull() // user, assistant
                t.column("content", .text).notNull()
                t.column("audio_file_path", .text)
                t.column("timestamp", .datetime).notNull()
                t.column("embedding", .blob)
            }

            // User patterns table
            try db.create(table: "user_patterns") { t in
                t.column("id", .text).primaryKey()
                t.column("pattern_type", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("occurrences", .integer).notNull()
                t.column("last_seen", .datetime).notNull()
            }
        }

        // v2: Vector search tables (sqlite-vec)
        migrator.registerMigration("v2_vector") { db in
            // Note: sqlite-vec requires specific extension loading
            // These would be virtual tables in production

            // For now, we'll use the embedding blob columns created above
            // and implement vector search in Swift
        }

        try await dbPool.write { db in
            try migrator.migrate(db)
        }
    }

    // MARK: - Database Access

    var reader: DatabasePool {
        get throws {
            guard let dbPool = dbPool else {
                throw DatabaseError.notInitialized
            }
            return dbPool
        }
    }

    var writer: DatabasePool {
        get throws {
            guard let dbPool = dbPool else {
                throw DatabaseError.notInitialized
            }
            return dbPool
        }
    }

    // MARK: - Convenience Methods

    func read<T>(_ block: (Database) throws -> T) async throws -> T {
        try await writer.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) async throws -> T {
        try await writer.write(block)
    }
}

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed(String)
}
