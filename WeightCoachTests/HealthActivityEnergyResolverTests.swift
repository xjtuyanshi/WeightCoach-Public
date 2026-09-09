import XCTest
@testable import WeightCoach

final class HealthActivityEnergyResolverTests: XCTestCase {
    func testActivitySummaryWinsOverOverlappingStatisticsIntervals() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let duplicate = try XCTUnwrap(
            HealthActiveEnergyInterval(
                startDate: start,
                endDate: start.addingTimeInterval(3_600),
                kcal: 450
            )
        )

        let total = HealthActivityEnergyResolver.dailyTotal(
            activitySummaryKcal: 450,
            statisticsIntervals: [duplicate, duplicate]
        )

        XCTAssertEqual(total, 450)
    }

    func testStatisticsIntervalsAreFallbackWithoutActivitySummary() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let first = try XCTUnwrap(
            HealthActiveEnergyInterval(
                startDate: start,
                endDate: start.addingTimeInterval(1_800),
                kcal: 120
            )
        )
        let second = try XCTUnwrap(
            HealthActiveEnergyInterval(
                startDate: start.addingTimeInterval(1_800),
                endDate: start.addingTimeInterval(3_600),
                kcal: 180
            )
        )

        XCTAssertEqual(
            HealthActivityEnergyResolver.dailyTotal(
                activitySummaryKcal: nil,
                statisticsIntervals: [first, second]
            ),
            300
        )
    }

    func testInvalidActivitySummaryFallsBackToStatistics() throws {
        let interval = try XCTUnwrap(
            HealthActiveEnergyInterval(
                startDate: Date(timeIntervalSince1970: 10_000),
                endDate: Date(timeIntervalSince1970: 10_060),
                kcal: 25
            )
        )

        XCTAssertEqual(
            HealthActivityEnergyResolver.dailyTotal(
                activitySummaryKcal: .nan,
                statisticsIntervals: [interval]
            ),
            25
        )
    }
}
