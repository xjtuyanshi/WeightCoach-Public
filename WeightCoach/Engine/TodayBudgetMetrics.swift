import Foundation

/// 汇总仪表盘和 Widget 共用的当日热量数据。
///
/// 这里复用 `CalorieEngine` 的既有路径，不在 Widget 侧另建计算模型。
struct TodayBudgetMetrics {
    let currentWeight: Double
    let currentBodyFat: Double?
    let bodyFatSource: BodyFatSource?
    let bmr: Double
    let tdee: Double
    let deficit: Double
    let budget: Double
    let consumed: Double
    let healthActiveEnergy: Double
    let manualExerciseEstimatedEnergy: Double
    let manualExerciseHealthOverlap: Double
    let manualExerciseSupplementalEnergy: Double
    let effectiveActiveEnergy: Double

    static func calculate(
        profile: ProfileStore,
        health: HealthKitManager,
        todayFoods: [FoodEntry],
        localWeights: [WeightEntry],
        exercises: [ExerciseEntry] = [],
        referenceDate: Date = .now
    ) -> TodayBudgetMetrics {
        let healthWeight: (date: Date, value: Double)? = {
            guard let value = health.latestWeightKg, let date = health.latestWeightDate else {
                return nil
            }
            return (date, value)
        }()
        let localWeight = localWeights.first.map { (date: $0.date, value: $0.weightKg) }

        let currentWeight: Double
        switch (healthWeight, localWeight) {
        case let (health?, local?):
            currentWeight = health.date >= local.date ? health.value : local.value
        case let (health?, nil):
            currentWeight = health.value
        case let (nil, local?):
            currentWeight = local.value
        default:
            currentWeight = profile.goalStartWeight
        }

        let resolvedBodyFat = BodyFatResolver.resolve(
            healthKitPercent: health.latestBodyFatPercent,
            localWeights: localWeights,
            calibratedMeasurement: profile.bodyComposition.calibratedBodyFatPercent
        )
        let currentBodyFat = resolvedBodyFat?.percent
        let isMale = health.isMale ?? profile.isMale
        let bmr = CalorieEngine.bmr(
            weightKg: currentWeight,
            heightCm: health.heightCm ?? profile.heightCm,
            age: health.ageYears ?? profile.age,
            isMale: isMale,
            bodyFatPercent: currentBodyFat
        )
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: referenceDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let exerciseSummary = ManualExerciseSupplementEngine.calculateTotal(
            exercises: exercises.map(\.energyInterval),
            healthSamples: health.todayActiveEnergyIntervals.map(HealthActiveEnergySample.init),
            within: DateInterval(start: dayStart, end: dayEnd)
        )
        let healthActiveEnergy = health.todayActiveEnergyKcal.isFinite
            ? max(0, health.todayActiveEnergyKcal)
            : 0
        let effectiveActiveEnergy = healthActiveEnergy
            + (profile.includeActiveEnergy
                ? exerciseSummary.supplementalActiveEnergyKcal
                : 0)
        let tdee = CalorieEngine.tdee(
            bmr: bmr,
            activityFactor: profile.activityFactor,
            activeEnergyKcal: effectiveActiveEnergy,
            includeActiveEnergy: profile.includeActiveEnergy
        )
        let deficit = CalorieEngine.dailyDeficit(
            currentWeightKg: currentWeight,
            goalWeightKg: profile.goalWeight,
            goalEndDate: profile.goalEndDate
        )
        let budget = CalorieEngine.dailyBudget(tdee: tdee, deficit: deficit, isMale: isMale)
        let consumed = todayFoods.reduce(0) { $0 + $1.calories }

        return TodayBudgetMetrics(
            currentWeight: currentWeight,
            currentBodyFat: currentBodyFat,
            bodyFatSource: resolvedBodyFat?.source,
            bmr: bmr,
            tdee: tdee,
            deficit: deficit,
            budget: budget,
            consumed: consumed,
            healthActiveEnergy: healthActiveEnergy,
            manualExerciseEstimatedEnergy: exerciseSummary.estimatedActiveEnergyKcal,
            manualExerciseHealthOverlap: exerciseSummary.overlappingHealthEnergyKcal,
            manualExerciseSupplementalEnergy: exerciseSummary.supplementalActiveEnergyKcal,
            effectiveActiveEnergy: effectiveActiveEnergy
        )
    }
}
