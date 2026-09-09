import Foundation

enum ExerciseEnergyEngine {
    static let calculationVersion = 1

    static let validMETRange = 1.0...25.0
    static let validWeightKgRange = 20.0...350.0
    static let validDurationMinutesRange = 1.0...600.0

    /// 估算高于静息水平的活动热量。
    ///
    /// App 的 TDEE 已包含 BMR，因此这里使用 `(MET - 1)`，避免把运动时段的
    /// 静息消耗再次算入活动能量。
    static func estimateActiveEnergyKcal(
        met: Double,
        weightKg: Double,
        durationMinutes: Double
    ) -> Double? {
        guard met.isFinite,
              weightKg.isFinite,
              durationMinutes.isFinite,
              validMETRange.contains(met),
              validWeightKgRange.contains(weightKg),
              validDurationMinutesRange.contains(durationMinutes) else {
            return nil
        }

        let result = max(0, met - 1) * 3.5 * weightKg / 200 * durationMinutes
        guard result.isFinite, result >= 0 else { return nil }
        return result
    }

    static func estimateActiveEnergyKcal(
        intensity: ExerciseIntensity,
        weightKg: Double,
        durationMinutes: Double
    ) -> Double? {
        estimateActiveEnergyKcal(
            met: intensity.metValue,
            weightKg: weightKg,
            durationMinutes: durationMinutes
        )
    }
}

/// 仅决定何时提示用户人工核对，不把步数直接换算成热量。
enum HealthActivityGuidance {
    static let meaningfulStepThreshold = 1_000.0

    static func shouldOfferManualWalking(
        steps: Double,
        includeActiveEnergy: Bool
    ) -> Bool {
        includeActiveEnergy
            && steps.isFinite
            && steps >= meaningfulStepThreshold
    }

    static func shouldSuggestManualWalking(
        steps: Double,
        hasActiveEnergySamples: Bool,
        includeActiveEnergy: Bool
    ) -> Bool {
        shouldOfferManualWalking(
            steps: steps,
            includeActiveEnergy: includeActiveEnergy
        )
            && !hasActiveEnergySamples
    }
}
