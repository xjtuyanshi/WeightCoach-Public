import Foundation

enum BodyCompositionUnit: String, Codable, CaseIterable, Equatable {
    case percent
    case kilograms
    case kilogramsPerSquareMeter

    var symbol: String {
        switch self {
        case .percent: "%"
        case .kilograms: "kg"
        case .kilogramsPerSquareMeter: "kg/m²"
        }
    }
}

/// 单项身体成分测量。`value` 可以为空，以诚实表达“只有范围、没有精确值”。
struct BodyCompositionMeasurement: Codable, Equatable {
    var value: Double?
    var lowerBound: Double?
    var upperBound: Double?
    var unit: BodyCompositionUnit
    var source: String?
    var measuredAt: Date?
    var note: String?

    static func empty(unit: BodyCompositionUnit) -> BodyCompositionMeasurement {
        BodyCompositionMeasurement(
            value: nil,
            lowerBound: nil,
            upperBound: nil,
            unit: unit,
            source: nil,
            measuredAt: nil,
            note: nil
        )
    }
}

/// 历史 DEXA 快照单独存放，避免与当前校准或智能秤口径混为一谈。
struct DEXASnapshot: Codable, Equatable {
    var bodyFatPercent: BodyCompositionMeasurement
    var fatMassKg: BodyCompositionMeasurement
    var leanSoftTissueKg: BodyCompositionMeasurement
    var totalMassKg: BodyCompositionMeasurement

    static let empty = DEXASnapshot(
        bodyFatPercent: .empty(unit: .percent),
        fatMassKg: .empty(unit: .kilograms),
        leanSoftTissueKg: .empty(unit: .kilograms),
        totalMassKg: .empty(unit: .kilograms)
    )
}

/// 可编辑、可版本化持久化的身体成分档案。
///
/// 不同测量口径保持独立；除 `calibratedBodyFatPercent` 可在真实体脂缺失时作为
/// BMR fallback 外，其余字段均只用于展示与跟踪。
struct BodyCompositionProfile: Codable, Equatable {
    var calibratedBodyFatPercent: BodyCompositionMeasurement
    var fatMassKg: BodyCompositionMeasurement
    var fatFreeMassKg: BodyCompositionMeasurement
    var dexaLeanSoftTissueKg: BodyCompositionMeasurement
    var appendicularLeanMassKg: BodyCompositionMeasurement
    var fitdaysMuscleMassKg: BodyCompositionMeasurement
    var skeletalMuscleMassKg: BodyCompositionMeasurement
    var smiKgPerSquareMeter: BodyCompositionMeasurement
    var historicalDEXA: DEXASnapshot
    /// 个人饮食参考值；不进入 TDEE、动态缺口或每日预算计算。
    var referenceDailyIntakeKcal: Double?

    static let empty = BodyCompositionProfile(
        calibratedBodyFatPercent: .empty(unit: .percent),
        fatMassKg: .empty(unit: .kilograms),
        fatFreeMassKg: .empty(unit: .kilograms),
        dexaLeanSoftTissueKg: .empty(unit: .kilograms),
        appendicularLeanMassKg: .empty(unit: .kilograms),
        fitdaysMuscleMassKg: .empty(unit: .kilograms),
        skeletalMuscleMassKg: .empty(unit: .kilograms),
        smiKgPerSquareMeter: .empty(unit: .kilogramsPerSquareMeter),
        historicalDEXA: .empty,
        referenceDailyIntakeKcal: nil
    )
}
