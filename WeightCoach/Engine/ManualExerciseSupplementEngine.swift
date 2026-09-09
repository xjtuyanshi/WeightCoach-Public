import Foundation

struct ExerciseEnergyInterval: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let estimatedActiveEnergyKcal: Double
    let activityType: ExerciseActivityType?

    init(
        startDate: Date,
        endDate: Date,
        estimatedActiveEnergyKcal: Double,
        activityType: ExerciseActivityType? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.estimatedActiveEnergyKcal = estimatedActiveEnergyKcal
        self.activityType = activityType
    }

    init(
        startDate: Date,
        durationMinutes: Double,
        estimatedActiveEnergyKcal: Double,
        activityType: ExerciseActivityType? = nil
    ) {
        let endDate = durationMinutes.isFinite
            ? startDate.addingTimeInterval(durationMinutes * 60)
            : startDate
        self.init(
            startDate: startDate,
            endDate: endDate,
            estimatedActiveEnergyKcal: estimatedActiveEnergyKcal,
            activityType: activityType
        )
    }
}

/// HealthKit 中一条运动记录的纯值快照。
///
/// 只有运动类型匹配且确实带有活动能量的记录，才足以证明手动运动的相应时段
/// 已被另一数据源覆盖。运动总热量不会在这里再次相加。
struct HealthWorkoutInterval: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let activityType: ExerciseActivityType?
    let hasActiveEnergy: Bool
}

/// HealthKit 活动能量样本的纯数据表示，避免计算层依赖 HealthKit。
///
/// `startDate == endDate` 表示点样本：时间点落在运动区间内时扣除整笔能量。
struct HealthActiveEnergySample: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let energyKcal: Double

    init(startDate: Date, endDate: Date, energyKcal: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.energyKcal = energyKcal
    }

    init(date: Date, energyKcal: Double) {
        self.init(startDate: date, endDate: date, energyKcal: energyKcal)
    }

    init(_ interval: HealthActiveEnergyInterval) {
        self.init(
            startDate: interval.startDate,
            endDate: interval.endDate,
            energyKcal: interval.kcal
        )
    }
}

struct ManualExerciseSupplement: Equatable, Sendable {
    let estimatedActiveEnergyKcal: Double
    let overlappingHealthEnergyKcal: Double
    let supplementalActiveEnergyKcal: Double
    let healthWorkoutCoveredMinutes: Double
    let usedHealthWorkoutCoverage: Bool

    init(
        estimatedActiveEnergyKcal: Double,
        overlappingHealthEnergyKcal: Double,
        supplementalActiveEnergyKcal: Double,
        healthWorkoutCoveredMinutes: Double = 0,
        usedHealthWorkoutCoverage: Bool = false
    ) {
        self.estimatedActiveEnergyKcal = estimatedActiveEnergyKcal
        self.overlappingHealthEnergyKcal = overlappingHealthEnergyKcal
        self.supplementalActiveEnergyKcal = supplementalActiveEnergyKcal
        self.healthWorkoutCoveredMinutes = healthWorkoutCoveredMinutes
        self.usedHealthWorkoutCoverage = usedHealthWorkoutCoverage
    }
}

enum ManualExerciseSupplementEngine {
    /// 计算一条手动运动记录仍需补入 TDEE 的活动能量。
    ///
    /// 同类型且带活动能量的 HealthKit workout 是高置信覆盖证据：此时只按
    /// 未覆盖时长补入 MET 估算。没有这种 workout 时，继续使用合并后的活动
    /// 能量差额作为回退。传入 `queryInterval` 时，运动估算值、样本和 workout
    /// 都会裁剪到该查询范围，适合跨午夜记录按天汇总。
    static func calculate(
        exercise: ExerciseEnergyInterval,
        healthSamples: [HealthActiveEnergySample],
        healthWorkouts: [HealthWorkoutInterval] = [],
        within queryInterval: DateInterval? = nil
    ) -> ManualExerciseSupplement {
        guard let validated = validatedExercise(exercise, within: queryInterval) else {
            return ManualExerciseSupplement(
                estimatedActiveEnergyKcal: 0,
                overlappingHealthEnergyKcal: 0,
                supplementalActiveEnergyKcal: 0
            )
        }

        let overlappingHealthEnergy = healthSamples.reduce(0.0) { partial, sample in
            partial + overlappingEnergy(
                sample: sample,
                exerciseInterval: validated.clippedInterval,
                queryInterval: queryInterval
            )
        }
        let finiteHealthEnergy = overlappingHealthEnergy.isFinite
            ? max(0, overlappingHealthEnergy)
            : 0

        let workoutCoveredDuration = matchingWorkoutCoveredDuration(
            exercise: exercise,
            clippedExerciseInterval: validated.clippedInterval,
            healthWorkouts: healthWorkouts
        )
        let usesWorkoutCoverage = workoutCoveredDuration > 0
        let supplement: Double
        if usesWorkoutCoverage {
            let totalDuration = validated.clippedInterval.duration
            let uncoveredDuration = max(0, totalDuration - workoutCoveredDuration)
            let uncoveredDurationEstimate = totalDuration > 0
                ? validated.clippedEstimatedEnergy * uncoveredDuration / totalDuration
                : 0
            let energyDifferenceFallback = max(
                0,
                validated.clippedEstimatedEnergy - finiteHealthEnergy
            )
            // Workout 时间覆盖和活动能量覆盖是两份独立证据。部分 workout
            // 不能让已经由同区间活动能量覆盖的剩余时段再次补入，因此取两种
            // 保守上限中的较小值；完整 workout 覆盖仍然严格为 0。
            supplement = min(uncoveredDurationEstimate, energyDifferenceFallback)
        } else {
            // 没有可信 workout 身份时，保留原有的活动能量差额回退路径。
            supplement = max(0, validated.clippedEstimatedEnergy - finiteHealthEnergy)
        }

        return ManualExerciseSupplement(
            estimatedActiveEnergyKcal: validated.clippedEstimatedEnergy,
            overlappingHealthEnergyKcal: finiteHealthEnergy,
            supplementalActiveEnergyKcal: supplement.isFinite ? supplement : 0,
            healthWorkoutCoveredMinutes: workoutCoveredDuration / 60,
            usedHealthWorkoutCoverage: usesWorkoutCoverage
        )
    }

    /// 汇总多条互不重叠的本地运动记录。录入层应拒绝重叠记录。
    static func calculateTotal(
        exercises: [ExerciseEnergyInterval],
        healthSamples: [HealthActiveEnergySample],
        healthWorkouts: [HealthWorkoutInterval] = [],
        within queryInterval: DateInterval? = nil
    ) -> ManualExerciseSupplement {
        exercises.reduce(
            ManualExerciseSupplement(
                estimatedActiveEnergyKcal: 0,
                overlappingHealthEnergyKcal: 0,
                supplementalActiveEnergyKcal: 0
            )
        ) { total, exercise in
            let item = calculate(
                exercise: exercise,
                healthSamples: healthSamples,
                healthWorkouts: healthWorkouts,
                within: queryInterval
            )
            return ManualExerciseSupplement(
                estimatedActiveEnergyKcal: finiteSum(
                    total.estimatedActiveEnergyKcal,
                    item.estimatedActiveEnergyKcal
                ),
                overlappingHealthEnergyKcal: finiteSum(
                    total.overlappingHealthEnergyKcal,
                    item.overlappingHealthEnergyKcal
                ),
                supplementalActiveEnergyKcal: finiteSum(
                    total.supplementalActiveEnergyKcal,
                    item.supplementalActiveEnergyKcal
                ),
                healthWorkoutCoveredMinutes: finiteSum(
                    total.healthWorkoutCoveredMinutes,
                    item.healthWorkoutCoveredMinutes
                ),
                usedHealthWorkoutCoverage: total.usedHealthWorkoutCoverage
                    || item.usedHealthWorkoutCoverage
            )
        }
    }

    static func overlaps(
        startDate: Date,
        durationMinutes: Double,
        existingExercises: [ExerciseEnergyInterval]
    ) -> Bool {
        guard isFinite(startDate),
              durationMinutes.isFinite,
              durationMinutes > 0 else {
            return false
        }
        let candidateEnd = startDate.addingTimeInterval(durationMinutes * 60)
        guard isFinite(candidateEnd), candidateEnd > startDate else { return false }

        return existingExercises.contains { existing in
            isFinite(existing.startDate)
                && isFinite(existing.endDate)
                && existing.startDate < candidateEnd
                && existing.endDate > startDate
        }
    }

    private struct ValidatedExercise {
        let clippedInterval: DateInterval
        let clippedEstimatedEnergy: Double
    }

    private static func validatedExercise(
        _ exercise: ExerciseEnergyInterval,
        within queryInterval: DateInterval?
    ) -> ValidatedExercise? {
        guard isFinite(exercise.startDate),
              isFinite(exercise.endDate),
              exercise.endDate > exercise.startDate,
              exercise.estimatedActiveEnergyKcal.isFinite,
              exercise.estimatedActiveEnergyKcal >= 0 else {
            return nil
        }

        let original = DateInterval(start: exercise.startDate, end: exercise.endDate)
        let clipped: DateInterval
        if let queryInterval {
            guard isFinite(queryInterval.start),
                  isFinite(queryInterval.end),
                  queryInterval.duration.isFinite,
                  queryInterval.duration > 0,
                  let intersection = original.intersection(with: queryInterval),
                  intersection.duration > 0 else {
                return nil
            }
            clipped = intersection
        } else {
            clipped = original
        }

        let clippedEnergy = exercise.estimatedActiveEnergyKcal
            * clipped.duration / original.duration
        guard clippedEnergy.isFinite, clippedEnergy >= 0 else { return nil }

        return ValidatedExercise(
            clippedInterval: clipped,
            clippedEstimatedEnergy: clippedEnergy
        )
    }

    private static func overlappingEnergy(
        sample: HealthActiveEnergySample,
        exerciseInterval: DateInterval,
        queryInterval: DateInterval?
    ) -> Double {
        guard isFinite(sample.startDate),
              isFinite(sample.endDate),
              sample.energyKcal.isFinite,
              sample.energyKcal >= 0 else {
            return 0
        }

        if sample.startDate == sample.endDate {
            guard containsHalfOpen(exerciseInterval, date: sample.startDate) else {
                return 0
            }
            if let queryInterval,
               !containsHalfOpen(queryInterval, date: sample.startDate) {
                return 0
            }
            return sample.energyKcal
        }

        guard sample.endDate > sample.startDate else { return 0 }
        let sampleInterval = DateInterval(start: sample.startDate, end: sample.endDate)

        var relevantInterval = exerciseInterval
        if let queryInterval {
            guard let clippedExercise = relevantInterval.intersection(with: queryInterval),
                  clippedExercise.duration > 0 else {
                return 0
            }
            relevantInterval = clippedExercise
        }

        guard let overlap = sampleInterval.intersection(with: relevantInterval),
              overlap.duration > 0 else {
            return 0
        }

        let fraction = min(1, max(0, overlap.duration / sampleInterval.duration))
        let result = sample.energyKcal * fraction
        return result.isFinite ? result : 0
    }

    private static func matchingWorkoutCoveredDuration(
        exercise: ExerciseEnergyInterval,
        clippedExerciseInterval: DateInterval,
        healthWorkouts: [HealthWorkoutInterval]
    ) -> TimeInterval {
        guard let activityType = exercise.activityType else { return 0 }

        let matchingIntervals = healthWorkouts.compactMap { workout -> DateInterval? in
            guard workout.hasActiveEnergy,
                  workout.activityType == activityType,
                  isFinite(workout.startDate),
                  isFinite(workout.endDate),
                  workout.endDate > workout.startDate else {
                return nil
            }
            guard let overlap = DateInterval(
                start: workout.startDate,
                end: workout.endDate
            ).intersection(with: clippedExerciseInterval),
                overlap.duration.isFinite,
                overlap.duration > 0 else {
                return nil
            }
            return overlap
        }
        guard !matchingIntervals.isEmpty else { return 0 }

        let sorted = matchingIntervals.sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
        var merged: [DateInterval] = []
        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }

        let covered = merged.reduce(0.0) { partial, interval in
            finiteSum(partial, interval.duration)
        }
        guard covered.isFinite else { return 0 }
        return min(max(0, covered), clippedExerciseInterval.duration)
    }

    private static func containsHalfOpen(_ interval: DateInterval, date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func finiteSum(_ lhs: Double, _ rhs: Double) -> Double {
        let result = lhs + rhs
        return result.isFinite ? result : .greatestFiniteMagnitude
    }
}
