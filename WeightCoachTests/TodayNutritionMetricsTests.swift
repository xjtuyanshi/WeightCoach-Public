import XCTest
@testable import WeightCoach

final class TodayNutritionMetricsTests: XCTestCase {
    func testUnknownMacrosAreNotConvertedToZero() throws {
        let complete = FoodEntry(
            name: "完整记录",
            calories: 800,
            protein: 50,
            carbs: 80,
            fat: 20,
            mealType: .lunch,
            source: .manual
        )
        let caloriesOnly = FoodEntry(
            name: "仅热量",
            calories: 400,
            mealType: .dinner,
            source: .manual
        )

        let metrics = TodayNutritionMetrics.calculate(
            foods: [complete, caloriesOnly]
        )

        XCTAssertEqual(metrics.totalCalories, 1_200)
        XCTAssertEqual(metrics.proteinG, 50)
        XCTAssertEqual(metrics.carbsG, 80)
        XCTAssertEqual(metrics.fatG, 20)
        XCTAssertEqual(
            try XCTUnwrap(metrics.completeMacroCoverage),
            2.0 / 3.0,
            accuracy: 0.001
        )
        XCTAssertEqual(metrics.incompleteMacroEntryCount, 1)
        XCTAssertTrue(metrics.hasIncompleteMacroData)
    }

    func testExplicitZeroIsKnownNutrition() {
        let entry = FoodEntry(
            name: "无脂饮料",
            calories: 20,
            protein: 0,
            carbs: 5,
            fat: 0,
            mealType: .snack,
            source: .manual
        )

        let metrics = TodayNutritionMetrics.calculate(foods: [entry])

        XCTAssertEqual(metrics.proteinG, 0)
        XCTAssertEqual(metrics.fatG, 0)
        XCTAssertEqual(metrics.completeMacroCoverage, 1)
        XCTAssertEqual(metrics.incompleteMacroEntryCount, 0)
        XCTAssertFalse(metrics.hasIncompleteMacroData)
    }

    func testNoMacroDataRemainsNil() {
        let entry = FoodEntry(
            name: "未知营养",
            calories: 300,
            mealType: .dinner,
            source: .manual
        )

        let metrics = TodayNutritionMetrics.calculate(foods: [entry])

        XCTAssertNil(metrics.proteinG)
        XCTAssertNil(metrics.carbsG)
        XCTAssertNil(metrics.fatG)
        XCTAssertEqual(metrics.completeMacroCoverage, 0)
        XCTAssertEqual(metrics.incompleteMacroEntryCount, 1)
    }

    func testZeroCalorieUnknownEntryStillMarksDataIncomplete() {
        let complete = FoodEntry(
            name: "完整记录",
            calories: 1_000,
            protein: 50,
            carbs: 100,
            fat: 30,
            mealType: .lunch,
            source: .manual
        )
        let unknownZeroCalorie = FoodEntry(
            name: "未补全饮料",
            calories: 0,
            mealType: .snack,
            source: .manual
        )

        let metrics = TodayNutritionMetrics.calculate(
            foods: [complete, unknownZeroCalorie]
        )

        XCTAssertEqual(metrics.completeMacroCoverage, 1)
        XCTAssertEqual(metrics.incompleteMacroEntryCount, 1)
        XCTAssertTrue(metrics.hasIncompleteMacroData)
    }

    func testEmptyDayHasNoCoverageClaim() {
        let metrics = TodayNutritionMetrics.calculate(foods: [])

        XCTAssertNil(metrics.completeMacroCoverage)
        XCTAssertEqual(metrics.incompleteMacroEntryCount, 0)
        XCTAssertEqual(metrics.totalCalories, 0)
        XCTAssertEqual(metrics.entryCount, 0)
        XCTAssertFalse(metrics.hasIncompleteMacroData)
    }
}
