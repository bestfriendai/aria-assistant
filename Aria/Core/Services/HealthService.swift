import Foundation
import HealthKit

/// Health service using HealthKit for health data and medication tracking
actor HealthService {
    // MARK: - HealthKit

    private let healthStore = HKHealthStore()

    // MARK: - Medication Tracking

    private var medicationsCache: [Medication] = []
    private var medicationLogsCache: [MedicationLog] = []

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.workoutType(),
            HKObjectType.activitySummaryType()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        ]

        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        return true
    }

    // MARK: - Activity Data

    func getSteps(for date: Date = Date()) async throws -> Int {
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let sum = try await querySum(for: stepsType, date: date, unit: .count())
        return Int(sum)
    }

    func getStepsThisWeek() async throws -> [DailySteps] {
        var results: [DailySteps] = []
        let calendar = Calendar.current

        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let steps = try await getSteps(for: date)
            results.append(DailySteps(date: date, count: steps))
        }

        return results
    }

    func getDistance(for date: Date = Date()) async throws -> Double {
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        return try await querySum(for: distanceType, date: date, unit: .mile())
    }

    func getActiveCalories(for date: Date = Date()) async throws -> Double {
        let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        return try await querySum(for: caloriesType, date: date, unit: .kilocalorie())
    }

    func getActivityRings(for date: Date = Date()) async throws -> ActivityRings {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let summary = summaries?.first else {
                    continuation.resume(returning: ActivityRings(
                        moveCalories: 0, moveGoal: 500,
                        exerciseMinutes: 0, exerciseGoal: 30,
                        standHours: 0, standGoal: 12
                    ))
                    return
                }

                let rings = ActivityRings(
                    moveCalories: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                    standHours: summary.appleStandHours.doubleValue(for: .count()),
                    standGoal: summary.appleStandHoursGoal.doubleValue(for: .count())
                )

                continuation.resume(returning: rings)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Heart Rate

    func getCurrentHeartRate() async throws -> Double {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        return try await queryMostRecent(for: heartRateType, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func getRestingHeartRate() async throws -> Double {
        let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        return try await queryMostRecent(for: restingHRType, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func getHeartRateVariability() async throws -> Double {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        return try await queryMostRecent(for: hrvType, unit: .secondUnit(with: .milli))
    }

    func getHeartRateHistory(days: Int = 7) async throws -> [HeartRateReading] {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let readings = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRateReading(
                        timestamp: sample.startDate,
                        bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                } ?? []

                continuation.resume(returning: readings)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Sleep

    func getSleepData(for date: Date = Date()) async throws -> SleepData {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let calendar = Calendar.current

        let startOfDay = calendar.startOfDay(for: date)
        let startOfPreviousDay = calendar.date(byAdding: .day, value: -1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfPreviousDay, end: startOfDay, options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var inBedTime: TimeInterval = 0
                var asleepTime: TimeInterval = 0
                var deepSleepTime: TimeInterval = 0
                var remSleepTime: TimeInterval = 0
                var coreSleepTime: TimeInterval = 0
                var awakeTime: TimeInterval = 0
                var sleepStart: Date?
                var sleepEnd: Date?

                for sample in (samples as? [HKCategorySample]) ?? [] {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)

                    if sleepStart == nil {
                        sleepStart = sample.startDate
                    }
                    sleepEnd = sample.endDate

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        inBedTime += duration
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        asleepTime += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        coreSleepTime += duration
                        asleepTime += duration
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deepSleepTime += duration
                        asleepTime += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        remSleepTime += duration
                        asleepTime += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakeTime += duration
                    default:
                        break
                    }
                }

                let sleepData = SleepData(
                    date: date,
                    inBedDuration: inBedTime,
                    asleepDuration: asleepTime,
                    deepSleepDuration: deepSleepTime,
                    remSleepDuration: remSleepTime,
                    coreSleepDuration: coreSleepTime,
                    awakeDuration: awakeTime,
                    sleepStart: sleepStart,
                    sleepEnd: sleepEnd
                )

                continuation.resume(returning: sleepData)
            }

            healthStore.execute(query)
        }
    }

    func getSleepHistory(days: Int = 7) async throws -> [SleepData] {
        var results: [SleepData] = []
        let calendar = Calendar.current

        for dayOffset in (0..<days).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date())!
            let sleep = try await getSleepData(for: date)
            results.append(sleep)
        }

        return results
    }

    // MARK: - Body Measurements

    func getWeight() async throws -> Double {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        return try await queryMostRecent(for: weightType, unit: .pound())
    }

    func getHeight() async throws -> Double {
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        return try await queryMostRecent(for: heightType, unit: .inch())
    }

    func getBMI() async throws -> Double {
        let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex)!
        return try await queryMostRecent(for: bmiType, unit: .count())
    }

    // MARK: - Vitals

    func getBloodPressure() async throws -> BloodPressure {
        let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
        let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!

        let systolic = try await queryMostRecent(for: systolicType, unit: .millimeterOfMercury())
        let diastolic = try await queryMostRecent(for: diastolicType, unit: .millimeterOfMercury())

        return BloodPressure(systolic: Int(systolic), diastolic: Int(diastolic), timestamp: Date())
    }

    func getBloodOxygen() async throws -> Double {
        let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
        return try await queryMostRecent(for: oxygenType, unit: .percent()) * 100
    }

    func getBloodGlucose() async throws -> Double {
        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
        return try await queryMostRecent(for: glucoseType, unit: HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)))
    }

    // MARK: - Workouts

    func getWorkouts(days: Int = 7) async throws -> [WorkoutData] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout])?.map { workout in
                    WorkoutData(
                        activityType: self.mapWorkoutType(workout.workoutActivityType),
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        totalCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        totalDistance: workout.totalDistance?.doubleValue(for: .mile()),
                        averageHeartRate: nil // Would need separate query
                    )
                } ?? []

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    private func mapWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hiking"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        default: return "Workout"
        }
    }

    // MARK: - Water Tracking

    func logWater(ounces: Double) async throws {
        let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
        let quantity = HKQuantity(unit: .fluidOunceUS(), doubleValue: ounces)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: Date(), end: Date())

        try await healthStore.save(sample)
    }

    func getWaterIntake(for date: Date = Date()) async throws -> Double {
        let waterType = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
        return try await querySum(for: waterType, date: date, unit: .fluidOunceUS())
    }

    // MARK: - Mindfulness

    func logMindfulMinutes(minutes: Double) async throws {
        let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-minutes * 60)

        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: startDate,
            end: endDate
        )

        try await healthStore.save(sample)
    }

    func getMindfulMinutes(for date: Date = Date()) async throws -> Double {
        let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let totalSeconds = (samples ?? []).reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate)
                }

                continuation.resume(returning: totalSeconds / 60)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Medications

    func addMedication(_ medication: Medication) async {
        medicationsCache.append(medication)
    }

    func getMedications() async -> [Medication] {
        medicationsCache
    }

    func removeMedication(id: UUID) async {
        medicationsCache.removeAll { $0.id == id }
    }

    func logMedicationTaken(_ medication: Medication, at time: Date = Date()) async {
        let log = MedicationLog(
            medicationId: medication.id,
            takenAt: time,
            dosage: medication.dosage
        )
        medicationLogsCache.append(log)
    }

    func getMedicationLogs(for date: Date = Date()) async -> [MedicationLog] {
        let calendar = Calendar.current
        return medicationLogsCache.filter { calendar.isDate($0.takenAt, inSameDayAs: date) }
    }

    func getDueMedications() async -> [Medication] {
        let now = Date()
        let calendar = Calendar.current
        let todayLogs = await getMedicationLogs(for: now)

        return medicationsCache.filter { medication in
            // Check if already taken today based on schedule
            let takenToday = todayLogs.filter { $0.medicationId == medication.id }

            for scheduleTime in medication.schedule {
                let scheduledComponents = calendar.dateComponents([.hour, .minute], from: scheduleTime)
                var todayScheduled = calendar.dateComponents([.year, .month, .day], from: now)
                todayScheduled.hour = scheduledComponents.hour
                todayScheduled.minute = scheduledComponents.minute

                guard let scheduledDate = calendar.date(from: todayScheduled) else { continue }

                // Check if this dose was already taken
                let taken = takenToday.contains { log in
                    abs(log.takenAt.timeIntervalSince(scheduledDate)) < 3600 // Within 1 hour
                }

                if !taken && scheduledDate <= now.addingTimeInterval(3600) && scheduledDate >= now.addingTimeInterval(-3600) {
                    return true
                }
            }

            return false
        }
    }

    // MARK: - Health Summary

    func getDailySummary(for date: Date = Date()) async throws -> HealthSummary {
        async let steps = getSteps(for: date)
        async let distance = getDistance(for: date)
        async let calories = getActiveCalories(for: date)
        async let rings = getActivityRings(for: date)
        async let sleep = getSleepData(for: date)
        async let water = getWaterIntake(for: date)
        async let mindful = getMindfulMinutes(for: date)

        return try await HealthSummary(
            date: date,
            steps: steps,
            distance: distance,
            activeCalories: calories,
            activityRings: rings,
            sleepData: sleep,
            waterOunces: water,
            mindfulMinutes: mindful
        )
    }

    // MARK: - Query Helpers

    private func querySum(for type: HKQuantityType, date: Date, unit: HKUnit) async throws -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }

            healthStore.execute(query)
        }
    }

    private func queryMostRecent(for type: HKQuantityType, unit: HKUnit) async throws -> Double {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 0)
                    return
                }

                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - Models

struct DailySteps: Identifiable {
    let id: UUID = UUID()
    let date: Date
    let count: Int
}

struct ActivityRings {
    let moveCalories: Double
    let moveGoal: Double
    let exerciseMinutes: Double
    let exerciseGoal: Double
    let standHours: Double
    let standGoal: Double

    var moveProgress: Double { moveGoal > 0 ? moveCalories / moveGoal : 0 }
    var exerciseProgress: Double { exerciseGoal > 0 ? exerciseMinutes / exerciseGoal : 0 }
    var standProgress: Double { standGoal > 0 ? standHours / standGoal : 0 }
}

struct HeartRateReading: Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let bpm: Double
}

struct SleepData: Identifiable {
    let id: UUID = UUID()
    let date: Date
    let inBedDuration: TimeInterval
    let asleepDuration: TimeInterval
    let deepSleepDuration: TimeInterval
    let remSleepDuration: TimeInterval
    let coreSleepDuration: TimeInterval
    let awakeDuration: TimeInterval
    let sleepStart: Date?
    let sleepEnd: Date?

    var totalHours: Double { asleepDuration / 3600 }
    var efficiency: Double {
        guard inBedDuration > 0 else { return 0 }
        return asleepDuration / inBedDuration * 100
    }
}

struct BloodPressure: Identifiable {
    let id: UUID = UUID()
    let systolic: Int
    let diastolic: Int
    let timestamp: Date

    var category: String {
        if systolic < 120 && diastolic < 80 {
            return "Normal"
        } else if systolic < 130 && diastolic < 80 {
            return "Elevated"
        } else if systolic < 140 || diastolic < 90 {
            return "High (Stage 1)"
        } else {
            return "High (Stage 2)"
        }
    }
}

struct WorkoutData: Identifiable {
    let id: UUID = UUID()
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalCalories: Double
    let totalDistance: Double?
    let averageHeartRate: Double?

    var durationMinutes: Double { duration / 60 }
}

struct Medication: Identifiable, Codable {
    let id: UUID
    var name: String
    var dosage: String
    var schedule: [Date] // Times of day to take
    var instructions: String?
    var refillDate: Date?
    var prescriber: String?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        schedule: [Date] = [],
        instructions: String? = nil,
        refillDate: Date? = nil,
        prescriber: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.schedule = schedule
        self.instructions = instructions
        self.refillDate = refillDate
        self.prescriber = prescriber
        self.isActive = isActive
    }
}

struct MedicationLog: Identifiable, Codable {
    let id: UUID = UUID()
    let medicationId: UUID
    let takenAt: Date
    let dosage: String
}

struct HealthSummary {
    let date: Date
    let steps: Int
    let distance: Double
    let activeCalories: Double
    let activityRings: ActivityRings
    let sleepData: SleepData
    let waterOunces: Double
    let mindfulMinutes: Double
}

// MARK: - Errors

enum HealthServiceError: Error, LocalizedError {
    case notAuthorized
    case dataNotAvailable
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Health data access not authorized"
        case .dataNotAvailable: return "Health data not available"
        case .queryFailed: return "Health query failed"
        }
    }
}
