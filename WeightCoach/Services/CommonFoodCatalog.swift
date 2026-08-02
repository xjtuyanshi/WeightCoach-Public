import Foundation

/// USDA FoodData Central 提供的常见家用份量及其可食部分克重。
///
/// 这是展示层的静态参考，不改变目录仍以「每 100 克」保存和计算的事实；
/// 品种、大小和品牌有差异，因此所有面向用户的文案都明确标注为约数。
struct CommonFoodStandardPortion: Identifiable, Equatable, Sendable {
    let id: String
    let grams: Double
    let simplifiedLabel: String
    let traditionalLabel: String
    let englishLabel: String
    let isDefault: Bool

    init(
        id: String,
        grams: Double,
        simplifiedLabel: String,
        traditionalLabel: String,
        englishLabel: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.grams = grams
        self.simplifiedLabel = simplifiedLabel
        self.traditionalLabel = traditionalLabel
        self.englishLabel = englishLabel
        self.isDefault = isDefault
    }

    func localizedLabel(locale: Locale) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            englishLabel
        case .traditionalChinese:
            traditionalLabel
        case .simplifiedChinese, .system:
            simplifiedLabel
        }
    }

    func compactDescription(locale: Locale) -> String {
        "\(localizedLabel(locale: locale)) · \(Self.amountText(grams))\(Self.gramUnit(locale: locale))"
    }

    func approximateWeightDescription(locale: Locale) -> String {
        let amount = Self.amountText(grams)
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "about \(amount) g"
        case .traditionalChinese:
            return "約 \(amount) 公克"
        case .simplifiedChinese, .system:
            return "约 \(amount) 克"
        }
    }

    func savedDescription(locale: Locale) -> String {
        let label = localizedLabel(locale: locale)
        let amount = Self.amountText(grams)
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(label) (about \(amount) g)"
        case .traditionalChinese:
            return "\(label)（約 \(amount) 公克）"
        case .simplifiedChinese, .system:
            return "\(label)（约 \(amount) 克）"
        }
    }

    func searchSummary(locale: Locale) -> String {
        let label = localizedLabel(locale: locale)
        let amount = Self.amountText(grams)
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(label) is about \(amount) g edible weight"
        case .traditionalChinese:
            return "\(label)約 \(amount) 公克可食部分"
        case .simplifiedChinese, .system:
            return "\(label)约 \(amount) 克可食部分"
        }
    }

    private static func gramUnit(locale: Locale) -> String {
        AppLanguage.system.resolvedLanguage(systemLocale: locale) == .english
            ? "g"
            : interfaceLocalized("common_food.unit.grams", locale: locale)
    }

    private static func amountText(_ amount: Double) -> String {
        if amount.rounded() == amount {
            return String(Int(amount))
        }
        return String(format: "%.1f", amount)
    }
}

/// 内置的常见食物参考值。每项都明确烹调状态，避免把生重、熟重或额外用油混为一谈。
struct CommonFoodReference: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let aliases: [String]
    let preparation: String
    let nutritionPer100Grams: NutritionValues
    let fdcID: Int?
    let standardPortions: [CommonFoodStandardPortion]

    init(
        id: String,
        name: String,
        aliases: [String],
        preparation: String,
        nutritionPer100Grams: NutritionValues,
        fdcID: Int?,
        standardPortions: [CommonFoodStandardPortion] = []
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.preparation = preparation
        self.nutritionPer100Grams = nutritionPer100Grams
        self.fdcID = fdcID
        self.standardPortions = standardPortions
    }

    /// The stored values remain Simplified Chinese so existing records and
    /// search aliases stay backward-compatible. UI and newly-created drafts
    /// resolve a stable semantic key for the currently selected app language.
    var displayName: String {
        "\(name)（\(preparation)）"
    }

    func localizedName(locale: Locale) -> String {
        localizedCatalogValue(suffix: "name", fallback: name, locale: locale)
    }

    func localizedPreparation(locale: Locale) -> String {
        localizedCatalogValue(
            suffix: "preparation",
            fallback: preparation,
            locale: locale
        )
    }

    func localizedDisplayName(locale: Locale) -> String {
        let name = localizedName(locale: locale)
        let preparation = localizedPreparation(locale: locale)
        if locale.language.languageCode?.identifier == "en" {
            return "\(name) (\(preparation))"
        }
        return "\(name)（\(preparation)）"
    }

    var sourceDescription: String {
        if let fdcID {
            return "USDA FoodData Central · FDC \(fdcID)"
        }
        return "USDA FoodData Central · SR Legacy 2018 参考值"
    }

    var defaultStandardPortion: CommonFoodStandardPortion? {
        standardPortions.first(where: \.isDefault) ?? standardPortions.first
    }

    func nutrition(forGrams grams: Double) -> NutritionValues? {
        guard grams.isFinite, grams > 0, grams <= 10_000 else { return nil }
        return NutritionEngine.calculate(
            profile: NutritionProfile(per100Grams: nutritionPer100Grams),
            amount: .grams(Decimal(grams))
        )
    }

    func draft(
        grams: Double,
        mealType: MealType,
        date: Date,
        locale: Locale = Locale(identifier: "zh-Hans"),
        portionText: String? = nil
    ) -> FoodEntryDraft? {
        guard let nutrition = nutrition(forGrams: grams),
              let calories = nutrition.energyKcal?.doubleValue else {
            return nil
        }

        return FoodEntryDraft(
            name: localizedDisplayName(locale: locale),
            calories: calories,
            protein: nutrition.proteinG?.doubleValue,
            carbs: nutrition.carbohydratesG?.doubleValue,
            fat: nutrition.fatG?.doubleValue,
            portionText: portionText
                ?? "\(Self.amountText(grams)) \(Self.localizedGramUnit(locale: locale))",
            mealType: mealType,
            source: .referenceCatalog,
            date: date,
            amountValue: grams,
            amountUnit: .grams,
            calculationVersion: CommonFoodCatalog.calculationVersion,
            fiber: nutrition.fiberG?.doubleValue,
            sugar: nutrition.sugarG?.doubleValue,
            sodiumMg: nutrition.sodiumMg?.doubleValue,
            caffeineMg: nutrition.caffeineMg?.doubleValue
        )
    }

    private func localizedCatalogValue(
        suffix: String,
        fallback: String,
        locale: Locale
    ) -> String {
        let key = "common_food.\(id).\(suffix)"
        let value = interfaceLocalized(key, locale: locale)
        return value == key ? fallback : value
    }

    private static func localizedGramUnit(locale: Locale) -> String {
        let key = "common_food.unit.grams"
        let value = interfaceLocalized(key, locale: locale)
        return value == key ? "克" : value
    }

    private static func amountText(_ amount: Double) -> String {
        if amount.rounded() == amount {
            return String(Int(amount))
        }
        return String(format: "%.1f", amount)
    }
}

enum CommonFoodCatalog {
    static let calculationVersion = 1

    static let foods: [CommonFoodReference] = coreFoods + additionalFoods

    /// USDA FoodData Central SR Legacy（2018）的公开参考值，
    /// 统一按可食部分每 100 克保存。
    private static let coreFoods: [CommonFoodReference] = [
        CommonFoodReference(
            id: "broccoli-raw",
            name: "西兰花",
            aliases: ["青花菜", "绿花椰菜", "broccoli", "broccoli florets"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 34,
                proteinG: 2.82,
                carbohydratesG: 6.64,
                fatG: 0.37,
                fiberG: 2.6
            ),
            fdcID: 170379
        ),
        CommonFoodReference(
            id: "shrimp-cooked",
            name: "虾仁",
            aliases: ["虾", "熟虾", "shrimp", "cooked shrimp", "prawn"],
            preparation: "熟、去壳，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 99,
                proteinG: 24,
                carbohydratesG: 0.2,
                fatG: 0.28
            ),
            fdcID: 175180
        ),
        CommonFoodReference(
            id: "chicken-breast-cooked",
            name: "鸡胸肉",
            aliases: ["鸡胸", "去皮鸡胸", "chicken breast", "skinless chicken breast"],
            preparation: "烤熟、去皮、仅肉，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 165,
                proteinG: 31,
                carbohydratesG: 0,
                fatG: 3.57
            ),
            fdcID: 171477
        ),
        CommonFoodReference(
            id: "white-rice-cooked",
            name: "白米饭",
            aliases: ["米饭", "白饭", "cooked white rice", "steamed rice"],
            preparation: "长粒白米、熟、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 130,
                proteinG: 2.69,
                carbohydratesG: 28.2,
                fatG: 0.28,
                fiberG: 0.4
            ),
            fdcID: 169757
        ),
        CommonFoodReference(
            id: "salmon-cooked",
            name: "大西洋三文鱼",
            aliases: ["三文鱼", "鲑鱼", "大西洋鲑鱼", "salmon", "Atlantic salmon"],
            preparation: "养殖、干热熟制，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 206,
                proteinG: 22.1,
                carbohydratesG: 0,
                fatG: 12.4
            ),
            fdcID: 175168
        ),
        CommonFoodReference(
            id: "egg-hard-boiled",
            name: "水煮蛋",
            aliases: ["鸡蛋", "熟鸡蛋", "水煮鸡蛋", "hard-boiled egg", "boiled egg"],
            preparation: "全蛋、煮熟，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 155,
                proteinG: 12.6,
                carbohydratesG: 1.12,
                fatG: 10.6
            ),
            fdcID: 173424,
            standardPortions: [
                CommonFoodStandardPortion(
                    id: "half-large-egg",
                    grams: 25,
                    simplifiedLabel: "大号 ½ 个",
                    traditionalLabel: "大號 ½ 個",
                    englishLabel: "½ large egg"
                ),
                CommonFoodStandardPortion(
                    id: "one-large-egg",
                    grams: 50,
                    simplifiedLabel: "大号 1 个",
                    traditionalLabel: "大號 1 個",
                    englishLabel: "1 large egg",
                    isDefault: true
                ),
                CommonFoodStandardPortion(
                    id: "two-large-eggs",
                    grams: 100,
                    simplifiedLabel: "大号 2 个",
                    traditionalLabel: "大號 2 個",
                    englishLabel: "2 large eggs"
                ),
            ]
        ),
        CommonFoodReference(
            id: "spinach-raw",
            name: "菠菜",
            aliases: ["spinach"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 23,
                proteinG: 2.86,
                carbohydratesG: 3.63,
                fatG: 0.39,
                fiberG: 2.2
            ),
            fdcID: 168462
        ),
        CommonFoodReference(
            id: "banana-raw",
            name: "香蕉",
            aliases: ["banana"],
            preparation: "生、去皮",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 89,
                proteinG: 1.09,
                carbohydratesG: 22.8,
                fatG: 0.33,
                fiberG: 2.6
            ),
            fdcID: 173944,
            standardPortions: [
                CommonFoodStandardPortion(
                    id: "small-banana",
                    grams: 101,
                    simplifiedLabel: "小根 1 根",
                    traditionalLabel: "小根 1 根",
                    englishLabel: "1 small banana"
                ),
                CommonFoodStandardPortion(
                    id: "medium-banana",
                    grams: 118,
                    simplifiedLabel: "中等 1 根",
                    traditionalLabel: "中等 1 根",
                    englishLabel: "1 medium banana",
                    isDefault: true
                ),
                CommonFoodStandardPortion(
                    id: "large-banana",
                    grams: 136,
                    simplifiedLabel: "大根 1 根",
                    traditionalLabel: "大根 1 根",
                    englishLabel: "1 large banana"
                ),
            ]
        ),
        CommonFoodReference(
            id: "avocado-raw",
            name: "牛油果",
            aliases: ["鳄梨", "avocado", "alligator pear"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 160,
                proteinG: 2,
                carbohydratesG: 8.53,
                fatG: 14.7,
                fiberG: 6.7
            ),
            fdcID: 171705
        ),
        CommonFoodReference(
            id: "apple-raw",
            name: "苹果",
            aliases: ["apple"],
            preparation: "生、带皮",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 52,
                proteinG: 0.26,
                carbohydratesG: 13.81,
                fatG: 0.17,
                fiberG: 2.4
            ),
            fdcID: 171688,
            standardPortions: [
                CommonFoodStandardPortion(
                    id: "small-apple",
                    grams: 149,
                    simplifiedLabel: "小号 1 个",
                    traditionalLabel: "小號 1 個",
                    englishLabel: "1 small apple"
                ),
                CommonFoodStandardPortion(
                    id: "medium-apple",
                    grams: 182,
                    simplifiedLabel: "中等 1 个",
                    traditionalLabel: "中等 1 個",
                    englishLabel: "1 medium apple",
                    isDefault: true
                ),
                CommonFoodStandardPortion(
                    id: "large-apple",
                    grams: 223,
                    simplifiedLabel: "大号 1 个",
                    traditionalLabel: "大號 1 個",
                    englishLabel: "1 large apple"
                ),
            ]
        ),
        CommonFoodReference(
            id: "carrot-raw",
            name: "胡萝卜",
            aliases: ["红萝卜", "carrot"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 41,
                proteinG: 0.93,
                carbohydratesG: 9.58,
                fatG: 0.24,
                fiberG: 2.8
            ),
            fdcID: 170393,
            standardPortions: [
                CommonFoodStandardPortion(
                    id: "small-carrot",
                    grams: 50,
                    simplifiedLabel: "小根 1 根",
                    traditionalLabel: "小根 1 根",
                    englishLabel: "1 small carrot"
                ),
                CommonFoodStandardPortion(
                    id: "medium-carrot",
                    grams: 61,
                    simplifiedLabel: "中等 1 根",
                    traditionalLabel: "中等 1 根",
                    englishLabel: "1 medium carrot",
                    isDefault: true
                ),
                CommonFoodStandardPortion(
                    id: "large-carrot",
                    grams: 72,
                    simplifiedLabel: "大根 1 根",
                    traditionalLabel: "大根 1 根",
                    englishLabel: "1 large carrot"
                ),
            ]
        ),
        CommonFoodReference(
            id: "tofu-firm",
            name: "硬豆腐",
            aliases: ["豆腐", "板豆腐", "老豆腐", "firm tofu", "bean curd"],
            preparation: "硫酸钙凝固、未煎炸",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 144,
                proteinG: 17.3,
                carbohydratesG: 2.78,
                fatG: 8.72,
                fiberG: 2.3
            ),
            fdcID: 172475
        ),
        CommonFoodReference(
            id: "greek-yogurt-nonfat",
            name: "无脂原味希腊酸奶",
            aliases: ["希腊酸奶", "0脂希腊酸奶", "原味希腊酸奶", "plain Greek yogurt", "nonfat Greek yogurt"],
            preparation: "即食、原味、无脂配方",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 59,
                proteinG: 10.2,
                carbohydratesG: 3.6,
                fatG: 0.39
            ),
            fdcID: 170894
        )
    ]

    static func food(id: String) -> CommonFoodReference? {
        foods.first { $0.id == id }
    }

    private static let referenceIDByStoredName: [String: String] = {
        let locales = [
            Locale(identifier: "zh-Hans"),
            Locale(identifier: "zh-Hant-TW"),
            Locale(identifier: "en-US"),
        ]
        var result: [String: String] = [:]
        for food in foods {
            for locale in locales {
                let names = [
                    food.localizedDisplayName(locale: locale),
                    food.localizedName(locale: locale),
                ]
                for name in names where result[name] == nil {
                    // 保持旧实现 `foods.first` 的冲突优先级。
                    result[name] = food.id
                }
            }
        }
        return result
    }()

    /// 旧记录只保存了本地化后的名称；切换 App 语言后仍尽量恢复同一个参考库身份，
    /// 让「常吃」不会因为简繁英显示名不同而拆成三组。
    static func referenceID(forStoredName storedName: String) -> String? {
        referenceIDByStoredName[storedName]
    }

    static func search(_ query: String) -> [CommonFoodReference] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else {
            return featuredFoodIDs.compactMap(food(id:))
        }

        return foods.enumerated().compactMap {
            pair -> (food: CommonFoodReference, score: Int, index: Int)? in
            let (index, food) = pair
            guard let score = matchScore(food, query: normalizedQuery) else {
                return nil
            }
            return (food, score, index)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.index < $1.index
            }
            return $0.score < $1.score
        }
        .map(\.food)
    }

    private static let featuredFoodIDs = [
        "white-rice-cooked",
        "chicken-breast-cooked",
        "egg-hard-boiled",
        "pasta-cooked",
        "whole-wheat-bread",
        "banana-raw",
        "apple-raw",
        "whole-milk",
        "cola-regular",
        "broccoli-raw",
        "shrimp-cooked",
        "watermelon-raw",
        "greek-yogurt-nonfat"
    ]

    private static func matchScore(
        _ food: CommonFoodReference,
        query: String
    ) -> Int? {
        let name = normalized(food.name)
        let localizedNames = supportedSearchLocales.map {
            normalized(food.localizedName(locale: $0))
        }
        let aliases = food.aliases.map(normalized) + localizedNames
        let preparations = [food.preparation] + supportedSearchLocales.map {
            food.localizedPreparation(locale: $0)
        }
        .map(normalized)

        if name == query { return 0 }
        if aliases.contains(query) { return 1 }
        if name.hasPrefix(query) { return 2 }
        if aliases.contains(where: { $0.hasPrefix(query) }) { return 3 }
        if name.contains(query) { return 4 }
        if aliases.contains(where: { $0.contains(query) }) { return 5 }
        if preparations.contains(where: { $0.contains(query) }) { return 6 }
        return nil
    }

    private static let supportedSearchLocales = [
        Locale(identifier: "zh-Hans"),
        Locale(identifier: "zh-Hant-TW"),
        Locale(identifier: "en")
    ]

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "zh-Hans")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
