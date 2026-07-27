import XCTest
@testable import WeightCoach

final class StarbucksCustomizationEngineTests: XCTestCase {
    func testUnchangedStandardRecipeKeepsOfficialBaseline() throws {
        let result = try XCTUnwrap(
            StarbucksCustomizationEngine.estimateVentiIcedShakenEspresso(
                standardSyrupPumps: 4,
                finalTotalSyrupPumps: 4,
                includesBlueCoconutProteinColdFoam: false
            )
        )

        XCTAssertEqual(result.officialStandardCalories, 160)
        XCTAssertEqual(result.syrupAdjustmentCalories, 0)
        XCTAssertEqual(result.recommendedCalories, 160)
        XCTAssertEqual(result.caffeineMg, 300)
    }

    func testReducingSyrupSubtractsOnlyThePumpDifference() throws {
        let result = try XCTUnwrap(
            StarbucksCustomizationEngine.estimateVentiIcedShakenEspresso(
                standardSyrupPumps: 4,
                finalTotalSyrupPumps: 1,
                includesBlueCoconutProteinColdFoam: false
            )
        )

        XCTAssertEqual(result.syrupAdjustmentCalories, -52.5, accuracy: 0.001)
        XCTAssertEqual(result.customizedBaseCalories, 107.5, accuracy: 0.001)
        XCTAssertEqual(result.recommendedCalories, 110)
        XCTAssertEqual(result.caffeineMg, 300, "减少糖浆不应减少浓缩咖啡因")
    }

    func testCurrentScreenshotConfigurationIncludesFoamAsEstimateRange() throws {
        let result = try XCTUnwrap(
            StarbucksCustomizationEngine.estimateVentiIcedShakenEspresso(
                standardSyrupPumps: 4,
                finalTotalSyrupPumps: 1,
                includesBlueCoconutProteinColdFoam: true
            )
        )

        XCTAssertEqual(result.recommendedCalories, 400)
        XCTAssertEqual(result.calorieLowerBound, 370)
        XCTAssertEqual(result.calorieUpperBound, 430)
        XCTAssertEqual(result.caffeineMg, 300)
        XCTAssertEqual(result.proteinG, 21)
    }

    func testRejectsOutOfRangePumpCounts() {
        XCTAssertNil(
            StarbucksCustomizationEngine.estimateVentiIcedShakenEspresso(
                standardSyrupPumps: -1,
                finalTotalSyrupPumps: 1,
                includesBlueCoconutProteinColdFoam: true
            )
        )
        XCTAssertNil(
            StarbucksCustomizationEngine.estimateVentiIcedShakenEspresso(
                standardSyrupPumps: 4,
                finalTotalSyrupPumps: 13,
                includesBlueCoconutProteinColdFoam: true
            )
        )
    }
}
