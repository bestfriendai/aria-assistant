import Foundation

/// A task extracted from various sources or manually created
struct AriaTask: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String?
    let source: DataSource
    let sourceRef: String? // email_id, event_id, etc.
    var dueDate: Date?
    var priority: Int // 0-100, AI-computed
    var context: [String] // people, projects, locations
    var status: TaskStatus
    var embedding: [Float]? // For semantic search
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        source: DataSource = .manual,
        sourceRef: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 50,
        context: [String] = [],
        status: TaskStatus = .pending,
        embedding: [Float]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.source = source
        self.sourceRef = sourceRef
        self.dueDate = dueDate
        self.priority = min(100, max(0, priority))
        self.context = context
        self.status = status
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    /// Calculate urgency based on due date and priority
    var urgency: Double {
        var score = Double(priority) / 100.0 * 0.5 // Priority contributes 50%

        if let dueDate = dueDate {
            let hoursUntilDue = dueDate.timeIntervalSinceNow / 3600
            if hoursUntilDue < 0 {
                score += 0.5 // Overdue = max urgency
            } else if hoursUntilDue < 24 {
                score += 0.4 // Due within 24 hours
            } else if hoursUntilDue < 72 {
                score += 0.3 // Due within 3 days
            } else if hoursUntilDue < 168 {
                score += 0.2 // Due within a week
            }
        }

        return min(1.0, score)
    }

    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .done
    }

    mutating func markDone() {
        status = .done
        completedAt = Date()
        updatedAt = Date()
    }
}

enum TaskStatus: String, Codable, Hashable {
    case pending
    case inProgress = "in_progress"
    case done
    case delegated
    case cancelled
}

// MARK: - Priority Algorithm
extension AriaTask {
    /// Calculate priority using the algorithm from the spec
    /// - urgency (deadline proximity): weight 0.3
    /// - importance (source, people involved): weight 0.3
    /// - effort (estimated time): weight 0.1
    /// - dependencies (blocked/blocking): weight 0.2
    /// - patterns (when user does what): weight 0.1
    static func calculatePriority(
        dueDate: Date?,
        source: DataSource,
        contextPeople: [String],
        estimatedMinutes: Int? = nil,
        isBlocking: Bool = false,
        isBlocked: Bool = false,
        userPatternScore: Double = 0.5
    ) -> Int {
        var score: Double = 0

        // Urgency (0.3)
        if let dueDate = dueDate {
            let hoursUntilDue = dueDate.timeIntervalSinceNow / 3600
            let urgencyScore: Double
            if hoursUntilDue < 0 {
                urgencyScore = 1.0
            } else if hoursUntilDue < 24 {
                urgencyScore = 0.9
            } else if hoursUntilDue < 72 {
                urgencyScore = 0.7
            } else if hoursUntilDue < 168 {
                urgencyScore = 0.5
            } else {
                urgencyScore = 0.3
            }
            score += urgencyScore * 0.3
        } else {
            score += 0.3 * 0.3 // Default low urgency
        }

        // Importance (0.3)
        let sourceImportance: Double = switch source {
        case .email: 0.6
        case .calendar: 0.7
        case .banking: 0.8
        case .voice: 0.9 // User explicitly asked
        case .manual: 0.5
        default: 0.4
        }
        let peopleBonus = min(0.2, Double(contextPeople.count) * 0.05)
        score += (sourceImportance + peopleBonus) * 0.3

        // Effort (0.1) - favor quick tasks
        if let minutes = estimatedMinutes {
            let effortScore = minutes < 15 ? 0.9 : (minutes < 60 ? 0.6 : 0.3)
            score += effortScore * 0.1
        } else {
            score += 0.5 * 0.1
        }

        // Dependencies (0.2)
        if isBlocking {
            score += 1.0 * 0.2 // Blocking others = high priority
        } else if isBlocked {
            score += 0.2 * 0.2 // Blocked = lower priority
        } else {
            score += 0.5 * 0.2
        }

        // Patterns (0.1)
        score += userPatternScore * 0.1

        return Int(score * 100)
    }
}
