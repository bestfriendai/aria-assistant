import Foundation

/// Work communications service for Slack and Microsoft Teams integration
actor WorkCommunicationsService {
    // MARK: - Configuration

    private var slackToken: String?
    private var teamsToken: String?

    private let slackBaseURL = URL(string: "https://slack.com/api")!
    private let graphBaseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    // MARK: - Cache

    private var slackMessagesCache: [WorkMessage] = []
    private var teamsMessagesCache: [WorkMessage] = []
    private var channelsCache: [WorkChannel] = []
    private var unreadCount: Int = 0

    // MARK: - Configuration

    func configure(slackToken: String? = nil, teamsToken: String? = nil) {
        self.slackToken = slackToken
        self.teamsToken = teamsToken
    }

    var isSlackConfigured: Bool { slackToken != nil }
    var isTeamsConfigured: Bool { teamsToken != nil }

    // MARK: - Slack Integration

    func getSlackChannels() async throws -> [WorkChannel] {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: slackBaseURL.appendingPathComponent("/conversations.list"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseSlackChannels(data)
    }

    func getSlackMessages(channelId: String, limit: Int = 50) async throws -> [WorkMessage] {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        let url = slackBaseURL.appendingPathComponent("/conversations.history")
            .appending(queryItems: [
                URLQueryItem(name: "channel", value: channelId),
                URLQueryItem(name: "limit", value: String(limit))
            ])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseSlackMessages(data, channelId: channelId)
    }

    func getSlackDirectMessages(userId: String, limit: Int = 50) async throws -> [WorkMessage] {
        // First open a DM channel
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        let openUrl = slackBaseURL.appendingPathComponent("/conversations.open")
        var openRequest = URLRequest(url: openUrl)
        openRequest.httpMethod = "POST"
        openRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        openRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        openRequest.httpBody = try JSONSerialization.data(withJSONObject: ["users": userId])

        let (openData, _) = try await URLSession.shared.data(for: openRequest)

        guard let json = try JSONSerialization.jsonObject(with: openData) as? [String: Any],
              let channel = json["channel"] as? [String: Any],
              let channelId = channel["id"] as? String else {
            throw WorkCommsError.parseError
        }

        return try await getSlackMessages(channelId: channelId, limit: limit)
    }

    func sendSlackMessage(channelId: String, text: String, threadTs: String? = nil) async throws -> WorkMessage {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: slackBaseURL.appendingPathComponent("/chat.postMessage"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "channel": channelId,
            "text": text
        ]

        if let threadTs = threadTs {
            body["thread_ts"] = threadTs
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseSlackMessageResponse(data, channelId: channelId)
    }

    func searchSlack(query: String) async throws -> [WorkMessage] {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        let url = slackBaseURL.appendingPathComponent("/search.messages")
            .appending(queryItems: [URLQueryItem(name: "query", value: query)])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseSlackSearchResults(data)
    }

    func getSlackMentions() async throws -> [WorkMessage] {
        try await searchSlack(query: "@me")
    }

    func getSlackUnreadCount() async throws -> Int {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        let url = slackBaseURL.appendingPathComponent("/conversations.list")
            .appending(queryItems: [URLQueryItem(name: "types", value: "im,mpim")])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = json["channels"] as? [[String: Any]] else {
            throw WorkCommsError.parseError
        }

        var count = 0
        for channel in channels {
            if let unreadCount = channel["unread_count"] as? Int {
                count += unreadCount
            }
        }

        unreadCount = count
        return count
    }

    func setSlackStatus(text: String, emoji: String? = nil, expiration: Date? = nil) async throws {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: slackBaseURL.appendingPathComponent("/users.profile.set"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var profile: [String: Any] = [
            "status_text": text
        ]

        if let emoji = emoji {
            profile["status_emoji"] = emoji
        }

        if let expiration = expiration {
            profile["status_expiration"] = Int(expiration.timeIntervalSince1970)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: ["profile": profile])

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WorkCommsError.requestFailed
        }
    }

    func setSlackPresence(away: Bool) async throws {
        guard let token = slackToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: slackBaseURL.appendingPathComponent("/users.setPresence"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["presence": away ? "away" : "auto"])

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    // MARK: - Microsoft Teams Integration

    func getTeamsChats() async throws -> [WorkChannel] {
        guard let token = teamsToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: graphBaseURL.appendingPathComponent("/me/chats"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseTeamsChats(data)
    }

    func getTeamsMessages(chatId: String, limit: Int = 50) async throws -> [WorkMessage] {
        guard let token = teamsToken else {
            throw WorkCommsError.notConfigured
        }

        let url = graphBaseURL.appendingPathComponent("/me/chats/\(chatId)/messages")
            .appending(queryItems: [URLQueryItem(name: "$top", value: String(limit))])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseTeamsMessages(data, chatId: chatId)
    }

    func sendTeamsMessage(chatId: String, text: String) async throws -> WorkMessage {
        guard let token = teamsToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: graphBaseURL.appendingPathComponent("/me/chats/\(chatId)/messages"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "body": ["content": text]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseTeamsMessageResponse(data, chatId: chatId)
    }

    func getTeamsChannelMessages(teamId: String, channelId: String, limit: Int = 50) async throws -> [WorkMessage] {
        guard let token = teamsToken else {
            throw WorkCommsError.notConfigured
        }

        let url = graphBaseURL.appendingPathComponent("/teams/\(teamId)/channels/\(channelId)/messages")
            .appending(queryItems: [URLQueryItem(name: "$top", value: String(limit))])

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseTeamsMessages(data, chatId: channelId)
    }

    func setTeamsPresence(availability: TeamsAvailability, activity: TeamsActivity? = nil) async throws {
        guard let token = teamsToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: graphBaseURL.appendingPathComponent("/me/presence/setPresence"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "sessionId": UUID().uuidString,
            "availability": availability.rawValue
        ]

        if let activity = activity {
            body["activity"] = activity.rawValue
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    func setTeamsStatusMessage(_ message: String, expiration: Date? = nil) async throws {
        guard let token = teamsToken else {
            throw WorkCommsError.notConfigured
        }

        var request = URLRequest(url: graphBaseURL.appendingPathComponent("/me/presence/setStatusMessage"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var statusMessage: [String: Any] = [
            "message": ["content": message]
        ]

        if let expiration = expiration {
            let formatter = ISO8601DateFormatter()
            statusMessage["expiryDateTime"] = ["dateTime": formatter.string(from: expiration)]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: ["statusMessage": statusMessage])

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    // MARK: - Unified Interface

    func getAllUnreadMessages() async throws -> [WorkMessage] {
        var messages: [WorkMessage] = []

        if slackToken != nil {
            let slackMentions = try await getSlackMentions()
            messages.append(contentsOf: slackMentions)
        }

        // Teams doesn't have a direct unread API, would need to track locally

        return messages.sorted { $0.timestamp > $1.timestamp }
    }

    func getRecentMessages(limit: Int = 20) async throws -> [WorkMessage] {
        var messages: [WorkMessage] = []

        if slackToken != nil {
            // Get messages from recent channels
            let channels = try await getSlackChannels()
            for channel in channels.prefix(3) {
                let channelMessages = try await getSlackMessages(channelId: channel.externalId, limit: 10)
                messages.append(contentsOf: channelMessages)
            }
        }

        if teamsToken != nil {
            let chats = try await getTeamsChats()
            for chat in chats.prefix(3) {
                let chatMessages = try await getTeamsMessages(chatId: chat.externalId, limit: 10)
                messages.append(contentsOf: chatMessages)
            }
        }

        return messages
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    func searchMessages(query: String) async throws -> [WorkMessage] {
        var results: [WorkMessage] = []

        if slackToken != nil {
            let slackResults = try await searchSlack(query: query)
            results.append(contentsOf: slackResults)
        }

        // Teams search would go through Microsoft Graph search API

        return results
    }

    // MARK: - Parsing Helpers

    private func parseSlackChannels(_ data: Data) throws -> [WorkChannel] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = json["channels"] as? [[String: Any]] else {
            throw WorkCommsError.parseError
        }

        return channels.compactMap { channel -> WorkChannel? in
            guard let id = channel["id"] as? String,
                  let name = channel["name"] as? String else {
                return nil
            }

            return WorkChannel(
                externalId: id,
                platform: .slack,
                name: name,
                type: (channel["is_im"] as? Bool == true) ? .directMessage : .channel,
                memberCount: channel["num_members"] as? Int,
                unreadCount: channel["unread_count"] as? Int ?? 0
            )
        }
    }

    private func parseSlackMessages(_ data: Data, channelId: String) throws -> [WorkMessage] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            throw WorkCommsError.parseError
        }

        return messages.compactMap { message -> WorkMessage? in
            guard let ts = message["ts"] as? String,
                  let text = message["text"] as? String else {
                return nil
            }

            let timestamp = Double(ts) ?? 0

            return WorkMessage(
                externalId: ts,
                platform: .slack,
                channelId: channelId,
                senderId: message["user"] as? String ?? "",
                senderName: message["username"] as? String ?? "Unknown",
                content: text,
                timestamp: Date(timeIntervalSince1970: timestamp),
                isFromMe: false, // Would need to check against current user
                threadId: message["thread_ts"] as? String,
                replyCount: message["reply_count"] as? Int ?? 0
            )
        }
    }

    private func parseSlackMessageResponse(_ data: Data, channelId: String) throws -> WorkMessage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let ts = message["ts"] as? String,
              let text = message["text"] as? String else {
            throw WorkCommsError.parseError
        }

        return WorkMessage(
            externalId: ts,
            platform: .slack,
            channelId: channelId,
            senderId: message["user"] as? String ?? "",
            senderName: "Me",
            content: text,
            timestamp: Date(),
            isFromMe: true
        )
    }

    private func parseSlackSearchResults(_ data: Data) throws -> [WorkMessage] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messagesWrapper = json["messages"] as? [String: Any],
              let matches = messagesWrapper["matches"] as? [[String: Any]] else {
            throw WorkCommsError.parseError
        }

        return matches.compactMap { match -> WorkMessage? in
            guard let ts = match["ts"] as? String,
                  let text = match["text"] as? String,
                  let channel = match["channel"] as? [String: Any],
                  let channelId = channel["id"] as? String else {
                return nil
            }

            let timestamp = Double(ts) ?? 0

            return WorkMessage(
                externalId: ts,
                platform: .slack,
                channelId: channelId,
                senderId: match["user"] as? String ?? "",
                senderName: match["username"] as? String ?? "Unknown",
                content: text,
                timestamp: Date(timeIntervalSince1970: timestamp),
                isFromMe: false
            )
        }
    }

    private func parseTeamsChats(_ data: Data) throws -> [WorkChannel] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chats = json["value"] as? [[String: Any]] else {
            throw WorkCommsError.parseError
        }

        return chats.compactMap { chat -> WorkChannel? in
            guard let id = chat["id"] as? String else {
                return nil
            }

            let chatType = chat["chatType"] as? String ?? ""
            let type: WorkChannelType = chatType == "oneOnOne" ? .directMessage : .group

            return WorkChannel(
                externalId: id,
                platform: .teams,
                name: chat["topic"] as? String ?? "Chat",
                type: type,
                memberCount: nil,
                unreadCount: 0
            )
        }
    }

    private func parseTeamsMessages(_ data: Data, chatId: String) throws -> [WorkMessage] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["value"] as? [[String: Any]] else {
            throw WorkCommsError.parseError
        }

        let formatter = ISO8601DateFormatter()

        return messages.compactMap { message -> WorkMessage? in
            guard let id = message["id"] as? String,
                  let body = message["body"] as? [String: Any],
                  let content = body["content"] as? String,
                  let from = message["from"] as? [String: Any],
                  let user = from["user"] as? [String: Any] else {
                return nil
            }

            let createdStr = message["createdDateTime"] as? String ?? ""
            let timestamp = formatter.date(from: createdStr) ?? Date()

            return WorkMessage(
                externalId: id,
                platform: .teams,
                channelId: chatId,
                senderId: user["id"] as? String ?? "",
                senderName: user["displayName"] as? String ?? "Unknown",
                content: content,
                timestamp: timestamp,
                isFromMe: false
            )
        }
    }

    private func parseTeamsMessageResponse(_ data: Data, chatId: String) throws -> WorkMessage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let body = json["body"] as? [String: Any],
              let content = body["content"] as? String else {
            throw WorkCommsError.parseError
        }

        return WorkMessage(
            externalId: id,
            platform: .teams,
            channelId: chatId,
            senderId: "",
            senderName: "Me",
            content: content,
            timestamp: Date(),
            isFromMe: true
        )
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ command: String) async throws -> String {
        let lower = command.lowercased()

        if lower.contains("unread") || lower.contains("new messages") {
            if slackToken != nil {
                let count = try await getSlackUnreadCount()
                return "You have \(count) unread Slack messages"
            }
            return "Work communications not configured"
        }

        if lower.contains("send") && lower.contains("slack") {
            // Parse: "send slack message to #channel saying ..."
            // This would need more sophisticated parsing
            throw WorkCommsError.unknownCommand
        }

        if lower.contains("set status") || lower.contains("update status") {
            let status = extractStatus(from: command)
            if slackToken != nil {
                try await setSlackStatus(text: status)
                return "Slack status updated to: \(status)"
            }
            if teamsToken != nil {
                try await setTeamsStatusMessage(status)
                return "Teams status updated to: \(status)"
            }
            return "Work communications not configured"
        }

        if lower.contains("away") || lower.contains("do not disturb") {
            if slackToken != nil {
                try await setSlackPresence(away: true)
            }
            if teamsToken != nil {
                try await setTeamsPresence(availability: .away)
            }
            return "Set to away"
        }

        if lower.contains("available") || lower.contains("online") {
            if slackToken != nil {
                try await setSlackPresence(away: false)
            }
            if teamsToken != nil {
                try await setTeamsPresence(availability: .available)
            }
            return "Set to available"
        }

        throw WorkCommsError.unknownCommand
    }

    private func extractStatus(from command: String) -> String {
        let lower = command.lowercased()
        if let range = lower.range(of: "status to") {
            return String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = lower.range(of: "status") {
            return String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return command
    }
}

// MARK: - Models

struct WorkChannel: Identifiable {
    let id: UUID = UUID()
    let externalId: String
    let platform: WorkPlatform
    var name: String
    var type: WorkChannelType
    var memberCount: Int?
    var unreadCount: Int
}

struct WorkMessage: Identifiable {
    let id: UUID = UUID()
    let externalId: String
    let platform: WorkPlatform
    let channelId: String
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let isFromMe: Bool
    var threadId: String?
    var replyCount: Int = 0
    var reactions: [String: Int] = [:]
}

enum WorkPlatform: String, Codable {
    case slack
    case teams
}

enum WorkChannelType: String, Codable {
    case channel
    case group
    case directMessage
}

enum TeamsAvailability: String {
    case available = "Available"
    case busy = "Busy"
    case doNotDisturb = "DoNotDisturb"
    case away = "Away"
    case offline = "Offline"
}

enum TeamsActivity: String {
    case available = "Available"
    case inACall = "InACall"
    case inAMeeting = "InAMeeting"
    case presenting = "Presenting"
    case outOfOffice = "OutOfOffice"
}

// MARK: - Errors

enum WorkCommsError: Error, LocalizedError {
    case notConfigured
    case requestFailed
    case parseError
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Work communications not configured"
        case .requestFailed: return "Request failed"
        case .parseError: return "Failed to parse response"
        case .unknownCommand: return "Unknown command"
        }
    }
}
