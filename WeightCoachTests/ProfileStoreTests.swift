import XCTest
@testable import WeightCoach

final class ProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ProfileStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNewProfileStartsWithEmptyBodyComposition() throws {
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 25))
        )

        let profile = ProfileStore(defaults: defaults, now: now)

        XCTAssertEqual(profile.heightCm, 170)
        XCTAssertEqual(profile.birthYear, 1996)
        XCTAssertFalse(profile.isMale)
        XCTAssertEqual(profile.goalStartWeight, 80)
        XCTAssertEqual(profile.goalWeight, 75)
        XCTAssertEqual(profile.deficitStrategy, .deadlinePaced)
        XCTAssertEqual(
            defaults.string(forKey: ProfileStore.Keys.deficitStrategy),
            DeficitStrategy.deadlinePaced.rawValue
        )
        XCTAssertEqual(profile.totalDays, 90)
        XCTAssertEqual(profile.bodyComposition, .empty)
        XCTAssertFalse(profile.isOnboardingComplete)
        XCTAssertEqual(defaults.integer(forKey: ProfileStore.Keys.bodyCompositionSeedVersion), 1)
        XCTAssertNotNil(defaults.data(forKey: ProfileStore.Keys.bodyCompositionData))
    }

    func testExistingScalarAndBodyCompositionValuesAreNotOverwritten() throws {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let endDate = Date(timeIntervalSince1970: 1_707_776_000)
        defaults.set(177.5, forKey: ProfileStore.Keys.heightCm)
        defaults.set(1988, forKey: ProfileStore.Keys.birthYear)
        defaults.set(false, forKey: ProfileStore.Keys.isMale)
        defaults.set(startDate, forKey: ProfileStore.Keys.goalStartDate)
        defaults.set(endDate, forKey: ProfileStore.Keys.goalEndDate)
        defaults.set(91.2, forKey: ProfileStore.Keys.goalStartWeight)
        defaults.set(85.5, forKey: ProfileStore.Keys.goalWeight)
        defaults.set(
            DeficitStrategy.deadlinePaced.rawValue,
            forKey: ProfileStore.Keys.deficitStrategy
        )
        defaults.set(1.55, forKey: ProfileStore.Keys.activityFactor)
        defaults.set(false, forKey: ProfileStore.Keys.includeActiveEnergy)
        defaults.set(true, forKey: ProfileStore.Keys.foodReminderEnabled)
        defaults.set(true, forKey: ProfileStore.Keys.weightReminderEnabled)
        var custom = BodyCompositionTestFixture.syntheticProfile()
        custom.calibratedBodyFatPercent.value = 21.8
        custom.calibratedBodyFatPercent.source = "用户已编辑"
        let existingBodyCompositionData = try JSONEncoder().encode(custom)
        defaults.set(existingBodyCompositionData, forKey: ProfileStore.Keys.bodyCompositionData)

        let profile = ProfileStore(defaults: defaults)

        XCTAssertEqual(profile.heightCm, 177.5)
        XCTAssertEqual(profile.birthYear, 1988)
        XCTAssertFalse(profile.isMale)
        XCTAssertEqual(profile.goalStartDate, startDate)
        XCTAssertEqual(profile.goalEndDate, endDate)
        XCTAssertEqual(profile.goalStartWeight, 91.2)
        XCTAssertEqual(profile.goalWeight, 85.5)
        XCTAssertEqual(profile.deficitStrategy, .deadlinePaced)
        XCTAssertEqual(profile.activityFactor, 1.55)
        XCTAssertFalse(profile.includeActiveEnergy)
        XCTAssertTrue(profile.foodReminderEnabled)
        XCTAssertTrue(profile.weightReminderEnabled)
        XCTAssertTrue(profile.isOnboardingComplete)
        XCTAssertEqual(profile.bodyComposition.calibratedBodyFatPercent.value, 21.8)
        XCTAssertEqual(
            profile.bodyComposition.calibratedBodyFatPercent.source,
            "用户已编辑"
        )
        XCTAssertEqual(
            defaults.data(forKey: ProfileStore.Keys.bodyCompositionData),
            existingBodyCompositionData,
            "初始化不得重写已有手机上的身体成分数据"
        )
        XCTAssertEqual(defaults.integer(forKey: ProfileStore.Keys.bodyCompositionSeedVersion), 1)
    }

    func testCompletingOnboardingPersistsAcrossLaunches() {
        let first = ProfileStore(defaults: defaults)
        XCTAssertFalse(first.isOnboardingComplete)

        first.heightCm = 168
        first.goalStartWeight = 72
        first.goalWeight = 65
        first.completeOnboarding()

        let second = ProfileStore(defaults: defaults)

        XCTAssertTrue(second.isOnboardingComplete)
        XCTAssertEqual(second.heightCm, 168)
        XCTAssertEqual(second.goalStartWeight, 72)
        XCTAssertEqual(second.goalWeight, 65)
    }

    func testDeficitStrategyPersistsAcrossLaunches() {
        let first = ProfileStore(defaults: defaults)
        first.deficitStrategy = .rapidFatLoss

        let second = ProfileStore(defaults: defaults)

        XCTAssertEqual(second.deficitStrategy, .rapidFatLoss)
    }

    func testUnknownDeficitStrategyRepairsToDeadlinePaced() {
        defaults.set("unsupported", forKey: ProfileStore.Keys.deficitStrategy)

        let profile = ProfileStore(defaults: defaults)

        XCTAssertEqual(profile.deficitStrategy, .deadlinePaced)
        XCTAssertEqual(
            defaults.string(forKey: ProfileStore.Keys.deficitStrategy),
            DeficitStrategy.deadlinePaced.rawValue
        )
    }

    func testExistingBodyCompositionWithoutMarkerIsNotReseededIfDataIsLaterRemoved() throws {
        var custom = BodyCompositionTestFixture.syntheticProfile()
        custom.calibratedBodyFatPercent.value = 21.8
        defaults.set(
            try JSONEncoder().encode(custom),
            forKey: ProfileStore.Keys.bodyCompositionData
        )

        _ = ProfileStore(defaults: defaults)
        defaults.removeObject(forKey: ProfileStore.Keys.bodyCompositionData)
        let relaunched = ProfileStore(defaults: defaults)

        XCTAssertNil(relaunched.bodyComposition.calibratedBodyFatPercent.value)
    }

    func testClearedFieldIsPersistedAndNotReseededOnNextLaunch() {
        let first = ProfileStore(defaults: defaults)
        first.bodyComposition.calibratedBodyFatPercent.value = nil
        first.bodyComposition.calibratedBodyFatPercent.source = "用户清空"

        let second = ProfileStore(defaults: defaults)

        XCTAssertNil(second.bodyComposition.calibratedBodyFatPercent.value)
        XCTAssertEqual(
            second.bodyComposition.calibratedBodyFatPercent.source,
            "用户清空"
        )
    }

    func testBodyCompositionEditsRoundTripThroughProfileStore() {
        let measuredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ProfileStore(defaults: defaults)
        first.bodyComposition.fatMassKg.value = 21.7
        first.bodyComposition.fatMassKg.lowerBound = 21.0
        first.bodyComposition.fatMassKg.upperBound = 22.4
        first.bodyComposition.fatMassKg.source = "真机复测"
        first.bodyComposition.fatMassKg.measuredAt = measuredAt
        first.bodyComposition.referenceDailyIntakeKcal = 1_950

        let second = ProfileStore(defaults: defaults)

        XCTAssertEqual(second.bodyComposition.fatMassKg.value, 21.7)
        XCTAssertEqual(second.bodyComposition.fatMassKg.lowerBound, 21.0)
        XCTAssertEqual(second.bodyComposition.fatMassKg.upperBound, 22.4)
        XCTAssertEqual(second.bodyComposition.fatMassKg.source, "真机复测")
        XCTAssertEqual(second.bodyComposition.fatMassKg.measuredAt, measuredAt)
        XCTAssertEqual(second.bodyComposition.referenceDailyIntakeKcal, 1_950)
    }

    func testCorruptStoredDataIsNotSilentlyReplacedWithCalibration() {
        defaults.set(Data([0xFF]), forKey: ProfileStore.Keys.bodyCompositionData)

        let profile = ProfileStore(defaults: defaults)

        XCTAssertNil(profile.bodyComposition.calibratedBodyFatPercent.value)
        XCTAssertEqual(defaults.data(forKey: ProfileStore.Keys.bodyCompositionData), Data([0xFF]))
        XCTAssertEqual(defaults.integer(forKey: ProfileStore.Keys.bodyCompositionSeedVersion), 1)
    }

    func testTrainingFuelAdjustmentDefaultsOffAndPersists() {
        let first = ProfileStore(defaults: defaults)

        XCTAssertFalse(first.trainingFuelAdjustmentEnabled)
        XCTAssertEqual(first.macroDayStyle(), .standard)

        first.trainingFuelAdjustmentEnabled = true
        first.setMacroDayStyle(.training)

        let second = ProfileStore(defaults: defaults)

        XCTAssertTrue(second.trainingFuelAdjustmentEnabled)
        XCTAssertEqual(second.macroDayStyle(), .training)
    }

    func testTrainingDaySelectionExpiresOnAnotherDate() {
        let selectedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let nextDay = selectedDate.addingTimeInterval(86_400)
        let profile = ProfileStore(defaults: defaults, now: selectedDate)
        profile.trainingFuelAdjustmentEnabled = true
        profile.setMacroDayStyle(.training, on: selectedDate)

        XCTAssertEqual(profile.macroDayStyle(on: selectedDate), .training)
        XCTAssertEqual(profile.macroDayStyle(on: nextDay), .standard)
    }
}
