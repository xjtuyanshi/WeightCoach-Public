import XCTest
@testable import WeightCoach

final class CalorieEngineTests: XCTestCase {
    private let calendar = Calendar.current

    func testBMRUsesKatchMcArdleWhenBodyFatIsAvailable() {
        let result = CalorieEngine.bmr(
            weightKg: 80,
            heightCm: 170,
            age: 30,
            isMale: true,
            bodyFatPercent: 28
        )

        XCTAssertEqual(result, 1_614.16, accuracy: 0.001)
    }

    func testBMRFallsBackToMifflinStJeorWithoutBodyFat() {
        let result = CalorieEngine.bmr(
            weightKg: 80,
            heightCm: 170,
            age: 30,
            isMale: true,
            bodyFatPercent: nil
        )

        XCTAssertEqual(result, 1_717.5, accuracy: 0.001)
    }

    func testTDEEWithActiveEnergyUsesTEFAndIgnoresActivityFactor() {
        let result = CalorieEngine.tdee(
            bmr: 1_800,
            activityFactor: 1.9,
            activeEnergyKcal: 500,
            includeActiveEnergy: true
        )

        XCTAssertEqual(result, 2_480, accuracy: 0.001)
    }

    func testTDEEWithoutActiveEnergyUsesActivityFactor() {
        let result = CalorieEngine.tdee(
            bmr: 1_800,
            activityFactor: 1.2,
            activeEnergyKcal: 900,
            includeActiveEnergy: false
        )

        XCTAssertEqual(result, 2_160, accuracy: 0.001)
    }

    func testDailyDeficitIsZeroWhenGoalIsReached() {
        let result = CalorieEngine.dailyDeficit(
            currentWeightKg: 75,
            goalWeightKg: 75,
            goalEndDate: Date().addingTimeInterval(86_400)
        )

        XCTAssertEqual(result, 0)
    }

    func testDailyDeficitClampsToMaximumWithOneDayRemaining() {
        let now = Date()
        let result = CalorieEngine.dailyDeficit(
            currentWeightKg: 76,
            goalWeightKg: 75,
            goalEndDate: now.addingTimeInterval(86_400),
            now: now
        )

        XCTAssertEqual(result, 1_000)
    }

    func testDailyDeficitClampsToMinimumForFarFutureGoal() {
        let now = Date()
        let result = CalorieEngine.dailyDeficit(
            currentWeightKg: 76,
            goalWeightKg: 75,
            goalEndDate: now.addingTimeInterval(400 * 86_400),
            now: now
        )

        XCTAssertEqual(result, 250)
    }

    func testRapidFatLossDeficitStaysAt750RegardlessOfDeadline() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let oneDay = CalorieEngine.targetDeficit(
            strategy: .rapidFatLoss,
            currentWeightKg: 76,
            goalWeightKg: 75,
            goalEndDate: now.addingTimeInterval(86_400),
            now: now
        )
        let farFuture = CalorieEngine.targetDeficit(
            strategy: .rapidFatLoss,
            currentWeightKg: 76,
            goalWeightKg: 75,
            goalEndDate: now.addingTimeInterval(400 * 86_400),
            now: now
        )

        XCTAssertEqual(oneDay, 750)
        XCTAssertEqual(farFuture, 750)
    }

    func testRapidFatLossDeficitIsZeroAtOrBelowGoal() {
        let goalDate = Date().addingTimeInterval(86_400)

        XCTAssertEqual(
            CalorieEngine.targetDeficit(
                strategy: .rapidFatLoss,
                currentWeightKg: 75,
                goalWeightKg: 75,
                goalEndDate: goalDate
            ),
            0
        )
        XCTAssertEqual(
            CalorieEngine.targetDeficit(
                strategy: .rapidFatLoss,
                currentWeightKg: 74.5,
                goalWeightKg: 75,
                goalEndDate: goalDate
            ),
            0
        )
    }

    func testDeadlineStrategyKeepsExistingDynamicFormula() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = CalorieEngine.targetDeficit(
            strategy: .deadlinePaced,
            currentWeightKg: 76,
            goalWeightKg: 75,
            goalEndDate: now.addingTimeInterval(10 * 86_400),
            now: now
        )

        XCTAssertEqual(result, 770, accuracy: 0.001)
    }

    func testDailyBudgetRespectsSexSpecificFloors() {
        XCTAssertEqual(
            CalorieEngine.dailyBudget(tdee: 1_800, deficit: 900, isMale: true),
            1_500
        )
        XCTAssertEqual(
            CalorieEngine.dailyBudget(tdee: 1_500, deficit: 900, isMale: false),
            1_200
        )
        XCTAssertEqual(
            CalorieEngine.dailyBudget(tdee: 2_400, deficit: 500, isMale: true),
            1_900
        )
    }

    func testProjectedGoalDateUsesRecentWeightLossRate() throws {
        let now = Date()
        let tenDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now))
        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 10, to: now))

        let projected = try XCTUnwrap(
            CalorieEngine.projectedGoalDate(
                currentWeightKg: 77,
                goalWeightKg: 75,
                recentPoints: [
                    (date: tenDaysAgo, weightKg: 79),
                    (date: now, weightKg: 77),
                ]
            )
        )

        XCTAssertEqual(projected.timeIntervalSince(expected), 0, accuracy: 1)
    }

    func testProjectedGoalDateReturnsNilWithInsufficientData() {
        let projected = CalorieEngine.projectedGoalDate(
            currentWeightKg: 77,
            goalWeightKg: 75,
            recentPoints: [(date: .now, weightKg: 77)]
        )

        XCTAssertNil(projected)
    }

    func testProjectedGoalDateReturnsNilWhenWeightLossRateIsZero() throws {
        let now = Date()
        let sevenDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: now))

        let projected = CalorieEngine.projectedGoalDate(
            currentWeightKg: 77,
            goalWeightKg: 75,
            recentPoints: [
                (date: sevenDaysAgo, weightKg: 77),
                (date: now, weightKg: 77),
            ]
        )

        XCTAssertNil(projected)
    }
}
