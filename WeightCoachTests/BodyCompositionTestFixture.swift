@testable import WeightCoach

enum BodyCompositionTestFixture {
    static func syntheticProfile() -> BodyCompositionProfile {
        func measurement(
            value: Double? = nil,
            lowerBound: Double? = nil,
            upperBound: Double? = nil,
            unit: BodyCompositionUnit,
            note: String
        ) -> BodyCompositionMeasurement {
            BodyCompositionMeasurement(
                value: value,
                lowerBound: lowerBound,
                upperBound: upperBound,
                unit: unit,
                source: "合成测试数据",
                measuredAt: nil,
                note: note
            )
        }

        return BodyCompositionProfile(
            calibratedBodyFatPercent: measurement(
                value: 20,
                lowerBound: 19,
                upperBound: 21,
                unit: .percent,
                note: "仅用于测试校准体脂字段。"
            ),
            fatMassKg: measurement(
                value: 16,
                lowerBound: 15,
                upperBound: 17,
                unit: .kilograms,
                note: "仅用于测试脂肪量字段。"
            ),
            fatFreeMassKg: measurement(
                value: 64,
                lowerBound: 63,
                upperBound: 65,
                unit: .kilograms,
                note: "仅用于测试完整去脂体重字段。"
            ),
            dexaLeanSoftTissueKg: measurement(
                lowerBound: 60,
                upperBound: 61,
                unit: .kilograms,
                note: "仅用于测试 DEXA 瘦软组织范围。"
            ),
            appendicularLeanMassKg: measurement(
                lowerBound: 28,
                upperBound: 29,
                unit: .kilograms,
                note: "仅用于测试四肢瘦体重范围。"
            ),
            fitdaysMuscleMassKg: measurement(
                value: 58,
                unit: .kilograms,
                note: "仅用于测试设备肌肉量字段。"
            ),
            skeletalMuscleMassKg: measurement(
                value: 34,
                unit: .kilograms,
                note: "仅用于测试骨骼肌字段。"
            ),
            smiKgPerSquareMeter: measurement(
                value: 8,
                unit: .kilogramsPerSquareMeter,
                note: "仅用于测试 SMI 字段。"
            ),
            historicalDEXA: DEXASnapshot(
                bodyFatPercent: measurement(
                    value: 22,
                    unit: .percent,
                    note: "仅用于测试历史 DEXA 体脂字段。"
                ),
                fatMassKg: measurement(
                    value: 17.6,
                    unit: .kilograms,
                    note: "仅用于测试历史 DEXA 脂肪量字段。"
                ),
                leanSoftTissueKg: measurement(
                    value: 59.4,
                    unit: .kilograms,
                    note: "仅用于测试历史 DEXA 瘦软组织字段。"
                ),
                totalMassKg: measurement(
                    value: 80,
                    unit: .kilograms,
                    note: "仅用于测试历史 DEXA 总重字段。"
                )
            ),
            referenceDailyIntakeKcal: 2_100
        )
    }
}
