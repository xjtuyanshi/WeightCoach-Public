import Foundation

enum HistoricalBodyDataSource: String, Equatable, Sendable {
    case healthKit
    case localRecord
    case calibratedProfile
    case goalProfileFallback
}

struct HistoricalBodyPoint: Equatable, Sendable {
    let date: Date
    let value: Double
}

struct HistoricalTrendFood: Equatable, Sendable {
    let date: Date
    let calories: Double
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?

    init(
        date: Date,
        calories: Double,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?
    ) {
        self.date = date
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }

    init(_ entry: FoodEntry) {
        self.init(
            date: entry.date,
            calories: entry.calories,
            proteinG: entry.protein,
            carbsG: entry.carbs,
            fatG: entry.fat
        )
    }
}

struct HistoricalTrendExercise: Equatable, Sendable {
    let interval: ExerciseEnergyInterval

    init(interval: ExerciseEnergyInterval) {
        self.interval = interval
    }

    init(_ entry: ExerciseEntry) {
        self.init(interval: entry.energyInterval)
    }
}

struct DailyActiveEnergyReading: Equatable, Sendable {
    let dayStart: Date
    let kcal: Double?

    init(dayStart: Date, kcal: Double?) {
        self.dayStart = dayStart
        if let kcal, kcal.isFinite, kcal >= 0 {
            self.kcal = kcal
        } else {
            self.kcal = nil
        }
    }
}

struct HistoricalTrendHealthData: Equatable, Sendable {
    let dailyActiveEnergy: [DailyActiveEnergyReading]
    let activeEnergyIntervals: [HealthActiveEnergyInterval]
    let weightPoints: [HistoricalBodyPoint]
    let bodyFatPoints: [HistoricalBodyPoint]
    let manualOverlapDataAvailable: Bool

    static let empty = HistoricalTrendHealthData(
        dailyActiveEnergy: [],
        activeEnergyIntervals: [],
        weightPoints: [],
        bodyFatPoints: [],
        manualOverlapDataAvailable: true
    )
}

struct HistoricalTrendConfiguration: Equatable, Sendable {
    let heightCm: Double
    let age: Int
    let isMale: Bool
    let activityFactor: Double
    let includeActiveEnergy: Bool
    let fallbackWeightKg: Double
    let calibratedBodyFatPercent: Double?
    let calibratedBodyFatMeasuredAt: Date?
}

struct DailyHistoricalTrendPoint: Identifiable, Equatable, Sendable {
    var id: Date { dayStart }

    let dayStart: Date
    let intakeKcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let completeMacroCoverage: Double?
    let foodEntryCount: Int
    let estimatedExpenditureKcal: Double?
    /// 正数表示估算缺口，负数表示估算盈余。
    let energyBalanceKcal: Double?
    let healthActiveEnergyKcal: Double?
    let manualSupplementKcal: Double
    let weightKg: Double
    let weightSource: HistoricalBodyDataSource
    let bodyFatPercent: Double?
    let bodyFatSource: HistoricalBodyDataSource?
    let isCompleteDay: Bool
    let usesHealthActiveEnergy: Bool
}

struct HistoricalTrendResult: Equatable, Sendable {
    let points: [DailyHistoricalTrendPoint]

    func suffix(days: Int) -> HistoricalTrendResult {
        HistoricalTrendResult(points: Array(points.suffix(max(0, days))))
    }

    func weeklySummary(
        referenceDate: Date,
        calendar: Calendar
    ) -> HistoricalTrendWeeklySummary {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: todayStart)
        let daysSinceMonday = (weekday + 5) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: todayStart
        ) ?? todayStart
        let completed = points.filter {
            $0.dayStart >= weekStart
                && $0.dayStart < todayStart
                && $0.isCompleteDay
        }
        let eligibleBalances = completed.compactMap(\.energyBalanceKcal)

        return HistoricalTrendWeeklySummary(
            weekStart: weekStart,
            throughDate: calendar.date(byAdding: .day, value: -1, to: todayStart),
            cumulativeEnergyBalanceKcal: eligibleBalances.isEmpty
                ? nil
                : eligibleBalances.reduce(0, +),
            completedDayCount: completed.count,
            eligibleDayCount: eligibleBalances.count,
            foodRecordedDayCount: completed.filter { $0.foodEntryCount > 0 }.count,
            expenditureKnownDayCount: completed.filter {
                $0.estimatedExpenditureKcal != nil
            }.count
        )
    }
}

struct HistoricalTrendWeeklySummary: Equatable, Sendable {
    let weekStart: Date
    let throughDate: Date?
    let cumulativeEnergyBalanceKcal: Double?
    let completedDayCount: Int
    let eligibleDayCount: Int
    let foodRecordedDayCount: Int
    let expenditureKnownDayCount: Int
}

enum HistoricalTrendEngine {
    static func calculate(
        from startDate: Date,
        to endDate: Date,
        referenceDate: Date,
        calendar: Calendar,
        configuration: HistoricalTrendConfiguration,
        foods: [HistoricalTrendFood],
        exercises: [HistoricalTrendExercise],
        localWeights: [HistoricalBodyPoint],
        localBodyFat: [HistoricalBodyPoint],
        healthData: HistoricalTrendHealthData
    ) -> HistoricalTrendResult {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard end > start else { return HistoricalTrendResult(points: []) }

        let todayStart = calendar.startOfDay(for: referenceDate)
        let activeByDay = Dictionary(
            healthData.dailyActiveEnergy.map {
                (calendar.startOfDay(for: $0.dayStart), $0.kcal)
            },
            uniquingKeysWith: { _, newest in newest }
        )

        var points: [DailyHistoricalTrendPoint] = []
        var dayStart = start
        while dayStart < end {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  dayEnd > dayStart else {
                break
            }

            let dayInterval = DateInterval(start: dayStart, end: dayEnd)
            let dayFoods = foods.filter {
                $0.date >= dayStart && $0.date < dayEnd
            }
            let nutrition = nutritionSummary(dayFoods)
            let dayExercises = exercises.filter {
                $0.interval.startDate < dayEnd && $0.interval.endDate > dayStart
            }

            let weight = resolveWeight(
                before: dayEnd,
                healthPoints: healthData.weightPoints,
                localPoints: localWeights,
                fallback: configuration.fallbackWeightKg
            )
            let bodyFat = resolveBodyFat(
                before: dayEnd,
                healthPoints: healthData.bodyFatPoints,
                localPoints: localBodyFat,
                calibratedPercent: configuration.calibratedBodyFatPercent,
                calibratedMeasuredAt: configuration.calibratedBodyFatMeasuredAt,
                allowUndatedCalibration: dayStart >= todayStart
            )
            let bmr = CalorieEngine.bmr(
                weightKg: weight.value,
                heightCm: configuration.heightCm,
                age: configuration.age,
                isMale: configuration.isMale,
                bodyFatPercent: bodyFat?.value
            )

            let healthActiveEnergy = activeByDay[dayStart] ?? nil
            let canCalculateManualSupplement =
                dayExercises.isEmpty || healthData.manualOverlapDataAvailable
            let manualSummary = canCalculateManualSupplement
                ? ManualExerciseSupplementEngine.calculateTotal(
                    exercises: dayExercises.map(\.interval),
                    healthSamples: healthData.activeEnergyIntervals.map(
                        HealthActiveEnergySample.init
                    ),
                    within: dayInterval
                )
                : ManualExerciseSupplement(
                    estimatedActiveEnergyKcal: 0,
                    overlappingHealthEnergyKcal: 0,
                    supplementalActiveEnergyKcal: 0
                )

            let expenditure: Double?
            if configuration.includeActiveEnergy {
                if let healthActiveEnergy, canCalculateManualSupplement {
                    expenditure = CalorieEngine.tdee(
                        bmr: bmr,
                        activityFactor: configuration.activityFactor,
                        activeEnergyKcal: healthActiveEnergy
                            + manualSummary.supplementalActiveEnergyKcal,
                        includeActiveEnergy: true
                    )
                } else {
                    expenditure = nil
                }
            } else {
                expenditure = CalorieEngine.tdee(
                    bmr: bmr,
                    activityFactor: configuration.activityFactor,
                    activeEnergyKcal: 0,
                    includeActiveEnergy: false
                )
            }

            let isCompleteDay = dayEnd <= todayStart
            let balance: Double?
            if isCompleteDay,
               let intake = nutrition.intakeKcal,
               let expenditure {
                let value = expenditure - intake
                balance = value.isFinite ? value : nil
            } else {
                balance = nil
            }

            points.append(
                DailyHistoricalTrendPoint(
                    dayStart: dayStart,
                    intakeKcal: nutrition.intakeKcal,
                    proteinG: nutrition.proteinG,
                    carbsG: nutrition.carbsG,
                    fatG: nutrition.fatG,
                    completeMacroCoverage: nutrition.completeMacroCoverage,
                    foodEntryCount: dayFoods.count,
                    estimatedExpenditureKcal: expenditure,
                    energyBalanceKcal: balance,
                    healthActiveEnergyKcal: healthActiveEnergy,
                    manualSupplementKcal: manualSummary.supplementalActiveEnergyKcal,
                    weightKg: weight.value,
                    weightSource: weight.source,
                    bodyFatPercent: bodyFat?.value,
                    bodyFatSource: bodyFat?.source,
                    isCompleteDay: isCompleteDay,
                    usesHealthActiveEnergy: configuration.includeActiveEnergy
                )
            )
            dayStart = dayEnd
        }

        return HistoricalTrendResult(points: points)
    }

    private struct ResolvedBodyValue {
        let value: Double
        let source: HistoricalBodyDataSource
    }

    private struct NutritionSummary {
        let intakeKcal: Double?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        let completeMacroCoverage: Double?
    }

    private static func resolveWeight(
        before date: Date,
        healthPoints: [HistoricalBodyPoint],
        localPoints: [HistoricalBodyPoint],
        fallback: Double
    ) -> ResolvedBodyValue {
        let health = latestValid(
            healthPoints,
            before: date,
            validator: validWeight
        )
        let local = latestValid(
            localPoints,
            before: date,
            validator: validWeight
        )

        switch (health, local) {
        case let (health?, local?):
            if health.date >= local.date {
                return ResolvedBodyValue(
                    value: health.value,
                    source: .healthKit
                )
            }
            return ResolvedBodyValue(value: local.value, source: .localRecord)
        case let (health?, nil):
            return ResolvedBodyValue(value: health.value, source: .healthKit)
        case let (nil, local?):
            return ResolvedBodyValue(value: local.value, source: .localRecord)
        default:
            let safeFallback = validWeight(fallback) ? fallback : 70
            return ResolvedBodyValue(
                value: safeFallback,
                source: .goalProfileFallback
            )
        }
    }

    private static func resolveBodyFat(
        before date: Date,
        healthPoints: [HistoricalBodyPoint],
        localPoints: [HistoricalBodyPoint],
        calibratedPercent: Double?,
        calibratedMeasuredAt: Date?,
        allowUndatedCalibration: Bool
    ) -> ResolvedBodyValue? {
        if let health = latestValid(
            healthPoints,
            before: date,
            validator: validBodyFat
        ) {
            return ResolvedBodyValue(
                value: health.value,
                source: .healthKit
            )
        }
        if let local = latestValid(
            localPoints,
            before: date,
            validator: validBodyFat
        ) {
            return ResolvedBodyValue(
                value: local.value,
                source: .localRecord
            )
        }
        if let calibratedPercent, validBodyFat(calibratedPercent) {
            let calibrationIsAvailable =
                calibratedMeasuredAt.map { $0 < date }
                ?? allowUndatedCalibration
            guard calibrationIsAvailable else { return nil }
            return ResolvedBodyValue(
                value: calibratedPercent,
                source: .calibratedProfile
            )
        }
        return nil
    }

    private static func latestValid(
        _ points: [HistoricalBodyPoint],
        before date: Date,
        validator: (Double) -> Bool
    ) -> HistoricalBodyPoint? {
        points
            .filter { $0.date < date && validator($0.value) }
            .max { lhs, rhs in lhs.date < rhs.date }
    }

    private static func nutritionSummary(
        _ foods: [HistoricalTrendFood]
    ) -> NutritionSummary {
        guard !foods.isEmpty else {
            return NutritionSummary(
                intakeKcal: nil,
                proteinG: nil,
                carbsG: nil,
                fatG: nil,
                completeMacroCoverage: nil
            )
        }

        let totalCalories = foods.reduce(0) {
            $0 + validCalories($1.calories)
        }
        let completeCalories = foods.reduce(0) { partial, food in
            guard validMacro(food.proteinG) != nil,
                  validMacro(food.carbsG) != nil,
                  validMacro(food.fatG) != nil else {
                return partial
            }
            return partial + validCalories(food.calories)
        }
        let coverage: Double
        if totalCalories > 0 {
            coverage = min(max(completeCalories / totalCalories, 0), 1)
        } else {
            let completeCount = foods.filter {
                validMacro($0.proteinG) != nil
                    && validMacro($0.carbsG) != nil
                    && validMacro($0.fatG) != nil
            }.count
            coverage = Double(completeCount) / Double(foods.count)
        }

        return NutritionSummary(
            intakeKcal: totalCalories,
            proteinG: sumKnown(foods.compactMap { validMacro($0.proteinG) }),
            carbsG: sumKnown(foods.compactMap { validMacro($0.carbsG) }),
            fatG: sumKnown(foods.compactMap { validMacro($0.fatG) }),
            completeMacroCoverage: coverage
        )
    }

    private static func sumKnown(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let result = values.reduce(0, +)
        return result.isFinite ? result : nil
    }

    private static func validCalories(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func validMacro(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func validWeight(_ value: Double) -> Bool {
        value.isFinite && value > 20 && value < 400
    }

    private static func validBodyFat(_ value: Double) -> Bool {
        value.isFinite && value > 3 && value < 70
    }
}
