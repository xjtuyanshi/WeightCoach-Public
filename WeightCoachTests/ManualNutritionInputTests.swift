import XCTest
@testable import WeightCoach

final class ManualNutritionInputTests: XCTestCase {
    func testBlankOptionalNutritionRemainsUnknown() {
        XCTAssertNil(
            ManualNutritionInput.optionalNonnegativeNumber(from: "")
        )
        XCTAssertNil(
            ManualNutritionInput.optionalNonnegativeNumber(from: "   ")
        )
        XCTAssertTrue(ManualNutritionInput.isValidOptionalNumber(""))
    }

    func testExplicitZeroRemainsZero() {
        XCTAssertEqual(
            ManualNutritionInput.optionalNonnegativeNumber(from: "0"),
            0
        )
    }

    func testDecimalCommaAndWhitespaceAreAccepted() {
        XCTAssertEqual(
            ManualNutritionInput.nonnegativeNumber(from: " 12,5 "),
            12.5
        )
    }

    func testInvalidNegativeAndNonFiniteValuesAreRejected() {
        for value in ["abc", "-1", "nan", "inf"] {
            XCTAssertNil(
                ManualNutritionInput.nonnegativeNumber(from: value),
                value
            )
            XCTAssertFalse(
                ManualNutritionInput.isValidOptionalNumber(value),
                value
            )
        }
    }
}
