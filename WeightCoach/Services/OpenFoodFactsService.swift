import Foundation

/// Open Food Facts 商品信息（免费开放数据库，覆盖 Costco/Walmart 等大部分美国商品）
struct ScannedProduct: Sendable {
    var barcode: String
    var name: String
    var brand: String?
    var nutritionBasis: NutritionBasis
    var nutritionValues: NutritionValues
    var source: FoodProductSource
    var servingSizeText: String?
    var servingQuantityG: Double?
    var millilitersPerServing: Double?
    var unitsPerServing: Double?
    var servingsPerPackage: Double?
    var imageURL: URL?
    var cachedProductID: UUID?
    var preferredAmount: Double?
    var preferredUnit: FoodQuantityUnit?
    var isCached = false

    init(
        barcode: String,
        name: String,
        brand: String? = nil,
        nutritionBasis: NutritionBasis,
        nutritionValues: NutritionValues,
        source: FoodProductSource,
        servingSizeText: String? = nil,
        servingQuantityG: Double? = nil,
        millilitersPerServing: Double? = nil,
        unitsPerServing: Double? = nil,
        servingsPerPackage: Double? = nil,
        imageURL: URL? = nil,
        cachedProductID: UUID? = nil,
        preferredAmount: Double? = nil,
        preferredUnit: FoodQuantityUnit? = nil,
        isCached: Bool = false
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.nutritionBasis = nutritionBasis
        self.nutritionValues = nutritionValues
        self.source = source
        self.servingSizeText = servingSizeText
        self.servingQuantityG = servingQuantityG
        self.millilitersPerServing = millilitersPerServing
        self.unitsPerServing = unitsPerServing
        self.servingsPerPackage = servingsPerPackage
        self.imageURL = imageURL
        self.cachedProductID = cachedProductID
        self.preferredAmount = preferredAmount
        self.preferredUnit = preferredUnit
        self.isCached = isCached
    }

    /// 旧扫码表单仍可按具体基准读取；规范数据只保留上面的 basis + values。
    var nutritionPer100Grams: NutritionValues? {
        nutritionBasis == .per100Grams ? nutritionValues : nil
    }

    var nutritionPerServing: NutritionValues? {
        nutritionBasis == .perServing ? nutritionValues : nil
    }

    var nutritionPer100Milliliters: NutritionValues? {
        nutritionBasis == .per100Milliliters ? nutritionValues : nil
    }

    var nutritionPerPackage: NutritionValues? {
        nutritionBasis == .perPackage ? nutritionValues : nil
    }

    var nutritionPerUnit: NutritionValues? {
        nutritionBasis == .perUnit ? nutritionValues : nil
    }

    var kcalPer100g: Double? { nutritionPer100Grams?.energyKcal?.doubleValue }
    var kcalPer100ml: Double? { nutritionPer100Milliliters?.energyKcal?.doubleValue }
    var proteinPer100g: Double? { nutritionPer100Grams?.proteinG?.doubleValue }
    var carbsPer100g: Double? { nutritionPer100Grams?.carbohydratesG?.doubleValue }
    var fatPer100g: Double? { nutritionPer100Grams?.fatG?.doubleValue }
    var kcalPerServing: Double? { nutritionPerServing?.energyKcal?.doubleValue }

    /// 同一次计算只使用产品声明的一个营养基准；缺少热量时不猜算。
    var canonicalNutrition: (basis: NutritionBasis, values: NutritionValues)? {
        guard nutritionValues.energyKcal != nil else { return nil }
        return (nutritionBasis, nutritionValues)
    }

    var nutritionProfile: NutritionProfile {
        guard let canonicalNutrition else { return NutritionProfile() }
        let servingGrams = servingQuantityG.map { Decimal($0) }
        let servingMilliliters = millilitersPerServing.map { Decimal($0) }
        let servingUnits = unitsPerServing.map { Decimal($0) }
        let packageServings = servingsPerPackage.map { Decimal($0) }
        var profile = NutritionProfile(
            servingGrams: servingGrams,
            servingMilliliters: servingMilliliters,
            unitsPerServing: servingUnits,
            servingsPerPackage: packageServings
        )
        switch canonicalNutrition.basis {
        case .per100Grams:
            profile.per100Grams = canonicalNutrition.values
        case .perServing:
            profile.perServing = canonicalNutrition.values
        case .per100Milliliters:
            profile.per100Milliliters = canonicalNutrition.values
        case .perPackage:
            profile.perPackage = canonicalNutrition.values
        case .perUnit:
            profile.perUnit = canonicalNutrition.values
        }
        return profile
    }
}

enum OpenFoodFactsError: LocalizedError {
    case notFound
    case missingNutrition
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "数据库中没有找到该商品，可以改用手动输入（参考包装上的营养标签）"
        case .missingNutrition: return "找到了商品，但数据库没有可靠热量数据。请扫描包装上的营养表"
        case .network(let message): return "查询失败：\(message)"
        }
    }
}

enum OpenFoodFactsService {
    private enum ServingMeasurementUnit: Hashable {
        case grams
        case milliliters
    }

    static func fetchProduct(barcode: String) async throws -> ScannedProduct {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = "product_name,product_name_en,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,product_quantity_unit,servings_per_package,image_front_small_url"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)") else {
            throw OpenFoodFactsError.network("条形码格式无效")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("WeightCoach/1.0 (iOS; personal weight tracking app)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw OpenFoodFactsError.notFound
            }
            data = d
        } catch let error as OpenFoodFactsError {
            throw error
        } catch {
            throw OpenFoodFactsError.network(error.localizedDescription)
        }

        return try parseProduct(data: data, barcode: code)
    }

    static func parseProduct(data: Data, barcode: String) throws -> ScannedProduct {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int == 1) || json["product"] != nil,
              let product = json["product"] as? [String: Any] else {
            throw OpenFoodFactsError.notFound
        }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let per100 = nutritionValues(in: nutriments, suffix: "_100g")
        let perServing = nutritionValues(in: nutriments, suffix: "_serving")
        let servingUnit = resolvedServingMeasurementUnit(in: product)
        let nutrition: (basis: NutritionBasis, values: NutritionValues)
        if per100.energyKcal != nil, servingUnit == .grams {
            nutrition = (.per100Grams, per100)
        } else if per100.energyKcal != nil, servingUnit == .milliliters {
            // Open Food Facts keeps the legacy `_100g` key for both solids and
            // liquids; its schema defines the liquid value as per 100 ml.
            nutrition = (.per100Milliliters, per100)
        } else if perServing.energyKcal != nil {
            nutrition = (.perServing, perServing)
        } else {
            throw OpenFoodFactsError.missingNutrition
        }
        let name = nonemptyString(product["product_name"])
            ?? nonemptyString(product["product_name_en"])
            ?? "未命名商品"

        return ScannedProduct(
            barcode: barcode,
            name: name,
            brand: nonemptyString(product["brands"]),
            nutritionBasis: nutrition.basis,
            nutritionValues: nutrition.values,
            source: .openFoodFacts,
            servingSizeText: nonemptyString(product["serving_size"]),
            servingQuantityG: servingUnit == .grams
                ? number(product["serving_quantity"])
                : nil,
            millilitersPerServing: servingUnit == .milliliters
                ? number(product["serving_quantity"])
                : nil,
            unitsPerServing: nil,
            servingsPerPackage: number(product["servings_per_package"]),
            imageURL: nonemptyString(product["image_front_small_url"]).flatMap(URL.init(string:))
        )
    }

    /// Open Food Facts defines `serving_quantity_unit` and
    /// `product_quantity_unit` as normalized `g`/`ml` fields. Older records may
    /// only retain the free-text `serving_size`, so accept an explicit g/ml
    /// token there as a compatibility fallback. Conflicting or unsupported
    /// units stay unresolved instead of assuming that 1 ml equals 1 g.
    private static func resolvedServingMeasurementUnit(
        in product: [String: Any]
    ) -> ServingMeasurementUnit? {
        var units = Set<ServingMeasurementUnit>()

        if let rawServingUnit = nonemptyString(product["serving_quantity_unit"]) {
            guard let unit = normalizedMeasurementUnit(rawServingUnit) else {
                return nil
            }
            units.insert(unit)
        } else if let servingSize = nonemptyString(product["serving_size"]) {
            let legacyUnits = measurementUnits(inServingSize: servingSize)
            guard legacyUnits.count <= 1 else { return nil }
            units.formUnion(legacyUnits)
        }

        if let rawProductUnit = nonemptyString(product["product_quantity_unit"]) {
            guard let unit = normalizedMeasurementUnit(rawProductUnit) else {
                return nil
            }
            units.insert(unit)
        }

        guard units.count == 1 else { return nil }
        return units.first
    }

    private static func normalizedMeasurementUnit(
        _ rawValue: String
    ) -> ServingMeasurementUnit? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "g":
            return .grams
        case "ml":
            return .milliliters
        default:
            return nil
        }
    }

    private static func measurementUnits(
        inServingSize servingSize: String
    ) -> Set<ServingMeasurementUnit> {
        let pattern = #"(?i)(?<![a-z])\d+(?:[.,]\d+)?\s*(ml|g)(?![a-z])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(servingSize.startIndex..., in: servingSize)
        return Set(
            expression.matches(in: servingSize, range: range).compactMap { match in
                guard let unitRange = Range(match.range(at: 1), in: servingSize) else {
                    return nil
                }
                return normalizedMeasurementUnit(String(servingSize[unitRange]))
            }
        )
    }

    private static func nutritionValues(
        in nutriments: [String: Any],
        suffix: String
    ) -> NutritionValues {
        var energy = number(nutriments["energy-kcal\(suffix)"])
        if energy == nil, let kilojoules = number(nutriments["energy\(suffix)"]) {
            energy = kilojoules / 4.184
        }
        let protein = number(nutriments["proteins\(suffix)"])
        let carbohydrates = number(nutriments["carbohydrates\(suffix)"])
        let fat = number(nutriments["fat\(suffix)"])
        let saturatedFat = number(nutriments["saturated-fat\(suffix)"])
        let transFat = number(nutriments["trans-fat\(suffix)"])
        let cholesterol = number(nutriments["cholesterol\(suffix)"])
        let fiber = number(nutriments["fiber\(suffix)"])
        let sugar = number(nutriments["sugars\(suffix)"])
        let sodium = number(nutriments["sodium\(suffix)"])
        return NutritionValues(
            energyKcal: energy.map { Decimal($0) },
            proteinG: protein.map { Decimal($0) },
            carbohydratesG: carbohydrates.map { Decimal($0) },
            fatG: fat.map { Decimal($0) },
            saturatedFatG: saturatedFat.map { Decimal($0) },
            transFatG: transFat.map { Decimal($0) },
            cholesterolMg: cholesterol.map { Decimal($0 * 1_000) },
            fiberG: fiber.map { Decimal($0) },
            sugarG: sugar.map { Decimal($0) },
            sodiumMg: sodium.map { Decimal($0 * 1_000) }
        )
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let s = value as? String {
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
