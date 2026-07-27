import Foundation

struct ExerciseEnergyInterval: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let estimatedActiveEnergyKcal: Double

    init(startDate: Date, endDate: Date, estimatedActiveEnergyKcal: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.estimatedActiveEnergyKcal = estimatedActiveEnergyKcal
    }

    init(startDate: Date, durationMinutes: Double, estimatedActiveEnergyKcal: Double) {
        let endDate = durationMinutes.isFinite
            ? startDate.addingTimeInterval(durationMinutes * 60)
            : startDate
        self.init(
            startDate: startDate,
            endDate: endDate,
            estimatedActiveEnergyKcal: estimatedActiveEnergyKcal
        )
    }
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
}

enum ManualExerciseSupplementEngine {
    /// 计算一条手动运动记录仍需补入 TDEE 的活动能量。
    ///
    /// HealthKit 区间样本按与运动区间的重叠时长占样本总时长的比例扣除；
    /// 点样本落在运动区间内时扣除整笔。传入 `queryInterval` 时，运动估算值与
    /// 样本都会裁剪到该查询范围，适合跨午夜记录按天汇总。
    static func calculate(
        exercise: ExerciseEnergyInterval,
        healthSamples: [HealthActiveEnergySample],
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
        let supplement = max(0, validated.clippedEstimatedEnergy - finiteHealthEnergy)

        return ManualExerciseSupplement(
            estimatedActiveEnergyKcal: validated.clippedEstimatedEnergy,
            overlappingHealthEnergyKcal: finiteHealthEnergy,
            supplementalActiveEnergyKcal: supplement.isFinite ? supplement : 0
        )
    }

    /// 汇总多条互不重叠的本地运动记录。录入层应拒绝重叠记录。
    static func calculateTotal(
        exercises: [ExerciseEnergyInterval],
        healthSamples: [HealthActiveEnergySample],
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
                )
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
