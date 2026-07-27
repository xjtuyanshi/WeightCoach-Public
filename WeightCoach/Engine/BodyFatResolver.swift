import Foundation

enum BodyFatSource: Equatable {
    case healthKit
    case localRecord
    case calibratedProfile
}

struct ResolvedBodyFat: Equatable {
    let percent: Double
    let source: BodyFatSource
}

enum BodyFatResolver {
    /// 数据优先级：Apple 健康 → 最新本地体脂 → Profile 校准值。
    /// 历史 DEXA 与其他身体成分口径不会进入此路径。
    static func resolve(
        healthKitPercent: Double?,
        localWeights: [WeightEntry],
        calibratedMeasurement: BodyCompositionMeasurement
    ) -> ResolvedBodyFat? {
        if let healthKitPercent, isValid(healthKitPercent) {
            return ResolvedBodyFat(percent: healthKitPercent, source: .healthKit)
        }

        if let local = localWeights
            .compactMap({ entry -> (date: Date, percent: Double)? in
                guard let percent = entry.bodyFatPercent, isValid(percent) else { return nil }
                return (entry.date, percent)
            })
            .max(by: { $0.date < $1.date }) {
            return ResolvedBodyFat(percent: local.percent, source: .localRecord)
        }

        if calibratedMeasurement.unit == .percent,
           let calibrated = calibratedMeasurement.value,
           isValid(calibrated) {
            return ResolvedBodyFat(percent: calibrated, source: .calibratedProfile)
        }

        return nil
    }

    private static func isValid(_ percent: Double) -> Bool {
        percent.isFinite && percent > 3 && percent < 70
    }
}
