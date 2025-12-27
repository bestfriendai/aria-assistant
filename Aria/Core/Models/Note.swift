import Foundation

/// Note model (Apple Notes, etc.)
struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String // Apple Notes identifier
    let source: NoteSource

    var title: String
    var body: String
    var plainTextBody: String // Stripped of formatting
    var folder: String?

    var isPinned: Bool
    var isLocked: Bool

    var hasChecklist: Bool
    var checklistItems: [ChecklistItem]

    var attachmentCount: Int
    var hasDrawing: Bool
    var hasTable: Bool

    var createdAt: Date
    var modifiedAt: Date

    var embedding: [Float]?

    init(
        id: UUID = UUID(),
        sourceId: String,
        source: NoteSource = .appleNotes,
        title: String,
        body: String = "",
        plainTextBody: String = "",
        folder: String? = nil,
        isPinned: Bool = false,
        isLocked: Bool = false,
        hasChecklist: Bool = false,
        checklistItems: [ChecklistItem] = [],
        attachmentCount: Int = 0,
        hasDrawing: Bool = false,
        hasTable: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.source = source
        self.title = title
        self.body = body
        self.plainTextBody = plainTextBody
        self.folder = folder
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.hasChecklist = hasChecklist
        self.checklistItems = checklistItems
        self.attachmentCount = attachmentCount
        self.hasDrawing = hasDrawing
        self.hasTable = hasTable
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.embedding = embedding
    }

    var preview: String {
        let clean = plainTextBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 100 {
            return String(clean.prefix(100)) + "..."
        }
        return clean
    }

    var uncheckedItems: [ChecklistItem] {
        checklistItems.filter { !$0.isChecked }
    }

    var checkedItems: [ChecklistItem] {
        checklistItems.filter { $0.isChecked }
    }
}

enum NoteSource: String, Codable {
    case appleNotes
    case iCloudDrive
    case local
}

struct ChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isChecked: Bool

    init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

/// Document (iCloud Drive, etc.)
struct Document: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: String
    let source: DocumentSource

    var name: String
    var path: String
    var fileExtension: String
    var mimeType: String

    var sizeBytes: Int64
    var folder: String?

    var isDownloaded: Bool
    var isShared: Bool

    var createdAt: Date
    var modifiedAt: Date
    var lastOpenedAt: Date?

    var embedding: [Float]?

    init(
        id: UUID = UUID(),
        sourceId: String,
        source: DocumentSource = .iCloudDrive,
        name: String,
        path: String,
        fileExtension: String = "",
        mimeType: String = "",
        sizeBytes: Int64 = 0,
        folder: String? = nil,
        isDownloaded: Bool = false,
        isShared: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.source = source
        self.name = name
        self.path = path
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.folder = folder
        self.isDownloaded = isDownloaded
        self.isShared = isShared
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastOpenedAt = lastOpenedAt
        self.embedding = embedding
    }

    var icon: String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "txt", "md": return "doc.plaintext.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo.fill"
        case "mp4", "mov", "avi": return "video.fill"
        case "mp3", "m4a", "wav": return "music.note"
        case "zip", "rar", "7z": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

enum DocumentSource: String, Codable {
    case iCloudDrive
    case googleDrive
    case dropbox
    case oneDrive
    case local
}

/// iOS Reminder (via EventKit)
struct Reminder: Identifiable, Codable, Hashable {
    let id: UUID
    let eventKitId: String

    var title: String
    var notes: String?
    var list: String // Reminders list name

    var dueDate: Date?
    var reminderDate: Date?
    var priority: ReminderPriority

    var isCompleted: Bool
    var completedDate: Date?

    var isRecurring: Bool
    var recurrenceRule: String?

    var location: String?
    var locationTrigger: LocationTrigger?

    var url: String?
    var subtasks: [Reminder]

    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        eventKitId: String = "",
        title: String,
        notes: String? = nil,
        list: String = "Reminders",
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        priority: ReminderPriority = .none,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        isRecurring: Bool = false,
        recurrenceRule: String? = nil,
        location: String? = nil,
        locationTrigger: LocationTrigger? = nil,
        url: String? = nil,
        subtasks: [Reminder] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.eventKitId = eventKitId
        self.title = title
        self.notes = notes
        self.list = list
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.isRecurring = isRecurring
        self.recurrenceRule = recurrenceRule
        self.location = location
        self.locationTrigger = locationTrigger
        self.url = url
        self.subtasks = subtasks
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Date()
    }

    var isDueToday: Bool {
        guard let due = dueDate else { return false }
        return Calendar.current.isDateInToday(due)
    }

    var isDueSoon: Bool {
        guard let due = dueDate else { return false }
        let hoursUntilDue = due.timeIntervalSinceNow / 3600
        return hoursUntilDue > 0 && hoursUntilDue <= 24
    }
}

enum ReminderPriority: Int, Codable {
    case none = 0
    case low = 9
    case medium = 5
    case high = 1
}

enum LocationTrigger: Codable, Hashable {
    case arriving(latitude: Double, longitude: Double, radius: Double)
    case leaving(latitude: Double, longitude: Double, radius: Double)
}
