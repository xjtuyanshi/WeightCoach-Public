import Foundation
import SwiftData

enum FoodQuantityUnit: String, CaseIterable, Codable, Sendable {
    case grams
    case milliliters
    case servings
    case units
    case package

    var label: String {
        switch self {
        case .grams: return "克"
        case .milliliters: return "毫升"
        case .servings: return "份"
        case .units: return "个"
        case .package: return "包"
        }
    }

    func consumptionAmount(value: Decimal) -> ConsumptionAmount {
        switch self {
        case .grams: return .grams(value)
        case .milliliters: return .milliliters(value)
        case .servings: return .servings(value)
        case .units: return .units(value)
        case .package: return .packageFraction(value)
        }
    }
}

enum FoodProductSource: String, Codable, Sendable {
    case openFoodFacts
    case nutritionLabel
    case manual
    case demo

    var label: String {
        switch self {
        case .openFoodFacts: return "Open Food Facts"
        case .nutritionLabel: return "营养标签"
        case .manual: return "手动创建"
        case .demo: return "演示数据"
        }
    }
}

/// 可复用的食品定义。FoodEntry 仍保存每次摄入的数值快照，产品修改不会反算历史。
@Model
final class FoodProduct {
    var id: UUID
    var barcodeRaw: String?
    var gtin14: String?
    var name: String
    var brand: String?
    var nutritionBasisRaw: String

    var energyKcal: Double?
    var proteinG: Double?
    var carbohydratesG: Double?
    var fatG: Double?
    var saturatedFatG: Double?
    var transFatG: Double?
    var cholesterolMg: Double?
    var fiberG: Double?
    var sugarG: Double?
    var addedSugarG: Double?
    var sodiumMg: Double?
    var vitaminDMcg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var potassiumMg: Double?
    var caffeineMg: Double?

    var servingSizeText: String?
    var gramsPerServing: Double?
    var millilitersPerServing: Double?
    var unitsPerServing: Double?
    var servingsPerPackage: Double?
    var imageURLString: String?

    var sourceRaw: String
    var verifiedByUser: Bool
    var isFavorite: Bool
    var preferredAmount: Double?
    var preferredUnitRaw: String?
    var useCount: Int
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        barcodeRaw: String? = nil,
        gtin14: String? = nil,
        name: String,
        brand: String? = nil,
        nutritionBasis: NutritionBasis,
        nutrition: NutritionValues,
        servingSizeText: String? = nil,
        gramsPerServing: Double? = nil,
        millilitersPerServing: Double? = nil,
        unitsPerServing: Double? = nil,
        servingsPerPackage: Double? = nil,
        imageURL: URL? = nil,
        source: FoodProductSource,
        verifiedByUser: Bool = false,
        isFavorite: Bool = false,
        preferredAmount: Double? = nil,
        preferredUnit: FoodQuantityUnit? = nil,
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.barcodeRaw = barcodeRaw
        self.gtin14 = gtin14
        self.name = name
        self.brand = brand
        self.nutritionBasisRaw = nutritionBasis.rawValue
        self.servingSizeText = servingSizeText
        self.gramsPerServing = gramsPerServing
        self.millilitersPerServing = millilitersPerServing
        self.unitsPerServing = unitsPerServing
        self.servingsPerPackage = servingsPerPackage
        self.imageURLString = imageURL?.absoluteString
        self.sourceRaw = source.rawValue
        self.verifiedByUser = verifiedByUser
        self.isFavorite = isFavorite
        self.preferredAmount = preferredAmount
        self.preferredUnitRaw = preferredUnit?.rawValue
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        setNutrition(nutrition)
    }

    var nutritionBasis: NutritionBasis {
        get { NutritionBasis(rawValue: nutritionBasisRaw) ?? .perServing }
        set { nutritionBasisRaw = newValue.rawValue }
    }

    var source: FoodProductSource {
        get { FoodProductSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var preferredUnit: FoodQuantityUnit? {
        get { preferredUnitRaw.flatMap(FoodQuantityUnit.init(rawValue:)) }
        set { preferredUnitRaw = newValue?.rawValue }
    }

    var imageURL: URL? {
        imageURLString.flatMap(URL.init(string:))
    }

    var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(brand) \(name)"
    }

    var nutritionValues: NutritionValues {
        let energy = Self.decimal(energyKcal)
        let protein = Self.decimal(proteinG)
        let carbohydrates = Self.decimal(carbohydratesG)
        let fat = Self.decimal(fatG)
        let saturatedFat = Self.decimal(saturatedFatG)
        let transFat = Self.decimal(transFatG)
        let cholesterol = Self.decimal(cholesterolMg)
        let fiber = Self.decimal(fiberG)
        let sugar = Self.decimal(sugarG)
        let addedSugar = Self.decimal(addedSugarG)
        let sodium = Self.decimal(sodiumMg)
        let vitaminD = Self.decimal(vitaminDMcg)
        let calcium = Self.decimal(calciumMg)
        let iron = Self.decimal(ironMg)
        let potassium = Self.decimal(potassiumMg)
        let caffeine = Self.decimal(caffeineMg)
        return NutritionValues(
            energyKcal: energy,
            proteinG: protein,
            carbohydratesG: carbohydrates,
            fatG: fat,
            saturatedFatG: saturatedFat,
            transFatG: transFat,
            cholesterolMg: cholesterol,
            fiberG: fiber,
            sugarG: sugar,
            addedSugarG: addedSugar,
            sodiumMg: sodium,
            vitaminDMcg: vitaminD,
            calciumMg: calcium,
            ironMg: iron,
            potassiumMg: potassium,
            caffeineMg: caffeine
        )
    }

    var nutritionProfile: NutritionProfile {
        let servingGrams = Self.decimal(gramsPerServing)
        let servingMilliliters = Self.decimal(millilitersPerServing)
        let unitsPerServing = Self.decimal(unitsPerServing)
        let servingsPerPackage = Self.decimal(servingsPerPackage)
        var profile = NutritionProfile(
            servingGrams: servingGrams,
            servingMilliliters: servingMilliliters,
            unitsPerServing: unitsPerServing,
            servingsPerPackage: servingsPerPackage
        )
        switch nutritionBasis {
        case .per100Grams: profile.per100Grams = nutritionValues
        case .perServing: profile.perServing = nutritionValues
        case .per100Milliliters: profile.per100Milliliters = nutritionValues
        case .perPackage: profile.perPackage = nutritionValues
        case .perUnit: profile.perUnit = nutritionValues
        }
        return profile
    }

    func setNutrition(_ values: NutritionValues) {
        energyKcal = values.energyKcal?.doubleValue
        proteinG = values.proteinG?.doubleValue
        carbohydratesG = values.carbohydratesG?.doubleValue
        fatG = values.fatG?.doubleValue
        saturatedFatG = values.saturatedFatG?.doubleValue
        transFatG = values.transFatG?.doubleValue
        cholesterolMg = values.cholesterolMg?.doubleValue
        fiberG = values.fiberG?.doubleValue
        sugarG = values.sugarG?.doubleValue
        addedSugarG = values.addedSugarG?.doubleValue
        sodiumMg = values.sodiumMg?.doubleValue
        vitaminDMcg = values.vitaminDMcg?.doubleValue
        calciumMg = values.calciumMg?.doubleValue
        ironMg = values.ironMg?.doubleValue
        potassiumMg = values.potassiumMg?.doubleValue
        caffeineMg = values.caffeineMg?.doubleValue
    }

    private static func decimal(_ value: Double?) -> Decimal? {
        value.map { Decimal($0) }
    }
}
