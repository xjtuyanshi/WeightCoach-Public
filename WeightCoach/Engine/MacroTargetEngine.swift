import Foundation

enum MacroDayStyle: String, CaseIterable, Codable, Sendable {
    case standard
    case training

    var label: String {
        switch self {
        case .standard: return "普通日"
        case .training: return "训练日"
        }
    }
}

struct DailyMacroTargets: Equatable, Sendable {
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
    let budgetKcal: Double
    let dayStyle: MacroDayStyle
    let isBudgetConstrained: Bool

    var allocatedKcal: Double {
        proteinG * 4 + fatG * 9 + carbsG * 4
    }
}

/// 把 `CalorieEngine` 已经确定的今日预算分配给三大营养素。
///
/// 这里不读取 HealthKit、不计算 TDEE，也不会反向修改热量预算。
enum MacroTargetEngine {
    static let proteinGramsPerKilogram = 1.6
    static let standardFatFraction = 0.25
    static let trainingFatFraction = 0.20
    static let minimumFatFraction = 0.15

    static func calculate(
        currentWeightKg: Double,
        budgetKcal: Double,
        dayStyle: MacroDayStyle = .standard
    ) -> DailyMacroTargets? {
        guard currentWeightKg.isFinite,
              currentWeightKg > 0,
              budgetKcal.isFinite,
              budgetKcal > 0 else {
            return nil
        }

        let nominalProteinG = roundToFive(currentWeightKg * proteinGramsPerKilogram)
        let desiredFatFraction = dayStyle == .training
            ? trainingFatFraction
            : standardFatFraction
        let desiredFatG = (budgetKcal * desiredFatFraction / 9).rounded()
        let minimumFatG = ceil(budgetKcal * minimumFatFraction / 9)

        var proteinG = nominalProteinG
        var fatG = desiredFatG
        var isBudgetConstrained = false

        let maximumFatAtNominalProtein = floor(
            max(0, budgetKcal - proteinG * 4) / 9
        )
        if fatG > maximumFatAtNominalProtein {
            isBudgetConstrained = true
            fatG = maximumFatAtNominalProtein
        }

        if fatG < minimumFatG {
            isBudgetConstrained = true
            fatG = minimumFatG
            let maximumProteinG = floor(
                max(0, budgetKcal - fatG * 9) / 4 / 5
            ) * 5
            proteinG = min(proteinG, maximumProteinG)
        }

        let remainingKcal = max(0, budgetKcal - proteinG * 4 - fatG * 9)
        let carbsG = remainingKcal / 4

        return DailyMacroTargets(
            proteinG: proteinG,
            fatG: fatG,
            carbsG: carbsG,
            budgetKcal: budgetKcal,
            dayStyle: dayStyle,
            isBudgetConstrained: isBudgetConstrained
        )
    }

    private static func roundToFive(_ value: Double) -> Double {
        (value / 5).rounded() * 5
    }
}
