import Foundation

/// Health data model (HealthKit abstraction)
struct HealthData: Codable {
    // Activity
    var steps: Int?
    var stepsGoal: Int?
    var activeCalories: Int?
    var activeCaloriesGoal: Int?
    var exerciseMinutes: Int?
    var exerciseMinutesGoal: Int?
    var standHours: Int?
    var standHoursGoal: Int?
    var distance: Double? // meters
    var flightsClimbed: Int?

    // Vitals
    var heartRate: Int?
    var restingHeartRate: Int?
    var heartRateVariability: Double?
    var bloodOxygen: Double? // percentage
    var respiratoryRate: Double?
    var bodyTemperature: Double?

    // Body
    var weight: Double? // kg
    var height: Double? // cm
    var bmi: Double?
    var bodyFat: Double? // percentage

    // Sleep
    var sleepHours: Double?
    var sleepQuality: SleepQuality?
    var bedtime: Date?
    var wakeTime: Date?
    var deepSleep: Double? // hours
    var remSleep: Double? // hours
    var awakeTime: Double? // hours during sleep

    // Mindfulness
    var mindfulMinutes: Int?

    // Nutrition (if tracked)
    var waterIntake: Double? // liters
    var caffeine: Double? // mg

    var lastUpdated: Date

    init(
        steps: Int? = nil,
        stepsGoal: Int? = nil,
        activeCalories: Int? = nil,
        activeCaloriesGoal: Int? = nil,
        exerciseMinutes: Int? = nil,
        exerciseMinutesGoal: Int? = nil,
        standHours: Int? = nil,
        standHoursGoal: Int? = nil,
        distance: Double? = nil,
        flightsClimbed: Int? = nil,
        heartRate: Int? = nil,
        restingHeartRate: Int? = nil,
        heartRateVariability: Double? = nil,
        bloodOxygen: Double? = nil,
        respiratoryRate: Double? = nil,
        bodyTemperature: Double? = nil,
        weight: Double? = nil,
        height: Double? = nil,
        bmi: Double? = nil,
        bodyFat: Double? = nil,
        sleepHours: Double? = nil,
        sleepQuality: SleepQuality? = nil,
        bedtime: Date? = nil,
        wakeTime: Date? = nil,
        deepSleep: Double? = nil,
        remSleep: Double? = nil,
        awakeTime: Double? = nil,
        mindfulMinutes: Int? = nil,
        waterIntake: Double? = nil,
        caffeine: Double? = nil,
        lastUpdated: Date = Date()
    ) {
        self.steps = steps
        self.stepsGoal = stepsGoal
        self.activeCalories = activeCalories
        self.activeCaloriesGoal = activeCaloriesGoal
        self.exerciseMinutes = exerciseMinutes
        self.exerciseMinutesGoal = exerciseMinutesGoal
        self.standHours = standHours
        self.standHoursGoal = standHoursGoal
        self.distance = distance
        self.flightsClimbed = flightsClimbed
        self.heartRate = heartRate
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.bloodOxygen = bloodOxygen
        self.respiratoryRate = respiratoryRate
        self.bodyTemperature = bodyTemperature
        self.weight = weight
        self.height = height
        self.bmi = bmi
        self.bodyFat = bodyFat
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.deepSleep = deepSleep
        self.remSleep = remSleep
        self.awakeTime = awakeTime
        self.mindfulMinutes = mindfulMinutes
        self.waterIntake = waterIntake
        self.caffeine = caffeine
        self.lastUpdated = lastUpdated
    }

    var stepsProgress: Double? {
        guard let steps = steps, let goal = stepsGoal, goal > 0 else { return nil }
        return Double(steps) / Double(goal)
    }

    var caloriesProgress: Double? {
        guard let cals = activeCalories, let goal = activeCaloriesGoal, goal > 0 else { return nil }
        return Double(cals) / Double(goal)
    }

    var exerciseProgress: Double? {
        guard let mins = exerciseMinutes, let goal = exerciseMinutesGoal, goal > 0 else { return nil }
        return Double(mins) / Double(goal)
    }
}

enum SleepQuality: String, Codable {
    case poor
    case fair
    case good
    case excellent
}

/// Medication model
struct Medication: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var dosage: String
    var unit: String // mg, ml, etc.
    var form: MedicationForm

    var frequency: MedicationFrequency
    var scheduledTimes: [Date] // Times of day
    var instructions: String? // "Take with food"

    var prescribedBy: String?
    var pharmacy: String?
    var refillDate: Date?
    var pillsRemaining: Int?

    var startDate: Date
    var endDate: Date?

    var isActive: Bool
    var notes: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        unit: String = "mg",
        form: MedicationForm = .pill,
        frequency: MedicationFrequency = .daily,
        scheduledTimes: [Date] = [],
        instructions: String? = nil,
        prescribedBy: String? = nil,
        pharmacy: String? = nil,
        refillDate: Date? = nil,
        pillsRemaining: Int? = nil,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.unit = unit
        self.form = form
        self.frequency = frequency
        self.scheduledTimes = scheduledTimes
        self.instructions = instructions
        self.prescribedBy = prescribedBy
        self.pharmacy = pharmacy
        self.refillDate = refillDate
        self.pillsRemaining = pillsRemaining
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var needsRefill: Bool {
        if let pills = pillsRemaining, pills < 7 {
            return true
        }
        if let refill = refillDate {
            let daysUntilRefill = Calendar.current.dateComponents([.day], from: Date(), to: refill).day ?? 0
            return daysUntilRefill <= 7
        }
        return false
    }

    var displayDosage: String {
        "\(dosage) \(unit)"
    }
}

enum MedicationForm: String, Codable {
    case pill
    case capsule
    case tablet
    case liquid
    case injection
    case patch
    case inhaler
    case drops
    case cream
    case other

    var icon: String {
        switch self {
        case .pill, .capsule, .tablet: return "pills.fill"
        case .liquid: return "drop.fill"
        case .injection: return "syringe.fill"
        case .patch: return "bandage.fill"
        case .inhaler: return "lungs.fill"
        case .drops: return "drop.fill"
        case .cream: return "hand.raised.fill"
        case .other: return "cross.case.fill"
        }
    }
}

enum MedicationFrequency: String, Codable {
    case asNeeded = "as_needed"
    case daily
    case twiceDaily = "twice_daily"
    case threeTimesDaily = "three_times_daily"
    case weekly
    case biweekly
    case monthly
    case custom

    var displayText: String {
        switch self {
        case .asNeeded: return "As needed"
        case .daily: return "Once daily"
        case .twiceDaily: return "Twice daily"
        case .threeTimesDaily: return "3 times daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }
}

/// Medication log entry
struct MedicationLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let medicationId: UUID
    let medicationName: String
    var scheduledTime: Date
    var takenTime: Date?
    var status: MedicationLogStatus
    var notes: String?

    var wasTaken: Bool {
        status == .taken
    }

    var isOverdue: Bool {
        status == .pending && scheduledTime < Date()
    }
}

enum MedicationLogStatus: String, Codable {
    case pending
    case taken
    case skipped
    case snoozed
}

/// Doctor/Healthcare provider
struct HealthcareProvider: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var specialty: String?
    var practice: String?
    var phone: String?
    var email: String?
    var address: String?
    var notes: String?

    var upcomingAppointments: [HealthcareAppointment]
}

struct HealthcareAppointment: Identifiable, Codable, Hashable {
    let id: UUID
    let providerId: UUID
    var providerName: String
    var purpose: String
    var dateTime: Date
    var duration: TimeInterval
    var location: String?
    var notes: String?
    var reminderSet: Bool

    var isUpcoming: Bool {
        dateTime > Date()
    }
}
