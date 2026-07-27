import XCTest
@testable import WeightCoach

final class WeightEntryInputTests: XCTestCase {
    func testOptionalBodyFatAcceptsBlankAndReasonableValues() {
        XCTAssertTrue(WeightEntryInput.isOptionalBodyFatValid(""))
        XCTAssertTrue(WeightEntryInput.isOptionalBodyFatValid("  "))
        XCTAssertTrue(WeightEntryInput.isOptionalBodyFatValid("23.5"))
        XCTAssertTrue(WeightEntryInput.isOptionalBodyFatValid("23,5"))
        XCTAssertEqual(WeightEntryInput.bodyFatPercent("23,5"), 23.5)
    }

    func testOptionalBodyFatRejectsInvalidAndOutOfRangeValues() {
        for value in ["abc", "-1", "3", "70", "240"] {
            XCTAssertFalse(
                WeightEntryInput.isOptionalBodyFatValid(value),
                "\(value) 不应作为体脂率保存"
            )
            XCTAssertNil(WeightEntryInput.bodyFatPercent(value))
        }
    }
}
