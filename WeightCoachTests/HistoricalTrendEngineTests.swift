import XCTest
@testable import WeightCoach

final class HistoricalTrendEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    func testWatchModeUsesReplacementModelAndSignedWeekendSurplusOffsetsDeficits() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 26, hour: 12)
        let foods = [
            food(on: 0, from: start, calories: 1_800),
            food(on: 1, from: start, calories: 1_900),
            food(on: 2, from: start, calories: 1_850),
            food(on: 3, from: start, calories: 1_900),
            food(on: 4, from: start, calories: 1_900),
            food(on: 5, from: start, calories: 3_000),
            food(on: 6, from: start, calories: 2_800),
        ]
        let active = (0..<7).map {
            DailyActiveEnergyReading(
                dayStart: day($0, from: start),
                kcal: 300
            )
        }
        let configuration = config(
            activityFactor: 9,
            includeActiveEnergy: true,
            fallbackWeightKg: 80,
            calibratedBodyFatPercent: nil
        )

        let result = calculate(
            start: start,
            reference: reference,
            foods: foods,
            configuration: configuration,
            healthData: HistoricalTrendHealthData(
                dailyActiveEnergy: active,
                activeEnergyIntervals: [],
                weightPoints: [],
                bodyFatPoints: [],
                manualOverlapDataAvailable: true
            )
        )

        let bmr = CalorieEngine.bmr(
            weightKg: 80,
            heightCm: 170,
            age: 30,
            isMale: false,
            bodyFatPercent: nil
        )
        let expenditure = bmr * 1.1 + 300
        XCTAssertEqual(
            result.points[0].estimatedExpenditureKcal!,
            expenditure,
            accuracy: 0.001
        )
        XCTAssertEqual(
            result.points[0].energyBalanceKcal!,
            expenditure - 1_800,
            accuracy: 0.001
        )
        XCTAssertLessThan(result.points[5].energyBalanceKcal!, 0)

        let expected = foods.prefix(6).reduce(0.0) {
            $0 + expenditure - $1.calories
        }
        let summary = result.weeklySummary(
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertEqual(
            summary.cumulativeEnergyBalanceKcal!,
            expected,
            accuracy: 0.001
        )
        XCTAssertEqual(summary.eligibleDayCount, 6)
    }

    func testAgeUsesFullBirthdayInsteadOfOnlyCalendarYear() {
        let beforeBirthday = date(2026, 7, 25)
        let onBirthday = date(2026, 7, 26)
        let birthday = DateComponents(year: 1996, month: 7, day: 26)

        XCTAssertEqual(
            HealthKitManager.calculatedAgeYears(
                dateOfBirth: birthday,
                now: beforeBirthday,
                calendar: calendar
            ),
            29
        )
        XCTAssertEqual(
            HealthKitManager.calculatedAgeYears(
                dateOfBirth: birthday,
                now: onBirthday,
                calendar: calendar
            ),
            30
        )
    }

    func testSavingWeightThrowsWhenHealthDataIsUnavailable() async {
        let health = HealthKitManager(healthDataAvailable: { false })

        do {
            try await health.saveWeight(
                kg: 80,
                bodyFatPercent: 24,
                date: date(2026, 7, 26)
            )
            XCTFail("不可用设备不应把体重写入当作成功")
        } catch let error as HealthKitManagerError {
            XCTAssertEqual(
                error.localizedDescription,
                HealthKitManagerError.healthDataUnavailable.localizedDescription
            )
        } catch {
            XCTFail("返回了错误类型：\(error)")
        }
    }

    func testFactorModeIgnoresHealthAndManualExercise() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 22)
        let exercise = HistoricalTrendExercise(
            interval: ExerciseEnergyInterval(
                startDate: date(2026, 7, 20, hour: 18),
                endDate: date(2026, 7, 20, hour: 19),
                estimatedActiveEnergyKcal: 500
            )
        )
        let result = calculate(
            start: start,
            reference: reference,
            foods: [food(on: 0, from: start, calories: 2_000)],
            exercises: [exercise],
            configuration: config(
                activityFactor: 1.375,
                includeActiveEnergy: false,
                calibratedBodyFatMeasuredAt: start
            ),
            healthData: HistoricalTrendHealthData(
                dailyActiveEnergy: [
                    DailyActiveEnergyReading(dayStart: start, kcal: 900),
                ],
                activeEnergyIntervals: [],
                weightPoints: [],
                bodyFatPoints: [],
                manualOverlapDataAvailable: false
            )
        )
        let bmr = CalorieEngine.bmr(
            weightKg: 80,
            heightCm: 170,
            age: 30,
            isMale: false,
            bodyFatPercent: 24
        )

        XCTAssertEqual(
            result.points[0].estimatedExpenditureKcal!,
            bmr * 1.375,
            accuracy: 0.001
        )
        XCTAssertEqual(result.points[0].manualSupplementKcal, 0)
    }

    func testMissingFoodOrWatchActivityNeverBecomesZero() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 23)
        let result = calculate(
            start: start,
            reference: reference,
            foods: [food(on: 1, from: start, calories: 2_000)],
            configuration: config(includeActiveEnergy: true),
            healthData: HistoricalTrendHealthData(
                dailyActiveEnergy: [
                    DailyActiveEnergyReading(dayStart: start, kcal: 400),
                ],
                activeEnergyIntervals: [],
                weightPoints: [],
                bodyFatPoints: [],
                manualOverlapDataAvailable: true
            )
        )

        XCTAssertNil(result.points[0].intakeKcal)
        XCTAssertNotNil(result.points[0].estimatedExpenditureKcal)
        XCTAssertNil(result.points[0].energyBalanceKcal)
        XCTAssertEqual(result.points[1].intakeKcal, 2_000)
        XCTAssertNil(result.points[1].healthActiveEnergyKcal)
        XCTAssertNil(result.points[1].estimatedExpenditureKcal)
        XCTAssertNil(result.points[1].energyBalanceKcal)

        let summary = result.weeklySummary(
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertNil(summary.cumulativeEnergyBalanceKcal)
        XCTAssertEqual(summary.eligibleDayCount, 0)
    }

    func testTodayIsExcludedFromBalanceAndWeeklySummary() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 21, hour: 12)
        let result = HistoricalTrendEngine.calculate(
            from: start,
            to: date(2026, 7, 22),
            referenceDate: reference,
            calendar: calendar,
            configuration: config(includeActiveEnergy: false),
            foods: [
                food(on: 0, from: start, calories: 2_000),
                food(on: 1, from: start, calories: 500),
            ],
            exercises: [],
            localWeights: [],
            localBodyFat: [],
            healthData: .empty
        )

        XCTAssertNotNil(result.points[0].energyBalanceKcal)
        XCTAssertNil(result.points[1].energyBalanceKcal)
        XCTAssertFalse(result.points[1].isCompleteDay)

        let summary = result.weeklySummary(
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertEqual(summary.completedDayCount, 1)
        XCTAssertEqual(
            summary.cumulativeEnergyBalanceKcal,
            result.points[0].energyBalanceKcal
        )
    }

    func testHistoricalWeightUsesNewestPastSourceAndNeverLeaksFutureData() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 23)
        let healthWeight = [
            HistoricalBodyPoint(date: date(2026, 7, 19), value: 95),
            HistoricalBodyPoint(date: date(2026, 7, 22), value: 70),
        ]
        let localWeight = [
            HistoricalBodyPoint(date: date(2026, 7, 20, hour: 8), value: 80),
            HistoricalBodyPoint(date: date(2026, 7, 21, hour: 8), value: 79),
        ]
        let result = calculate(
            start: start,
            reference: reference,
            foods: [
                food(on: 0, from: start, calories: 2_000),
                food(on: 1, from: start, calories: 2_000),
            ],
            localWeights: localWeight,
            configuration: config(includeActiveEnergy: false),
            healthData: HistoricalTrendHealthData(
                dailyActiveEnergy: [],
                activeEnergyIntervals: [],
                weightPoints: healthWeight,
                bodyFatPoints: [],
                manualOverlapDataAvailable: true
            )
        )

        XCTAssertEqual(result.points[0].weightKg, 80)
        XCTAssertEqual(result.points[0].weightSource, .localRecord)
        XCTAssertEqual(result.points[1].weightKg, 79)
        XCTAssertEqual(result.points[1].weightSource, .localRecord)
        XCTAssertNotEqual(result.points[0].weightKg, 70)
    }

    func testBodyFatUsesHealthThenLocalThenDatedCalibrationWithoutFutureLeak() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 24)
        let result = HistoricalTrendEngine.calculate(
            from: start,
            to: reference,
            referenceDate: reference,
            calendar: calendar,
            configuration: config(
                includeActiveEnergy: false,
                calibratedBodyFatPercent: 24,
                calibratedBodyFatMeasuredAt: date(2026, 7, 21, hour: 12)
            ),
            foods: [],
            exercises: [],
            localWeights: [],
            localBodyFat: [
                HistoricalBodyPoint(
                    date: date(2026, 7, 20, hour: 8),
                    value: 26
                ),
            ],
            healthData: HistoricalTrendHealthData(
                dailyActiveEnergy: [],
                activeEnergyIntervals: [],
                weightPoints: [],
                bodyFatPoints: [
                    HistoricalBodyPoint(
                        date: date(2026, 7, 22, hour: 8),
                        value: 22
                    ),
                ],
                manualOverlapDataAvailable: true
            )
        )

        XCTAssertEqual(result.points[0].bodyFatPercent, 26)
        XCTAssertEqual(result.points[0].bodyFatSource, .localRecord)
        XCTAssertEqual(result.points[1].bodyFatPercent, 26)
        XCTAssertEqual(result.points[1].bodyFatSource, .localRecord)
        XCTAssertEqual(result.points[2].bodyFatPercent, 22)
        XCTAssertEqual(result.points[2].bodyFatSource, .healthKit)

        let calibrationOnly = HistoricalTrendEngine.calculate(
            from: start,
            to: date(2026, 7, 23),
            referenceDate: reference,
            calendar: calendar,
            configuration: config(
                includeActiveEnergy: false,
                calibratedBodyFatPercent: 24,
                calibratedBodyFatMeasuredAt: date(2026, 7, 21, hour: 12)
            ),
            foods: [],
            exercises: [],
            localWeights: [],
            localBodyFat: [],
            healthData: .empty
        )
        XCTAssertNil(calibrationOnly.points[0].bodyFatPercent)
        XCTAssertEqual(calibrationOnly.points[1].bodyFatPercent, 24)
        XCTAssertEqual(
            calibrationOnly.points[1].bodyFatSource,
            .calibratedProfile
        )
    }

    func testUndatedCalibrationDoesNotRewriteCompletedHistoricalDays() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 22, hour: 12)
        let result = HistoricalTrendEngine.calculate(
            from: start,
            to: date(2026, 7, 23),
            referenceDate: reference,
            calendar: calendar,
            configuration: config(
                includeActiveEnergy: false,
                calibratedBodyFatPercent: 24,
                calibratedBodyFatMeasuredAt: nil
            ),
            foods: [],
            exercises: [],
            localWeights: [],
            localBodyFat: [],
            healthData: .empty
        )

        XCTAssertNil(result.points[0].bodyFatPercent)
        XCTAssertNil(result.points[1].bodyFatPercent)
        XCTAssertEqual(result.points[2].bodyFatPercent, 24)
        XCTAssertEqual(result.points[2].bodyFatSource, .calibratedProfile)
    }

    func testManualExerciseIsClippedAcrossMidnightAndHealthOverlapIsDeducted() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 23)
        let exercise = HistoricalTrendExercise(
            interval: ExerciseEnergyInterval(
                startDate: date(2026, 7, 20, hour: 23, minute: 30),
                endDate: date(2026, 7, 21, hour: 0, minute: 30),
                estimatedActiveEnergyKcal: 500
            )
        )
        let sample = HealthActiveEnergyInterval(
            startDate: date(2026, 7, 20, hour: 23, minute: 45),
            endDate: date(2026, 7, 21, hour: 0, minute: 15),
            kcal: 100
        )!
        let result = calculate(
            start: start,
            reference: reference,
            foods: [
                food(on: 0, from: start, calories: 2_000),
                food(on: 1, from: start, calories: 2_000),
            ],
            exercises: [exercise],
            configuration: config(includeActiveEnergy: true),
            healthData: HistoricalTrendHealthData(
                dailyActiveEnergy: [
                    DailyActiveEnergyReading(dayStart: start, kcal: 300),
                    DailyActiveEnergyReading(
                        dayStart: day(1, from: start),
                        kcal: 300
                    ),
                ],
                activeEnergyIntervals: [sample],
                weightPoints: [],
                bodyFatPoints: [],
                manualOverlapDataAvailable: true
            )
        )

        XCTAssertEqual(result.points[0].manualSupplementKcal, 200, accuracy: 0.001)
        XCTAssertEqual(result.points[1].manualSupplementKcal, 200, accuracy: 0.001)
    }

    func testMacroCoverageKeepsKnownValuesAndDoesNotInventMissingValues() {
        let start = date(2026, 7, 20)
        let reference = date(2026, 7, 22)
        let foods = [
            HistoricalTrendFood(
                date: date(2026, 7, 20, hour: 8),
                calories: 600,
                proteinG: 40,
                carbsG: 60,
                fatG: 20
            ),
            HistoricalTrendFood(
                date: date(2026, 7, 20, hour: 12),
                calories: 400,
                proteinG: nil,
                carbsG: nil,
                fatG: nil
            ),
        ]
        let result = calculate(
            start: start,
            reference: reference,
            foods: foods,
            configuration: config(includeActiveEnergy: false)
        )

        XCTAssertEqual(result.points[0].proteinG, 40)
        XCTAssertEqual(result.points[0].carbsG, 60)
        XCTAssertEqual(result.points[0].fatG, 20)
        XCTAssertEqual(result.points[0].completeMacroCoverage!, 0.6, accuracy: 0.001)
        XCTAssertNil(result.points[1].proteinG)
    }

    func testSevenAndThirtyDaySuffixesKeepInclusiveDailyBoundaries() {
        let start = date(2026, 6, 27)
        let reference = date(2026, 7, 27)
        let result = calculate(
            start: start,
            reference: reference,
            foods: [],
            configuration: config(includeActiveEnergy: false)
        )

        XCTAssertEqual(result.points.count, 30)
        XCTAssertEqual(result.suffix(days: 7).points.count, 7)
        XCTAssertEqual(result.points.first?.dayStart, start)
        XCTAssertEqual(
            result.points.last?.dayStart,
            date(2026, 7, 26)
        )
    }

    private func calculate(
        start: Date,
        reference: Date,
        foods: [HistoricalTrendFood],
        exercises: [HistoricalTrendExercise] = [],
        localWeights: [HistoricalBodyPoint] = [],
        localBodyFat: [HistoricalBodyPoint] = [],
        configuration: HistoricalTrendConfiguration,
        healthData: HistoricalTrendHealthData = .empty
    ) -> HistoricalTrendResult {
        HistoricalTrendEngine.calculate(
            from: start,
            to: reference,
            referenceDate: reference,
            calendar: calendar,
            configuration: configuration,
            foods: foods,
            exercises: exercises,
            localWeights: localWeights,
            localBodyFat: localBodyFat,
            healthData: healthData
        )
    }

    private func config(
        activityFactor: Double = 1.2,
        includeActiveEnergy: Bool,
        fallbackWeightKg: Double = 80,
        calibratedBodyFatPercent: Double? = 24,
        calibratedBodyFatMeasuredAt: Date? = nil
    ) -> HistoricalTrendConfiguration {
        HistoricalTrendConfiguration(
            heightCm: 170,
            age: 30,
            isMale: false,
            activityFactor: activityFactor,
            includeActiveEnergy: includeActiveEnergy,
            fallbackWeightKg: fallbackWeightKg,
            calibratedBodyFatPercent: calibratedBodyFatPercent,
            calibratedBodyFatMeasuredAt: calibratedBodyFatMeasuredAt
        )
    }

    private func food(
        on dayOffset: Int,
        from start: Date,
        calories: Double
    ) -> HistoricalTrendFood {
        HistoricalTrendFood(
            date: calendar.date(
                byAdding: .hour,
                value: 12,
                to: day(dayOffset, from: start)
            )!,
            calories: calories,
            proteinG: calories / 20,
            carbsG: calories / 10,
            fatG: calories / 40
        )
    }

    private func day(_ offset: Int, from start: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
