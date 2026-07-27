import XCTest
@testable import WeightCoach

final class TodayBudgetMetricsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TodayBudgetMetricsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testHealthKitBodyFatWinsOverLocalAndCalibration() {
        let profile = ProfileStore(defaults: defaults)
        let health = HealthKitManager()
        health.latestBodyFatPercent = 20
        let local = WeightEntry(weightKg: 80, bodyFatPercent: 22)

        let result = BodyFatResolver.resolve(
            healthKitPercent: health.latestBodyFatPercent,
            localWeights: [local],
            calibratedMeasurement: profile.bodyComposition.calibratedBodyFatPercent
        )

        XCTAssertEqual(result, ResolvedBodyFat(percent: 20, source: .healthKit))
    }

    func testLatestValidLocalBodyFatWinsWhenHealthKitIsMissingOrInvalid() {
        let profile = ProfileStore(defaults: defaults)
        let older = WeightEntry(
            date: Date(timeIntervalSince1970: 100),
            weightKg: 81,
            bodyFatPercent: 25
        )
        let newer = WeightEntry(
            date: Date(timeIntervalSince1970: 200),
            weightKg: 80,
            bodyFatPercent: 23
        )
        let invalidNewest = WeightEntry(
            date: Date(timeIntervalSince1970: 300),
            weightKg: 79,
            bodyFatPercent: 99
        )

        let result = BodyFatResolver.resolve(
            healthKitPercent: 0,
            localWeights: [older, invalidNewest, newer],
            calibratedMeasurement: profile.bodyComposition.calibratedBodyFatPercent
        )

        XCTAssertEqual(result, ResolvedBodyFat(percent: 23, source: .localRecord))
    }

    func testCalibrationIsUsedOnlyWhenHealthKitAndLocalBodyFatAreMissing() {
        let profile = ProfileStore(defaults: defaults)
        profile.bodyComposition = BodyCompositionTestFixture.syntheticProfile()

        let result = BodyFatResolver.resolve(
            healthKitPercent: nil,
            localWeights: [WeightEntry(weightKg: 80)],
            calibratedMeasurement: profile.bodyComposition.calibratedBodyFatPercent
        )

        XCTAssertEqual(
            result,
            ResolvedBodyFat(percent: 20, source: .calibratedProfile)
        )
    }

    func testMetricsUseCalibratedBodyFatForKatchMcArdleBMR() {
        let profile = ProfileStore(defaults: defaults)
        profile.bodyComposition = BodyCompositionTestFixture.syntheticProfile()
        let health = HealthKitManager()
        health.latestWeightKg = 80
        health.latestWeightDate = .now

        let metrics = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: []
        )
        let expected = CalorieEngine.bmr(
            weightKg: 80,
            heightCm: profile.heightCm,
            age: profile.age,
            isMale: profile.isMale,
            bodyFatPercent: 20
        )

        XCTAssertEqual(metrics.currentBodyFat, 20)
        XCTAssertEqual(metrics.bodyFatSource, .calibratedProfile)
        XCTAssertEqual(metrics.bmr, expected, accuracy: 0.001)
        XCTAssertEqual(metrics.bmr, 1_752.4, accuracy: 0.001)
    }

    func testHistoricalDEXABodyFatNeverBecomesFallback() {
        var profile = BodyCompositionProfile.empty
        profile.historicalDEXA.bodyFatPercent.value = 22

        let result = BodyFatResolver.resolve(
            healthKitPercent: nil,
            localWeights: [],
            calibratedMeasurement: profile.calibratedBodyFatPercent
        )

        XCTAssertNil(result)
    }

    func testCalibrationWithWrongUnitIsNotTreatedAsBodyFat() {
        var invalidCalibration = BodyCompositionMeasurement.empty(unit: .kilograms)
        invalidCalibration.value = 20

        let result = BodyFatResolver.resolve(
            healthKitPercent: nil,
            localWeights: [],
            calibratedMeasurement: invalidCalibration
        )

        XCTAssertNil(result)
    }

    func testNoBodyFatFallsBackToMifflinStJeor() {
        let profile = ProfileStore(defaults: defaults)
        profile.bodyComposition = .empty
        let health = HealthKitManager()
        health.latestWeightKg = 80
        health.latestWeightDate = .now

        let metrics = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: []
        )
        let expected = CalorieEngine.bmr(
            weightKg: 80,
            heightCm: profile.heightCm,
            age: profile.age,
            isMale: profile.isMale,
            bodyFatPercent: nil
        )

        XCTAssertNil(metrics.currentBodyFat)
        XCTAssertNil(metrics.bodyFatSource)
        XCTAssertEqual(metrics.bmr, expected, accuracy: 0.001)
    }

    func testReferenceCaloriesDoNotChangeBudgetCalculations() {
        let profile = ProfileStore(defaults: defaults)
        let health = HealthKitManager()
        health.latestWeightKg = 80
        health.latestWeightDate = .now
        health.todayActiveEnergyKcal = 450

        profile.bodyComposition.referenceDailyIntakeKcal = 2_000
        let baseline = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: []
        )

        profile.bodyComposition.referenceDailyIntakeKcal = 9_999
        let changed = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: []
        )

        XCTAssertEqual(changed.bmr, baseline.bmr, accuracy: 0.001)
        XCTAssertEqual(changed.tdee, baseline.tdee, accuracy: 0.001)
        XCTAssertEqual(changed.deficit, baseline.deficit, accuracy: 0.001)
        XCTAssertEqual(changed.budget, baseline.budget, accuracy: 0.001)
    }

    func testManualExerciseOnlyAddsEnergyMissingFromAppleHealth() throws {
        let profile = ProfileStore(defaults: defaults)
        profile.includeActiveEnergy = true
        let health = HealthKitManager()
        health.latestWeightKg = 80
        health.latestWeightDate = Date(timeIntervalSince1970: 10_000)
        health.todayActiveEnergyKcal = 450

        let referenceDate = Date(timeIntervalSince1970: 20_000)
        let start = referenceDate.addingTimeInterval(-3_600)
        health.todayActiveEnergyIntervals = [
            try XCTUnwrap(
                HealthActiveEnergyInterval(
                    startDate: start,
                    endDate: start.addingTimeInterval(3_600),
                    kcal: 120
                )
            ),
        ]
        let exercise = try XCTUnwrap(
            ExerciseEntry.estimated(
                startDate: start,
                durationMinutes: 60,
                intensity: .basketballGeneral,
                weightKg: 80
            )
        )

        let metrics = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: [],
            exercises: [exercise],
            referenceDate: referenceDate
        )

        XCTAssertEqual(metrics.manualExerciseEstimatedEnergy, 420, accuracy: 0.001)
        XCTAssertEqual(metrics.manualExerciseHealthOverlap, 120, accuracy: 0.001)
        XCTAssertEqual(metrics.manualExerciseSupplementalEnergy, 300, accuracy: 0.001)
        XCTAssertEqual(metrics.effectiveActiveEnergy, 750, accuracy: 0.001)
        XCTAssertEqual(
            metrics.tdee,
            metrics.bmr * 1.1 + 750,
            accuracy: 0.001
        )
    }

    func testManualExerciseDoesNotAlterActivityFactorMode() throws {
        let profile = ProfileStore(defaults: defaults)
        profile.includeActiveEnergy = false
        profile.activityFactor = 1.375
        let health = HealthKitManager()
        health.latestWeightKg = 80
        health.latestWeightDate = .now
        health.todayActiveEnergyKcal = 450
        let referenceDate = Date(timeIntervalSince1970: 20_000)
        let exercise = try XCTUnwrap(
            ExerciseEntry.estimated(
                startDate: referenceDate.addingTimeInterval(-3_600),
                durationMinutes: 60,
                intensity: .basketballGeneral,
                weightKg: 80
            )
        )

        let metrics = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: [],
            exercises: [exercise],
            referenceDate: referenceDate
        )

        XCTAssertEqual(metrics.manualExerciseSupplementalEnergy, 420, accuracy: 0.001)
        XCTAssertEqual(metrics.tdee, metrics.bmr * 1.375, accuracy: 0.001)
    }

    func testInvalidManualExerciseEnergyIsIgnored() {
        let profile = ProfileStore(defaults: defaults)
        let health = HealthKitManager()
        let invalid = ExerciseEntry(
            startDate: Date().addingTimeInterval(-3_600),
            durationMinutes: 60,
            activityType: .basketball,
            intensity: .basketballGeneral,
            compendiumCode: "invalid",
            metSnapshot: 6,
            weightKgSnapshot: 80,
            estimatedActiveEnergyKcal: .nan
        )

        let metrics = TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: [],
            localWeights: [],
            exercises: [invalid]
        )

        XCTAssertEqual(metrics.manualExerciseEstimatedEnergy, 0)
        XCTAssertEqual(metrics.manualExerciseHealthOverlap, 0)
        XCTAssertEqual(metrics.manualExerciseSupplementalEnergy, 0)
    }
}
