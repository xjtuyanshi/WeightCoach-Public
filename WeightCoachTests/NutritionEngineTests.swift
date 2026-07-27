import XCTest
@testable import WeightCoach

final class NutritionEngineTests: XCTestCase {
    func testScalesPer100GramNutritionByExactWeight() throws {
        let profile = NutritionProfile(
            per100Grams: NutritionValues(
                energyKcal: 210,
                proteinG: 14,
                carbohydratesG: 18,
                fatG: 9,
                sodiumMg: 520,
                caffeineMg: 80
            )
        )

        let result = try XCTUnwrap(
            NutritionEngine.calculate(profile: profile, amount: .grams(170))
        )

        XCTAssertEqual(result.energyKcal, 357)
        XCTAssertEqual(result.proteinG, 23.8)
        XCTAssertEqual(result.sodiumMg, 884)
        XCTAssertEqual(result.caffeineMg, 136)
    }

    func testScalesServingNutritionByFractionalServings() throws {
        let profile = NutritionProfile(
            perServing: NutritionValues(
                energyKcal: 280,
                proteinG: 12,
                carbohydratesG: 32,
                fatG: 10
            ),
            servingGrams: 85
        )

        let result = try XCTUnwrap(
            NutritionEngine.calculate(profile: profile, amount: .servings(0.5))
        )

        XCTAssertEqual(result.energyKcal, 140)
        XCTAssertEqual(result.proteinG, 6)
    }

    func testConvertsUnitCountThroughUnitsPerServing() throws {
        let profile = NutritionProfile(
            perServing: NutritionValues(energyKcal: 210, proteinG: 14),
            servingGrams: 85,
            unitsPerServing: 5
        )

        let result = try XCTUnwrap(
            NutritionEngine.calculate(profile: profile, amount: .units(7))
        )

        XCTAssertEqual(result.energyKcal, 294)
        XCTAssertEqual(result.proteinG, 19.6)
    }

    func testConvertsGramsFromServingOnlyLabel() throws {
        let profile = NutritionProfile(
            perServing: NutritionValues(energyKcal: 210),
            servingGrams: 85
        )

        let result = try XCTUnwrap(
            NutritionEngine.calculate(profile: profile, amount: .grams(170))
        )

        XCTAssertEqual(result.energyKcal, 420)
    }

    func testCalculatesPackageFractionFromServingCount() throws {
        let profile = NutritionProfile(
            perServing: NutritionValues(energyKcal: 150),
            servingsPerPackage: 4
        )

        let result = try XCTUnwrap(
            NutritionEngine.calculate(profile: profile, amount: .packageFraction(0.25))
        )

        XCTAssertEqual(result.energyKcal, 150)
    }

    func testReturnsNilInsteadOfGuessingWhenConversionDataIsMissing() {
        let profile = NutritionProfile(
            perServing: NutritionValues(energyKcal: 210)
        )

        XCTAssertNil(
            NutritionEngine.calculate(profile: profile, amount: .grams(100))
        )
        XCTAssertNil(
            NutritionEngine.calculate(profile: profile, amount: .units(2))
        )
    }

    func testRejectsNegativeAmounts() {
        let profile = NutritionProfile(
            per100Grams: NutritionValues(energyKcal: 100)
        )

        XCTAssertNil(
            NutritionEngine.calculate(profile: profile, amount: .grams(-1))
        )
    }
}
