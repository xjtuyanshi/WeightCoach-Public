import XCTest
@testable import WeightCoach

final class TodayCaffeineMetricsTests: XCTestCase {
    func testSumsOnlyKnownFiniteNonnegativeValues() {
        let foods = [
            food("浓缩咖啡", caffeineMg: 150),
            food("无咖啡因咖啡", caffeineMg: 0),
            food("鸡胸肉", caffeineMg: nil),
            food("错误数据", caffeineMg: -.infinity),
        ]

        let result = TodayCaffeineMetrics.calculate(foods: foods)

        XCTAssertEqual(result.knownTotalMg, 150)
        XCTAssertEqual(result.knownEntryCount, 2, "明确的 0 也属于已知值")
        XCTAssertEqual(result.unknownLikelyCaffeinatedCount, 0)
    }

    func testNilIsUnknownRatherThanZeroForLikelyCaffeinatedFood() {
        let result = TodayCaffeineMetrics.calculate(
            foods: [
                food("Starbucks Latte", caffeineMg: nil),
                food("苹果", caffeineMg: nil),
            ]
        )

        XCTAssertFalse(result.hasKnownData)
        XCTAssertEqual(result.knownTotalMg, 0)
        XCTAssertEqual(result.unknownLikelyCaffeinatedCount, 1)
    }

    private func food(_ name: String, caffeineMg: Double?) -> FoodEntry {
        FoodEntry(
            name: name,
            calories: 10,
            mealType: .snack,
            source: .manual,
            caffeineMg: caffeineMg
        )
    }
}
