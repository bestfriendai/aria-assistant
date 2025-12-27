import Foundation
import EventKit
import Photos
import Intents
import UserNotifications

/// iOS Native integration service for Reminders, Photos, Shortcuts, and Focus modes
actor iOSIntegrationService {
    // MARK: - EventKit (Reminders)

    private let eventStore = EKEventStore()
    private var remindersCache: [Reminder] = []

    // MARK: - Authorization

    func requestRemindersAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    func requestPhotosAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Reminders

    func getReminders(
        calendars: [EKCalendar]? = nil,
        completed: Bool? = nil
    ) async throws -> [Reminder] {
        let predicate = eventStore.predicateForReminders(in: calendars)

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { ekReminders in
                guard let ekReminders = ekReminders else {
                    continuation.resume(returning: [])
                    return
                }

                var reminders = ekReminders.compactMap { self.mapEKReminder($0) }

                if let completed = completed {
                    reminders = reminders.filter { $0.isCompleted == completed }
                }

                continuation.resume(returning: reminders)
            }
        }
    }

    func getTodayReminders() async throws -> [Reminder] {
        let all = try await getReminders(completed: false)
        return all.filter { $0.isDueToday }
    }

    func getOverdueReminders() async throws -> [Reminder] {
        let all = try await getReminders(completed: false)
        return all.filter { $0.isOverdue }
    }

    func getUpcomingReminders(days: Int = 7) async throws -> [Reminder] {
        let all = try await getReminders(completed: false)
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!

        return all.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return dueDate >= Date() && dueDate <= futureDate
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: ReminderPriority = .none,
        list: String? = nil
    ) async throws -> Reminder {
        let ekReminder = EKReminder(eventStore: eventStore)
        ekReminder.title = title
        ekReminder.notes = notes
        ekReminder.priority = priority.rawValue

        if let dueDate = dueDate {
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            // Add alarm
            let alarm = EKAlarm(absoluteDate: dueDate)
            ekReminder.addAlarm(alarm)
        }

        // Set calendar (list)
        if let listName = list,
           let calendar = eventStore.calendars(for: .reminder).first(where: { $0.title == listName }) {
            ekReminder.calendar = calendar
        } else {
            ekReminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        try eventStore.save(ekReminder, commit: true)

        return mapEKReminder(ekReminder)
    }

    func completeReminder(_ reminder: Reminder) async throws {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: reminder.eventKitId) as? EKReminder else {
            throw iOSIntegrationError.reminderNotFound
        }

        ekReminder.isCompleted = true
        ekReminder.completionDate = Date()
        try eventStore.save(ekReminder, commit: true)
    }

    func uncompleteReminder(_ reminder: Reminder) async throws {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: reminder.eventKitId) as? EKReminder else {
            throw iOSIntegrationError.reminderNotFound
        }

        ekReminder.isCompleted = false
        ekReminder.completionDate = nil
        try eventStore.save(ekReminder, commit: true)
    }

    func deleteReminder(_ reminder: Reminder) async throws {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: reminder.eventKitId) as? EKReminder else {
            throw iOSIntegrationError.reminderNotFound
        }

        try eventStore.remove(ekReminder, commit: true)
    }

    func getReminderLists() async -> [String] {
        eventStore.calendars(for: .reminder).map { $0.title }
    }

    private func mapEKReminder(_ ekReminder: EKReminder) -> Reminder {
        let dueDate: Date?
        if let components = ekReminder.dueDateComponents {
            dueDate = Calendar.current.date(from: components)
        } else {
            dueDate = nil
        }

        return Reminder(
            eventKitId: ekReminder.calendarItemIdentifier,
            title: ekReminder.title ?? "",
            notes: ekReminder.notes,
            list: ekReminder.calendar?.title ?? "Reminders",
            dueDate: dueDate,
            priority: ReminderPriority(rawValue: ekReminder.priority) ?? .none,
            isCompleted: ekReminder.isCompleted,
            completedDate: ekReminder.completionDate,
            createdAt: ekReminder.creationDate ?? Date(),
            modifiedAt: ekReminder.lastModifiedDate ?? Date()
        )
    }

    // MARK: - Photos

    func getRecentPhotos(limit: Int = 20) async throws -> [PhotoAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit

        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photos: [PhotoAsset] = []
        results.enumerateObjects { asset, _, _ in
            photos.append(self.mapPHAsset(asset))
        }

        return photos
    }

    func getPhotos(from startDate: Date, to endDate: Date) async throws -> [PhotoAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photos: [PhotoAsset] = []
        results.enumerateObjects { asset, _, _ in
            photos.append(self.mapPHAsset(asset))
        }

        return photos
    }

    func getPhotosAtLocation(latitude: Double, longitude: Double, radius: Double = 100) async throws -> [PhotoAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photos: [PhotoAsset] = []
        let targetLocation = CLLocation(latitude: latitude, longitude: longitude)

        results.enumerateObjects { asset, _, _ in
            if let location = asset.location {
                let distance = location.distance(from: targetLocation)
                if distance <= radius {
                    photos.append(self.mapPHAsset(asset))
                }
            }
        }

        return photos
    }

    func getScreenshots(limit: Int = 20) async throws -> [PhotoAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit

        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photos: [PhotoAsset] = []
        results.enumerateObjects { asset, _, _ in
            photos.append(self.mapPHAsset(asset))
        }

        return photos
    }

    func searchPhotos(text: String) async throws -> [PhotoAsset] {
        // iOS 15+ has on-device photo search
        // This is a simplified implementation
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // Would use PHAsset's localizedDescription or ML-based search
        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var photos: [PhotoAsset] = []
        results.enumerateObjects { asset, _, stop in
            photos.append(self.mapPHAsset(asset))
            if photos.count >= 50 {
                stop.pointee = true
            }
        }

        return photos
    }

    private func mapPHAsset(_ asset: PHAsset) -> PhotoAsset {
        PhotoAsset(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            location: asset.location,
            mediaType: asset.mediaType == .video ? .video : .photo,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    // MARK: - Shortcuts Integration

    func donateIntent(_ intent: INIntent) async {
        let interaction = INInteraction(intent: intent, response: nil)
        try? await interaction.donate()
    }

    func suggestShortcut(
        title: String,
        phrase: String,
        intent: INIntent
    ) async {
        let shortcut = INShortcut(intent: intent)

        if let shortcut = shortcut {
            let suggestion = INVoiceShortcut(shortcut: shortcut)
            // Would present to user for confirmation
        }
    }

    func runShortcut(named name: String) async throws {
        // Use URL scheme to run shortcut
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        if let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") {
            // Would open URL
        }
    }

    func runShortcutWithInput(named name: String, input: String) async throws {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let encodedInput = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input

        if let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)&input=\(encodedInput)") {
            // Would open URL
        }
    }

    // MARK: - Focus Mode

    func getCurrentFocusStatus() async -> FocusStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Check if Focus is active based on notification settings
        let isActive = settings.notificationCenterSetting == .disabled

        return FocusStatus(
            isActive: isActive,
            currentMode: isActive ? .custom : nil
        )
    }

    func checkFocusModeAllowsNotification() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // Note: Focus modes cannot be programmatically set without user interaction
    // These methods would trigger system UI

    func requestFocusModeChange(to mode: FocusMode) async {
        // Would use INSetFocusStatusIntent in iOS 16+
        // This requires user confirmation
    }

    // MARK: - Find My Integration

    func getDeviceLocations() async throws -> [DeviceLocation] {
        // Find My data is not accessible via public APIs
        // This would require private APIs or user to share location
        return []
    }

    // MARK: - Notifications

    func scheduleNotification(
        title: String,
        body: String,
        at date: Date,
        identifier: String? = nil
    ) async throws {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier ?? UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }

    func cancelNotification(identifier: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func getPendingNotifications() async -> [UNNotificationRequest] {
        let center = UNUserNotificationCenter.current()
        return await center.pendingNotificationRequests()
    }

    // MARK: - System Features

    func getBatteryLevel() -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
    }

    func getBatteryState() -> UIDevice.BatteryState {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryState
    }

    func isLowPowerModeEnabled() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func getStorageInfo() -> (used: Int64, total: Int64)? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else {
            return nil
        }

        let total = attributes[.systemSize] as? Int64 ?? 0
        let free = attributes[.systemFreeSize] as? Int64 ?? 0
        let used = total - free

        return (used, total)
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ command: String) async throws -> String {
        let lower = command.lowercased()

        // Reminders
        if lower.contains("remind me") {
            let title = extractReminderTitle(from: command)
            let dueDate = extractDate(from: command)

            let reminder = try await createReminder(title: title, dueDate: dueDate)
            return "Created reminder: \(reminder.title)"
        }

        if lower.contains("reminders") && (lower.contains("today") || lower.contains("due")) {
            let reminders = try await getTodayReminders()
            if reminders.isEmpty {
                return "You have no reminders due today."
            }
            return "You have \(reminders.count) reminder(s) due today: \(reminders.prefix(3).map { $0.title }.joined(separator: ", "))"
        }

        // Photos
        if lower.contains("recent photos") || lower.contains("latest photos") {
            let photos = try await getRecentPhotos(limit: 5)
            return "Found \(photos.count) recent photos"
        }

        if lower.contains("screenshots") {
            let screenshots = try await getScreenshots(limit: 5)
            return "Found \(screenshots.count) recent screenshots"
        }

        // Shortcuts
        if lower.contains("run shortcut") || lower.contains("run") {
            let shortcutName = extractShortcutName(from: command)
            try await runShortcut(named: shortcutName)
            return "Running shortcut: \(shortcutName)"
        }

        // Battery
        if lower.contains("battery") {
            let level = getBatteryLevel()
            let state = getBatteryState()
            let stateStr = state == .charging ? "charging" : (state == .full ? "fully charged" : "not charging")
            return "Battery is at \(Int(level * 100))% and \(stateStr)"
        }

        throw iOSIntegrationError.unknownCommand
    }

    private func extractReminderTitle(from command: String) -> String {
        // Extract text after "remind me to" or "remind me"
        let lower = command.lowercased()
        if let range = lower.range(of: "remind me to ") {
            var remaining = String(command[range.upperBound...])
            // Remove time-related parts
            if let atRange = remaining.lowercased().range(of: " at ") {
                remaining = String(remaining[..<atRange.lowerBound])
            }
            if let inRange = remaining.lowercased().range(of: " in ") {
                remaining = String(remaining[..<inRange.lowerBound])
            }
            return remaining.trimmingCharacters(in: .whitespaces)
        }
        return command
    }

    private func extractDate(from command: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: command, range: NSRange(command.startIndex..., in: command))
        return matches?.compactMap { $0.date }.first
    }

    private func extractShortcutName(from command: String) -> String {
        let lower = command.lowercased()
        if let range = lower.range(of: "run shortcut ") {
            return String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = lower.range(of: "run ") {
            return String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return command
    }
}

// MARK: - Models

struct PhotoAsset: Identifiable {
    let id: UUID = UUID()
    let localIdentifier: String
    let creationDate: Date?
    let modificationDate: Date?
    let location: CLLocation?
    let mediaType: MediaType
    let duration: TimeInterval
    let isFavorite: Bool
    let isHidden: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    enum MediaType {
        case photo
        case video
        case livePhoto
    }
}

struct FocusStatus {
    let isActive: Bool
    let currentMode: FocusMode?
}

enum FocusMode: String {
    case doNotDisturb = "Do Not Disturb"
    case personal = "Personal"
    case work = "Work"
    case sleep = "Sleep"
    case driving = "Driving"
    case fitness = "Fitness"
    case gaming = "Gaming"
    case mindfulness = "Mindfulness"
    case reading = "Reading"
    case custom = "Custom"
}

struct DeviceLocation: Identifiable {
    let id: UUID = UUID()
    let name: String
    let deviceType: String
    let location: CLLocation?
    let lastUpdated: Date
    let batteryLevel: Float?
    let isOnline: Bool
}

// MARK: - Errors

enum iOSIntegrationError: Error, LocalizedError {
    case notAuthorized
    case reminderNotFound
    case photoNotFound
    case shortcutNotFound
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Access not authorized"
        case .reminderNotFound: return "Reminder not found"
        case .photoNotFound: return "Photo not found"
        case .shortcutNotFound: return "Shortcut not found"
        case .unknownCommand: return "Unknown command"
        }
    }
}
