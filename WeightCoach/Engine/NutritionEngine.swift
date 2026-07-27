import Foundation

enum NutritionBasis: String, CaseIterable, Codable {
    case perServing
    case per100Grams
    case per100Milliliters
    case perPackage
    case perUnit
}

/// 营养数据的统一数值结构。计算阶段使用 Decimal，避免连续份量换算积累 Double 误差。
struct NutritionValues: Equatable, Sendable {
    var energyKcal: Decimal?
    var proteinG: Decimal?
    var carbohydratesG: Decimal?
    var fatG: Decimal?
    var saturatedFatG: Decimal?
    var transFatG: Decimal?
    var cholesterolMg: Decimal?
    var fiberG: Decimal?
    var sugarG: Decimal?
    var addedSugarG: Decimal?
    var sodiumMg: Decimal?
    var vitaminDMcg: Decimal?
    var calciumMg: Decimal?
    var ironMg: Decimal?
    var potassiumMg: Decimal?
    var caffeineMg: Decimal?

    init(
        energyKcal: Decimal? = nil,
        proteinG: Decimal? = nil,
        carbohydratesG: Decimal? = nil,
        fatG: Decimal? = nil,
        saturatedFatG: Decimal? = nil,
        transFatG: Decimal? = nil,
        cholesterolMg: Decimal? = nil,
        fiberG: Decimal? = nil,
        sugarG: Decimal? = nil,
        addedSugarG: Decimal? = nil,
        sodiumMg: Decimal? = nil,
        vitaminDMcg: Decimal? = nil,
        calciumMg: Decimal? = nil,
        ironMg: Decimal? = nil,
        potassiumMg: Decimal? = nil,
        caffeineMg: Decimal? = nil
    ) {
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbohydratesG = carbohydratesG
        self.fatG = fatG
        self.saturatedFatG = saturatedFatG
        self.transFatG = transFatG
        self.cholesterolMg = cholesterolMg
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.addedSugarG = addedSugarG
        self.sodiumMg = sodiumMg
        self.vitaminDMcg = vitaminDMcg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.potassiumMg = potassiumMg
        self.caffeineMg = caffeineMg
    }

    func scaled(by factor: Decimal) -> NutritionValues {
        NutritionValues(
            energyKcal: energyKcal.map { $0 * factor },
            proteinG: proteinG.map { $0 * factor },
            carbohydratesG: carbohydratesG.map { $0 * factor },
            fatG: fatG.map { $0 * factor },
            saturatedFatG: saturatedFatG.map { $0 * factor },
            transFatG: transFatG.map { $0 * factor },
            cholesterolMg: cholesterolMg.map { $0 * factor },
            fiberG: fiberG.map { $0 * factor },
            sugarG: sugarG.map { $0 * factor },
            addedSugarG: addedSugarG.map { $0 * factor },
            sodiumMg: sodiumMg.map { $0 * factor },
            vitaminDMcg: vitaminDMcg.map { $0 * factor },
            calciumMg: calciumMg.map { $0 * factor },
            ironMg: ironMg.map { $0 * factor },
            potassiumMg: potassiumMg.map { $0 * factor },
            caffeineMg: caffeineMg.map { $0 * factor }
        )
    }

    var hasAnyValue: Bool {
        energyKcal != nil
            || proteinG != nil
            || carbohydratesG != nil
            || fatG != nil
            || saturatedFatG != nil
            || transFatG != nil
            || cholesterolMg != nil
            || fiberG != nil
            || sugarG != nil
            || addedSugarG != nil
            || sodiumMg != nil
            || vitaminDMcg != nil
            || calciumMg != nil
            || ironMg != nil
            || potassiumMg != nil
            || caffeineMg != nil
    }
}

struct NutritionProfile: Equatable, Sendable {
    var per100Grams: NutritionValues?
    var perServing: NutritionValues?
    var per100Milliliters: NutritionValues?
    var perPackage: NutritionValues?
    var perUnit: NutritionValues?
    var servingGrams: Decimal?
    var servingMilliliters: Decimal?
    var unitsPerServing: Decimal?
    var servingsPerPackage: Decimal?

    init(
        per100Grams: NutritionValues? = nil,
        perServing: NutritionValues? = nil,
        per100Milliliters: NutritionValues? = nil,
        perPackage: NutritionValues? = nil,
        perUnit: NutritionValues? = nil,
        servingGrams: Decimal? = nil,
        servingMilliliters: Decimal? = nil,
        unitsPerServing: Decimal? = nil,
        servingsPerPackage: Decimal? = nil
    ) {
        self.per100Grams = per100Grams
        self.perServing = perServing
        self.per100Milliliters = per100Milliliters
        self.perPackage = perPackage
        self.perUnit = perUnit
        self.servingGrams = servingGrams
        self.servingMilliliters = servingMilliliters
        self.unitsPerServing = unitsPerServing
        self.servingsPerPackage = servingsPerPackage
    }
}

enum ConsumptionAmount: Equatable, Sendable {
    case grams(Decimal)
    case servings(Decimal)
    case milliliters(Decimal)
    case units(Decimal)
    case packageFraction(Decimal)
}

enum NutritionEngine {
    /// 只做确定性换算；数据不足时返回 nil，不猜份量或密度。
    static func calculate(
        profile: NutritionProfile,
        amount: ConsumptionAmount
    ) -> NutritionValues? {
        switch amount {
        case .grams(let grams):
            guard grams >= 0 else { return nil }
            if let values = profile.per100Grams {
                return values.scaled(by: grams / 100)
            }
            if let values = profile.perServing,
               let servingGrams = positive(profile.servingGrams) {
                return values.scaled(by: grams / servingGrams)
            }

        case .servings(let servings):
            guard servings >= 0 else { return nil }
            if let values = profile.perServing {
                return values.scaled(by: servings)
            }
            if let values = profile.per100Grams,
               let servingGrams = positive(profile.servingGrams) {
                return values.scaled(by: servingGrams * servings / 100)
            }
            if let values = profile.perPackage,
               let servingsPerPackage = positive(profile.servingsPerPackage) {
                return values.scaled(by: servings / servingsPerPackage)
            }

        case .milliliters(let milliliters):
            guard milliliters >= 0 else { return nil }
            if let values = profile.per100Milliliters {
                return values.scaled(by: milliliters / 100)
            }
            if let values = profile.perServing,
               let servingMilliliters = positive(profile.servingMilliliters) {
                return values.scaled(by: milliliters / servingMilliliters)
            }

        case .units(let units):
            guard units >= 0 else { return nil }
            if let values = profile.perUnit {
                return values.scaled(by: units)
            }
            if let values = profile.perServing,
               let unitsPerServing = positive(profile.unitsPerServing) {
                return values.scaled(by: units / unitsPerServing)
            }

        case .packageFraction(let fraction):
            guard fraction >= 0 else { return nil }
            if let values = profile.perPackage {
                return values.scaled(by: fraction)
            }
            if let values = profile.perServing,
               let servingsPerPackage = positive(profile.servingsPerPackage) {
                return values.scaled(by: servingsPerPackage * fraction)
            }
        }
        return nil
    }

    private static func positive(_ value: Decimal?) -> Decimal? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
