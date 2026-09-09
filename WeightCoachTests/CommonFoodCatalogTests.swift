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

    func testEggStandardPortionsUseEdibleWeightAndDefaultToOneLargeEgg() throws {
        let egg = try XCTUnwrap(
            CommonFoodCatalog.food(id: "egg-hard-boiled")
        )
        let defaultPortion = try XCTUnwrap(egg.defaultStandardPortion)

        XCTAssertEqual(defaultPortion.id, "one-large-egg")
        XCTAssertEqual(defaultPortion.grams, 50)
        XCTAssertEqual(
            defaultPortion.searchSummary(
                locale: Locale(identifier: "zh-Hans")
            ),
            "大号 1 个约 50 克可食部分"
        )
        XCTAssertEqual(
            try XCTUnwrap(
                egg.nutrition(forGrams: defaultPortion.grams)?.energyKcal
            ).doubleValue,
            77.5,
            accuracy: 0.001
        )
    }

    func testBananaStandardPortionsKeepUSDAFruitSizes() throws {
        let banana = try XCTUnwrap(
            CommonFoodCatalog.food(id: "banana-raw")
        )

        XCTAssertEqual(
            banana.standardPortions.map(\.grams),
            [101, 118, 136]
        )
        XCTAssertEqual(banana.defaultStandardPortion?.grams, 118)
        XCTAssertEqual(
            try XCTUnwrap(
                banana.nutrition(forGrams: 118)?.energyKcal
            ).doubleValue,
            105.02,
            accuracy: 0.001
        )
    }

    func testStandardPortionDescriptionsSupportAllAppLanguages() throws {
        let egg = try XCTUnwrap(
            CommonFoodCatalog.food(id: "egg-hard-boiled")
        )
        let portion = try XCTUnwrap(egg.defaultStandardPortion)

        XCTAssertEqual(
            portion.savedDescription(locale: Locale(identifier: "zh-Hans")),
            "大号 1 个（约 50 克）"
        )
        XCTAssertEqual(
            portion.savedDescription(locale: Locale(identifier: "zh-Hant-TW")),
            "大號 1 個（約 50 公克）"
        )
        XCTAssertEqual(
            portion.savedDescription(locale: Locale(identifier: "en-US")),
            "1 large egg (about 50 g)"
        )
        XCTAssertEqual(
            portion.approximateWeightDescription(
                locale: Locale(identifier: "zh-Hant-TW")
            ),
            "約 50 公克"
        )
    }

    func testDraftCanPreserveHumanReadableStandardPortion() throws {
        let bread = try XCTUnwrap(
            CommonFoodCatalog.food(id: "whole-wheat-bread")
        )
        let portion = try XCTUnwrap(bread.defaultStandardPortion)
        let draft = try XCTUnwrap(
            bread.draft(
                grams: portion.grams,
                mealType: .breakfast,
                date: .now,
                locale: Locale(identifier: "en-US"),
                portionText: portion.savedDescription(
                    locale: Locale(identifier: "en-US")
                )
            )
        )

        XCTAssertEqual(draft.amountValue, 32)
        XCTAssertEqual(draft.amountUnit, .grams)
        XCTAssertEqual(draft.portionText, "1 slice (about 32 g)")
        XCTAssertEqual(draft.calories, 80.64, accuracy: 0.001)
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

    func testCachedSearchPreservesAllCatalogTermsAndRanking() {
        let locales = [
            Locale(identifier: "zh-Hans"),
            Locale(identifier: "zh-Hant-TW"),
            Locale(identifier: "en")
        ]
        var queries: Set<String> = [
            "", "   ", "！", "西", "蝦", "米饭", "raw", "cooked",
            "  BROC COLI  ", "ｂｒｏｃｃｏｌｉ", "不存在的食物",
            "chicken-breast", "Greek YOGURT", "可食部分"
        ]
        for food in CommonFoodCatalog.foods {
            let terms = [food.name, food.preparation] + food.aliases
                + locales.flatMap {
                    [
                        food.localizedName(locale: $0),
                        food.localizedPreparation(locale: $0)
                    ]
                }
            for term in terms {
                queries.insert(term)
                queries.insert(String(term.prefix(1)))
                queries.insert(String(term.prefix(2)))
                queries.insert(String(term.suffix(2)))
            }
        }

        for query in queries.sorted() {
            XCTAssertEqual(
                CommonFoodCatalog.search(query).map(\.id),
                legacySearch(query).map(\.id),
                "Search results or ranking changed for: \(query)"
            )
        }
        print("COMMON_FOOD_SEARCH_EQUIVALENCE foods=\(CommonFoodCatalog.foods.count) queries=\(queries.count) locales=3")
    }

    func testRepeatedSearchBenchmarkPreservesResults() {
        let queries = [
            "西", "西兰花", "蝦", "shrimp", "rice", "鸡", "鸡胸肉",
            "生", "cooked", "milk", "蛋", "bread", "avocado",
            "香蕉", "酪梨", "Greek yogurt", "无", "broccoli",
            "ｂｒｏｃｃｏｌｉ", "不存在的食物"
        ]
        // Both paths are warm: this measures repeated typing, not one-time
        // catalog initialization or simulator startup. Timings are evidence,
        // never a machine-speed-dependent pass/fail threshold.
        for query in queries {
            _ = CommonFoodCatalog.search(query)
            _ = legacySearch(query)
        }

        let batches = 5
        let roundsPerBatch = 2
        var legacyDurations: [Double] = []
        var indexedDurations: [Double] = []
        func runBatch(_ search: (String) -> [CommonFoodReference]) -> (Double, Int) {
            let start = ProcessInfo.processInfo.systemUptime
            var count = 0
            for _ in 0..<roundsPerBatch {
                for query in queries {
                    count += search(query).count
                }
            }
            return (ProcessInfo.processInfo.systemUptime - start, count)
        }

        // Alternate execution order so one path does not always benefit from
        // running first. Report the median batch to reduce scheduling noise.
        for batch in 0..<batches {
            let legacy: (Double, Int)
            let indexed: (Double, Int)
            if batch.isMultiple(of: 2) {
                legacy = runBatch(legacySearch)
                indexed = runBatch(CommonFoodCatalog.search)
            } else {
                indexed = runBatch(CommonFoodCatalog.search)
                legacy = runBatch(legacySearch)
            }
            XCTAssertEqual(indexed.1, legacy.1)
            legacyDurations.append(legacy.0)
            indexedDurations.append(indexed.0)
        }
        let legacyMedian = legacyDurations.sorted()[batches / 2]
        let indexedMedian = indexedDurations.sorted()[batches / 2]
        let queriesPerBatch = roundsPerBatch * queries.count
        print(String(
            format: "COMMON_FOOD_SEARCH_BENCHMARK total_queries=%d batches=%d queries_per_batch=%d legacy_median_ms=%.3f indexed_median_ms=%.3f legacy_per_query_ms=%.3f indexed_per_query_ms=%.3f speedup=%.2f",
            batches * queriesPerBatch,
            batches,
            queriesPerBatch,
            legacyMedian * 1_000,
            indexedMedian * 1_000,
            legacyMedian * 1_000 / Double(queriesPerBatch),
            indexedMedian * 1_000 / Double(queriesPerBatch),
            legacyMedian / max(indexedMedian, Double.leastNonzeroMagnitude)
        ))
    }

    /// Frozen pre-index behavior, including localized aliases, preparation
    /// matching, and stable catalog ordering for equal scores.
    private func legacySearch(_ query: String) -> [CommonFoodReference] {
        let query = legacyNormalized(query)
        guard !query.isEmpty else {
            return [
                "white-rice-cooked", "chicken-breast-cooked", "egg-hard-boiled",
                "pasta-cooked", "whole-wheat-bread", "banana-raw", "apple-raw",
                "whole-milk", "cola-regular", "broccoli-raw", "shrimp-cooked",
                "watermelon-raw", "greek-yogurt-nonfat"
            ].compactMap { CommonFoodCatalog.food(id: $0) }
        }
        let locales = [
            Locale(identifier: "zh-Hans"),
            Locale(identifier: "zh-Hant-TW"),
            Locale(identifier: "en")
        ]
        return CommonFoodCatalog.foods.enumerated().compactMap {
            pair -> (food: CommonFoodReference, score: Int, index: Int)? in
            let (index, food) = pair
            let name = legacyNormalized(food.name)
            let aliases = food.aliases.map(legacyNormalized) + locales.map {
                legacyNormalized(food.localizedName(locale: $0))
            }
            let preparations = [food.preparation] + locales.map {
                food.localizedPreparation(locale: $0)
            }
            .map(legacyNormalized)
            let score: Int
            if name == query { score = 0 }
            else if aliases.contains(query) { score = 1 }
            else if name.hasPrefix(query) { score = 2 }
            else if aliases.contains(where: { $0.hasPrefix(query) }) { score = 3 }
            else if name.contains(query) { score = 4 }
            else if aliases.contains(where: { $0.contains(query) }) { score = 5 }
            else if preparations.contains(where: { $0.contains(query) }) { score = 6 }
            else { return nil }
            return (food, score, index)
        }
        .sorted {
            $0.score == $1.score ? $0.index < $1.index : $0.score < $1.score
        }
        .map(\.food)
    }

    private func legacyNormalized(_ value: String) -> String {
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
