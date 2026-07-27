import Foundation

struct StarbucksDrinkEstimate: Equatable, Sendable {
    let officialStandardCalories: Double
    let syrupAdjustmentCalories: Double
    let customizedBaseCalories: Double
    let addOnCalories: Double
    let recommendedCalories: Double
    let calorieLowerBound: Double
    let calorieUpperBound: Double
    let caffeineMg: Double
    let proteinG: Double
    let carbohydratesG: Double
    let fatG: Double
}

/// 当前只覆盖用户已核对过的 Venti Iced Shaken Espresso 配方。
///
/// 160 千卡是 Starbucks App 显示的标准杯型值；Starbucks 不会为每个自定义项
/// 动态给出营养总数。糖浆每泵和 Blue Coconut Protein Cold Foam 均以官方相邻
/// 配方的差值推算，所以结果必须以区间和“估算”展示，不能冒充官方精确值。
enum StarbucksCustomizationEngine {
    static let officialStandardCalories = 160.0
    static let officialStandardCaffeineMg = 300.0
    static let inferredCaloriesPerClassicSyrupPump = 17.5
    static let inferredFoamCalories = 290.0
    static let inferredFoamCalorieRange = 260.0...320.0

    static func estimateVentiIcedShakenEspresso(
        standardSyrupPumps: Int,
        finalTotalSyrupPumps: Int,
        includesBlueCoconutProteinColdFoam: Bool
    ) -> StarbucksDrinkEstimate? {
        guard (0...12).contains(standardSyrupPumps),
              (0...12).contains(finalTotalSyrupPumps) else {
            return nil
        }

        let pumpDifference = Double(finalTotalSyrupPumps - standardSyrupPumps)
        let syrupAdjustment = pumpDifference * inferredCaloriesPerClassicSyrupPump
        let customizedBase = max(0, officialStandardCalories + syrupAdjustment)
        let addOnEstimate = includesBlueCoconutProteinColdFoam
            ? inferredFoamCalories
            : 0
        let addOnLower = includesBlueCoconutProteinColdFoam
            ? inferredFoamCalorieRange.lowerBound
            : 0
        let addOnUpper = includesBlueCoconutProteinColdFoam
            ? inferredFoamCalorieRange.upperBound
            : 0

        let rawEstimate = customizedBase + addOnEstimate
        let rawLower = max(0, customizedBase + addOnLower)
        let rawUpper = customizedBase + addOnUpper

        // 标准 Venti 近似宏量：P4/C27/F4；Classic Syrup 只调整碳水。
        let baseCarbohydrates = max(
            0,
            27 + pumpDifference * inferredCaloriesPerClassicSyrupPump / 4
        )
        let protein = 4.0 + (includesBlueCoconutProteinColdFoam ? 17.0 : 0)
        let carbohydrates = baseCarbohydrates
            + (includesBlueCoconutProteinColdFoam ? 21 : 0)
        let fat = 4.0 + (includesBlueCoconutProteinColdFoam ? 17.0 : 0)

        return StarbucksDrinkEstimate(
            officialStandardCalories: officialStandardCalories,
            syrupAdjustmentCalories: syrupAdjustment,
            customizedBaseCalories: customizedBase,
            addOnCalories: addOnEstimate,
            recommendedCalories: roundedToNearestTen(rawEstimate),
            calorieLowerBound: roundedToNearestTen(rawLower),
            calorieUpperBound: roundedToNearestTen(rawUpper),
            caffeineMg: officialStandardCaffeineMg,
            proteinG: protein,
            carbohydratesG: carbohydrates,
            fatG: fat
        )
    }

    private static func roundedToNearestTen(_ value: Double) -> Double {
        (value / 10).rounded() * 10
    }
}
