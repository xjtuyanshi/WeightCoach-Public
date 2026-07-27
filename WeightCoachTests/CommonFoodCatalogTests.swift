import XCTest
@testable import WeightCoach

final class CommonFoodCatalogTests: XCTestCase {
    func testSearchSupportsChineseEnglishAliasesAndCaseFolding() {
        XCTAssertEqual(
            CommonFoodCatalog.search("西兰花").first?.id,
            "broccoli-raw"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("BROCCOLI").first?.id,
            "broccoli-raw"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("shrimp").first?.id,
            "shrimp-cooked"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("水煮蛋").first?.id,
            "egg-hard-boiled"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("青花菜").first?.id,
            "broccoli-raw"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("蝦仁").first?.id,
            "shrimp-cooked"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("酪梨").first?.id,
            "avocado-raw"
        )
    }

    func testSingleChineseCharacterReturnsAllMatchingFoodsImmediately() throws {
        let ids = CommonFoodCatalog.search("西").map(\.id)

        XCTAssertTrue(ids.contains("broccoli-raw"))
        XCTAssertTrue(ids.contains("watermelon-raw"))
        XCTAssertTrue(ids.contains("tomato-raw"))
        XCTAssertLessThan(
            try XCTUnwrap(ids.firstIndex(of: "broccoli-raw")),
            try XCTUnwrap(ids.firstIndex(of: "watermelon-raw"))
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("兰").first?.id,
            "broccoli-raw"
        )
    }

    func testSearchNormalizesEnglishWhitespaceCaseAndWidth() {
        XCTAssertEqual(
            CommonFoodCatalog.search("  BROC COLI  ").first?.id,
            "broccoli-raw"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("shrIMP").first?.id,
            "shrimp-cooked"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("ｂｒｏｃｃｏｌｉ").first?.id,
            "broccoli-raw"
        )
    }

    func testSearchRanksExactAliasBeforeContainsMatch() {
        let results = CommonFoodCatalog.search("米饭")

        XCTAssertEqual(results.first?.id, "white-rice-cooked")
        XCTAssertTrue(results.contains { $0.id == "brown-rice-cooked" })
    }

    func testEmptyQueryKeepsCuratedCommonFoods() {
        let emptyIDs = CommonFoodCatalog.search("").map(\.id)
        let whitespaceIDs = CommonFoodCatalog.search("   ").map(\.id)

        XCTAssertEqual(emptyIDs, whitespaceIDs)
        XCTAssertTrue(emptyIDs.contains("broccoli-raw"))
        XCTAssertTrue(emptyIDs.contains("watermelon-raw"))
        XCTAssertTrue(emptyIDs.contains("white-rice-cooked"))
        XCTAssertTrue(emptyIDs.contains("chicken-breast-cooked"))
    }

    func testExpandedWatermelonReferenceAndScaling() throws {
        let watermelon = try XCTUnwrap(
            CommonFoodCatalog.food(id: "watermelon-raw")
        )
        let nutrition = try XCTUnwrap(
            watermelon.nutrition(forGrams: 150)
        )

        XCTAssertEqual(watermelon.fdcID, 167765)
        XCTAssertEqual(
            try XCTUnwrap(nutrition.energyKcal).doubleValue,
            45,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nutrition.carbohydratesG).doubleValue,
            11.325,
            accuracy: 0.001
        )
    }

    func testPreviousCommonFoodsRemainSearchableInUnifiedCatalog() {
        XCTAssertEqual(
            CommonFoodCatalog.search("面条").first?.id,
            "pasta-cooked"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("全麦面包").first?.id,
            "whole-wheat-bread"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("牛奶").first?.id,
            "whole-milk"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("可乐").first?.id,
            "cola-regular"
        )
        XCTAssertEqual(
            CommonFoodCatalog.search("拿铁").first?.id,
            "latte-hot-2-percent-unsweetened"
        )
    }

    func testBroccoliNutritionScalesTo150Grams() throws {
        let broccoli = try XCTUnwrap(
            CommonFoodCatalog.food(id: "broccoli-raw")
        )
        let nutrition = try XCTUnwrap(
            broccoli.nutrition(forGrams: 150)
        )

        XCTAssertEqual(
            try XCTUnwrap(nutrition.energyKcal).doubleValue,
            51,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nutrition.proteinG).doubleValue,
            4.23,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nutrition.carbohydratesG).doubleValue,
            9.96,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nutrition.fatG).doubleValue,
            0.555,
            accuracy: 0.001
        )
    }

    func testDraftPreservesReferenceSourceWeightAndNutritionSnapshot() throws {
        let shrimp = try XCTUnwrap(
            CommonFoodCatalog.food(id: "shrimp-cooked")
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = try XCTUnwrap(
            shrimp.draft(
                grams: 200,
                mealType: .dinner,
                date: date
            )
        )

        XCTAssertEqual(draft.name, "虾仁（熟、去壳，不含额外用油）")
        XCTAssertEqual(draft.calories, 198, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(draft.protein), 48, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(draft.carbs), 0.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(draft.fat), 0.56, accuracy: 0.001)
        XCTAssertEqual(draft.portionText, "200 克")
        XCTAssertEqual(draft.amountValue, 200)
        XCTAssertEqual(draft.amountUnit, .grams)
        XCTAssertEqual(draft.source, .referenceCatalog)
        XCTAssertEqual(draft.calculationVersion, CommonFoodCatalog.calculationVersion)
        XCTAssertEqual(draft.date, date)
    }

    func testFoodNameAndPreparationUseSelectedLanguage() throws {
        let broccoli = try XCTUnwrap(
            CommonFoodCatalog.food(id: "broccoli-raw")
        )
        let shrimp = try XCTUnwrap(
            CommonFoodCatalog.food(id: "shrimp-cooked")
        )

        XCTAssertEqual(
            broccoli.localizedDisplayName(locale: Locale(identifier: "zh-Hans")),
            "西兰花（生，可食部分）"
        )
        XCTAssertEqual(
            broccoli.localizedDisplayName(locale: Locale(identifier: "zh-Hant-TW")),
            "青花菜（生鮮，可食部分）"
        )
        XCTAssertEqual(
            broccoli.localizedDisplayName(locale: Locale(identifier: "en-US")),
            "Broccoli (Raw, edible portion)"
        )
        XCTAssertEqual(
            shrimp.localizedPreparation(locale: Locale(identifier: "zh-Hant-TW")),
            "熟、去殼，不含額外用油"
        )
    }

    func testEveryCatalogFoodHasCompleteThreeLanguagePresentation() {
        let locales = [
            Locale(identifier: "zh-Hans"),
            Locale(identifier: "zh-Hant-TW"),
            Locale(identifier: "en-US")
        ]

        for food in CommonFoodCatalog.foods {
            for locale in locales {
                let name = food.localizedName(locale: locale)
                let preparation = food.localizedPreparation(locale: locale)

                XCTAssertFalse(name.isEmpty, "\(food.id) \(locale.identifier)")
                XCTAssertFalse(
                    preparation.isEmpty,
                    "\(food.id) \(locale.identifier)"
                )
                XCTAssertFalse(
                    name.hasPrefix("common_food."),
                    "\(food.id) \(locale.identifier)"
                )
                XCTAssertFalse(
                    preparation.hasPrefix("common_food."),
                    "\(food.id) \(locale.identifier)"
                )
            }
        }
    }

    func testDraftUsesSelectedLanguageForNameAndGramUnit() throws {
        let shrimp = try XCTUnwrap(
            CommonFoodCatalog.food(id: "shrimp-cooked")
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let english = try XCTUnwrap(
            shrimp.draft(
                grams: 200,
                mealType: .dinner,
                date: date,
                locale: Locale(identifier: "en-US")
            )
        )
        XCTAssertEqual(
            english.name,
            "Shrimp (Cooked and peeled; no added oil)"
        )
        XCTAssertEqual(english.portionText, "200 g")

        let traditionalChinese = try XCTUnwrap(
            shrimp.draft(
                grams: 200,
                mealType: .dinner,
                date: date,
                locale: Locale(identifier: "zh-Hant-TW")
            )
        )
        XCTAssertEqual(
            traditionalChinese.name,
            "蝦仁（熟、去殼，不含額外用油）"
        )
        XCTAssertEqual(traditionalChinese.portionText, "200 公克")
    }

    func testInvalidWeightsCannotCreateNutritionOrDraft() throws {
        let broccoli = try XCTUnwrap(
            CommonFoodCatalog.food(id: "broccoli-raw")
        )

        XCTAssertNil(broccoli.nutrition(forGrams: 0))
        XCTAssertNil(broccoli.nutrition(forGrams: -10))
        XCTAssertNil(broccoli.nutrition(forGrams: 10_001))
        XCTAssertNil(
            broccoli.draft(
                grams: .nan,
                mealType: .lunch,
                date: .now
            )
        )
    }

    func testCatalogHasUniqueIDsAndCompleteMacroReferences() {
        XCTAssertGreaterThanOrEqual(CommonFoodCatalog.foods.count, 48)
        XCTAssertEqual(
            Set(CommonFoodCatalog.foods.map(\.id)).count,
            CommonFoodCatalog.foods.count
        )
        let fdcIDs = CommonFoodCatalog.foods.compactMap(\.fdcID)
        XCTAssertEqual(Set(fdcIDs).count, CommonFoodCatalog.foods.count)

        for food in CommonFoodCatalog.foods {
            guard let energy = food.nutritionPer100Grams.energyKcal,
                  let protein = food.nutritionPer100Grams.proteinG,
                  let carbohydrates = food.nutritionPer100Grams.carbohydratesG,
                  let fat = food.nutritionPer100Grams.fatG else {
                XCTFail("营养数据不完整：\(food.id)")
                continue
            }
            XCTAssertGreaterThan(energy.doubleValue, 0, food.id)
            XCTAssertGreaterThanOrEqual(protein.doubleValue, 0, food.id)
            XCTAssertGreaterThanOrEqual(carbohydrates.doubleValue, 0, food.id)
            XCTAssertGreaterThanOrEqual(fat.doubleValue, 0, food.id)
            XCTAssertNotNil(food.fdcID, food.id)
        }
    }
}
