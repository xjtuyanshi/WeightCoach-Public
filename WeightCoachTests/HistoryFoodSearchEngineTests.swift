import XCTest
@testable import WeightCoach

final class HistoryFoodSearchEngineTests: XCTestCase {
    func testSimplifiedHistoryMatchesTraditionalEnglishAndAliases() throws {
        let shrimp = try XCTUnwrap(CommonFoodCatalog.food(id: "shrimp-cooked"))

        for query in ["虾仁", "蝦仁", "shrimp", "prawn", "熟虾"] {
            XCTAssertTrue(
                HistoryFoodSearchEngine(query: query).matches(name: shrimp.displayName),
                "Expected Simplified Chinese history to match \(query)"
            )
        }
    }

    func testStoredNamesInAllSupportedLanguagesMatchAllThreeSearchLanguages() throws {
        let shrimp = try XCTUnwrap(CommonFoodCatalog.food(id: "shrimp-cooked"))

        for language in ["zh-Hans", "zh-Hant-TW", "en-US"] {
            let locale = Locale(identifier: language)
            for storedName in [
                shrimp.localizedName(locale: locale),
                shrimp.localizedDisplayName(locale: locale),
            ] {
                for query in ["虾仁", "蝦仁", "shrimp"] {
                    XCTAssertTrue(
                        HistoryFoodSearchEngine(query: query).matches(name: storedName),
                        "Expected \(storedName) to match \(query)"
                    )
                }
            }
        }
    }

    func testPartialNamesAndAliasesRemainSearchable() throws {
        let broccoli = try XCTUnwrap(CommonFoodCatalog.food(id: "broccoli-raw"))

        for query in ["西", "青花", "绿花椰菜", "brocc", "broccoli florets"] {
            XCTAssertTrue(
                HistoryFoodSearchEngine(query: query).matches(name: broccoli.displayName)
            )
        }
        XCTAssertFalse(
            HistoryFoodSearchEngine(query: "shrimp").matches(name: broccoli.displayName)
        )
    }

    func testNormalizesWhitespaceCaseAndFullWidthCharacters() {
        for query in ["  SHRIMP  ", "ｓｈｒｉｍｐ", "\n SH RIMP\t"] {
            XCTAssertTrue(HistoryFoodSearchEngine(query: query).matches(name: "虾仁"))
        }
    }

    func testEmptyAndWhitespaceQueriesMatchAnyOriginalName() {
        for query in ["", "  \t\n　"] {
            XCTAssertTrue(HistoryFoodSearchEngine(query: query).matches(name: "自制午饭"))
            XCTAssertTrue(HistoryFoodSearchEngine(query: query).matches(name: "虾仁"))
        }
    }

    func testOriginalPortionMealAndSourceFieldsRemainSearchable() {
        for query in ["200 克", "晚餐", "手动"] {
            XCTAssertTrue(
                HistoryFoodSearchEngine(query: query).matches(
                    name: "自制午饭",
                    portionText: "200 克",
                    mealLabel: "晚餐",
                    sourceLabel: "手动"
                )
            )
        }
        XCTAssertTrue(
            HistoryFoodSearchEngine(query: "DINNER").matches(
                name: "Homemade meal",
                mealLabel: "Dinner"
            )
        )
    }

    func testCustomNamesOnlyMatchTheirOriginalTextWithoutInferredTranslation() {
        XCTAssertTrue(
            HistoryFoodSearchEngine(query: "虾仁").matches(name: "我的虾仁炒饭")
        )
        XCTAssertFalse(
            HistoryFoodSearchEngine(query: "shrimp").matches(name: "我的虾仁炒饭")
        )
        XCTAssertFalse(
            HistoryFoodSearchEngine(query: "蝦仁").matches(name: "我的虾仁炒饭")
        )
        XCTAssertTrue(
            HistoryFoodSearchEngine(query: "cafe bowl").matches(name: "Café Bowl")
        )
        XCTAssertFalse(
            HistoryFoodSearchEngine(query: "虾仁").matches(name: "Homemade shrimp bowl")
        )
    }
}
