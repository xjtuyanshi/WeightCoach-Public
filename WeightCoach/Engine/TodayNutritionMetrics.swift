import Foundation

struct TodayNutritionMetrics: Equatable {
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let proteinCoverage: Double?
    let carbsCoverage: Double?
    let fatCoverage: Double?
    let completeMacroCoverage: Double?
    let incompleteMacroEntryCount: Int
    let totalCalories: Double
    let entryCount: Int

    var hasIncompleteMacroData: Bool {
        incompleteMacroEntryCount > 0
    }

    static func calculate(foods: [FoodEntry]) -> TodayNutritionMetrics {
        let totalCalories = foods.reduce(0) {
            $0 + Self.validCalories($1.calories)
        }

        return TodayNutritionMetrics(
            proteinG: Self.sumKnown(foods.compactMap { Self.validMacro($0.protein) }),
            carbsG: Self.sumKnown(foods.compactMap { Self.validMacro($0.carbs) }),
            fatG: Self.sumKnown(foods.compactMap { Self.validMacro($0.fat) }),
            proteinCoverage: Self.coverage(
                foods: foods,
                totalCalories: totalCalories
            ) { Self.validMacro($0.protein) != nil },
            carbsCoverage: Self.coverage(
                foods: foods,
                totalCalories: totalCalories
            ) { Self.validMacro($0.carbs) != nil },
            fatCoverage: Self.coverage(
                foods: foods,
                totalCalories: totalCalories
            ) { Self.validMacro($0.fat) != nil },
            completeMacroCoverage: Self.coverage(
                foods: foods,
                totalCalories: totalCalories
            ) { Self.hasCompleteMacros($0) },
            incompleteMacroEntryCount: foods.filter {
                !Self.hasCompleteMacros($0)
            }.count,
            totalCalories: totalCalories,
            entryCount: foods.count
        )
    }

    private static func sumKnown(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private static func coverage(
        foods: [FoodEntry],
        totalCalories: Double,
        isKnown: (FoodEntry) -> Bool
    ) -> Double? {
        guard !foods.isEmpty else { return nil }

        if totalCalories > 0 {
            let knownCalories = foods.reduce(0) { partial, food in
                partial + (isKnown(food) ? validCalories(food.calories) : 0)
            }
            return min(max(knownCalories / totalCalories, 0), 1)
        }

        let knownCount = foods.reduce(0) { $0 + (isKnown($1) ? 1 : 0) }
        return Double(knownCount) / Double(foods.count)
    }

    private static func validCalories(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func validMacro(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func hasCompleteMacros(_ food: FoodEntry) -> Bool {
        validMacro(food.protein) != nil
            && validMacro(food.carbs) != nil
            && validMacro(food.fat) != nil
    }
}
