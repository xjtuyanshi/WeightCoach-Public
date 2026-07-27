import XCTest
@testable import WeightCoach

final class MacroTargetEngineTests: XCTestCase {
    func testStandardTargetsUseWeightAndExistingBudget() throws {
        let targets = try XCTUnwrap(
            MacroTargetEngine.calculate(
                currentWeightKg: 80,
                budgetKcal: 1_545
            )
        )

        XCTAssertEqual(targets.proteinG, 130)
        XCTAssertEqual(targets.fatG, 43)
        XCTAssertEqual(targets.carbsG, 159.5)
        XCTAssertEqual(targets.budgetKcal, 1_545)
        XCTAssertEqual(targets.dayStyle, .standard)
        XCTAssertFalse(targets.isBudgetConstrained)
        XCTAssertEqual(targets.allocatedKcal, 1_545, accuracy: 0.001)
    }

    func testTrainingDayKeepsProteinAndBudgetWhileShiftingFuelToCarbs() throws {
        let standard = try XCTUnwrap(
            MacroTargetEngine.calculate(
                currentWeightKg: 80,
                budgetKcal: 1_545,
                dayStyle: .standard
            )
        )
        let training = try XCTUnwrap(
            MacroTargetEngine.calculate(
                currentWeightKg: 80,
                budgetKcal: 1_545,
                dayStyle: .training
            )
        )

        XCTAssertEqual(training.proteinG, standard.proteinG)
        XCTAssertEqual(training.budgetKcal, standard.budgetKcal)
        XCTAssertLessThan(training.fatG, standard.fatG)
        XCTAssertGreaterThan(training.carbsG, standard.carbsG)
        XCTAssertEqual(training.fatG, 34)
        XCTAssertEqual(training.carbsG, 179.75)
    }

    func testConstrainedBudgetNeverCreatesNegativeCarbs() throws {
        let targets = try XCTUnwrap(
            MacroTargetEngine.calculate(
                currentWeightKg: 200,
                budgetKcal: 1_200
            )
        )

        XCTAssertTrue(targets.isBudgetConstrained)
        XCTAssertGreaterThanOrEqual(targets.fatG * 9, 1_200 * 0.15)
        XCTAssertGreaterThanOrEqual(targets.carbsG, 0)
        XCTAssertEqual(targets.allocatedKcal, 1_200, accuracy: 0.001)
    }

    func testRejectsInvalidInputs() {
        XCTAssertNil(
            MacroTargetEngine.calculate(
                currentWeightKg: 0,
                budgetKcal: 1_500
            )
        )
        XCTAssertNil(
            MacroTargetEngine.calculate(
                currentWeightKg: 90,
                budgetKcal: .nan
            )
        )
    }
}
