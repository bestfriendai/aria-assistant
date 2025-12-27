import Foundation
import KeychainAccess

/// Central configuration and secrets management
actor Configuration {
    static let shared = Configuration()

    private let keychain = Keychain(service: "com.aria.assistant")
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - API Keys

    var geminiApiKey: String? {
        get { try? keychain.get("gemini_api_key") }
    }

    func setGeminiApiKey(_ key: String) throws {
        try keychain.set(key, key: "gemini_api_key")
    }

    var plaidClientId: String? {
        get { try? keychain.get("plaid_client_id") }
    }

    var plaidSecret: String? {
        get { try? keychain.get("plaid_secret") }
    }

    func setPlaidCredentials(clientId: String, secret: String) throws {
        try keychain.set(clientId, key: "plaid_client_id")
        try keychain.set(secret, key: "plaid_secret")
    }

    var instacartApiKey: String? {
        get { try? keychain.get("instacart_api_key") }
    }

    func setInstacartApiKey(_ key: String) throws {
        try keychain.set(key, key: "instacart_api_key")
    }

    // MARK: - OAuth Tokens

    func getOAuthToken(for provider: String) -> OAuthCredentials? {
        guard let accessToken = try? keychain.get("\(provider)_access_token") else {
            return nil
        }

        let refreshToken = try? keychain.get("\(provider)_refresh_token")
        let expiresAtString = try? keychain.get("\(provider)_expires_at")
        let expiresAt = expiresAtString.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    func setOAuthToken(_ credentials: OAuthCredentials, for provider: String) throws {
        try keychain.set(credentials.accessToken, key: "\(provider)_access_token")

        if let refreshToken = credentials.refreshToken {
            try keychain.set(refreshToken, key: "\(provider)_refresh_token")
        }

        if let expiresAt = credentials.expiresAt {
            try keychain.set(String(expiresAt.timeIntervalSince1970), key: "\(provider)_expires_at")
        }
    }

    func removeOAuthToken(for provider: String) throws {
        try keychain.remove("\(provider)_access_token")
        try keychain.remove("\(provider)_refresh_token")
        try keychain.remove("\(provider)_expires_at")
    }

    // MARK: - User Preferences

    var wakeWordEnabled: Bool {
        get { defaults.bool(forKey: "wake_word_enabled") }
        set { defaults.set(newValue, forKey: "wake_word_enabled") }
    }

    var alwaysListening: Bool {
        get { defaults.bool(forKey: "always_listening") }
        set { defaults.set(newValue, forKey: "always_listening") }
    }

    var hapticFeedbackEnabled: Bool {
        get { defaults.bool(forKey: "haptic_feedback") }
        set { defaults.set(newValue, forKey: "haptic_feedback") }
    }

    var voiceName: String {
        get { defaults.string(forKey: "voice_name") ?? "Aria" }
        set { defaults.set(newValue, forKey: "voice_name") }
    }

    var speakingRate: Double {
        get { defaults.double(forKey: "speaking_rate").nonZero ?? 1.0 }
        set { defaults.set(newValue, forKey: "speaking_rate") }
    }

    // MARK: - Data Management

    func exportAllData() async throws -> Data {
        // Export user data as JSON
        let exportData: [String: Any] = [
            "preferences": [
                "wakeWordEnabled": wakeWordEnabled,
                "alwaysListening": alwaysListening,
                "hapticFeedback": hapticFeedbackEnabled,
                "voiceName": voiceName,
                "speakingRate": speakingRate
            ],
            "exportDate": ISO8601DateFormatter().string(from: Date())
        ]

        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    func deleteAllData() async throws {
        // Delete all keychain items
        try keychain.removeAll()

        // Delete user defaults
        if let bundleId = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleId)
        }

        // Delete database
        // DatabaseManager.shared.deleteAllData()
    }
}

// MARK: - Helpers

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
