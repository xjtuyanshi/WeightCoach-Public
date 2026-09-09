import XCTest
@testable import WeightCoach

final class ExerciseEnergyEngineTests: XCTestCase {
    func testCompendiumPresetsMatchExpectedCodesAndMETValues() {
        let expected: [(ExerciseIntensity, ExerciseActivityType, Double, String)] = [
            (.basketballShooting, .basketball, 5.0, "15070"),
            (.basketballGeneral, .basketball, 6.0, "15050"),
            (.basketballGame, .basketball, 8.0, "15040"),
            (.runningSlow, .running, 6.5, "12028"),
            (.runningModerate, .running, 8.5, "12030"),
            (.runningFast, .running, 11.0, "12070"),
            (.walkingSlow, .walking, 2.8, "17152"),
            (.walkingModerate, .walking, 3.8, "17190"),
            (.walkingBrisk, .walking, 4.8, "17200"),
            (.strengthGeneral, .strengthTraining, 3.5, "02054"),
            (.strengthCompound, .strengthTraining, 5.0, "02052"),
            (.strengthVigorous, .strengthTraining, 6.0, "02050"),
        ]

        for (intensity, activity, met, code) in expected {
            XCTAssertEqual(intensity.activityType, activity)
            XCTAssertEqual(intensity.metValue, met)
            XCTAssertEqual(intensity.compendiumCode, code)
        }
    }

    func testEveryActivityHasThreePresetsAndStableDefault() {
        let expectedDefaults: [ExerciseActivityType: ExerciseIntensity] = [
            .basketball: .basketballGeneral,
            .running: .runningModerate,
            .walking: .walkingModerate,
            .strengthTraining: .strengthGeneral,
        ]

        XCTAssertEqual(ExerciseActivityType.walking.rawValue, "walking")
        XCTAssertEqual(
            ExerciseActivityType.strengthTraining.rawValue,
            "strengthTraining"
        )

        for activity in ExerciseActivityType.allCases {
            let presets = ExerciseIntensity.presets(for: activity)
            XCTAssertEqual(presets.count, 3, activity.rawValue)
            XCTAssertTrue(presets.allSatisfy { $0.activityType == activity })
            XCTAssertEqual(
                ExerciseIntensity.defaultIntensity(for: activity),
                expectedDefaults[activity]
            )
        }
    }

    func testNetActiveEnergySubtractsOneRestingMET() throws {
        let basketball = try XCTUnwrap(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                intensity: .basketballGeneral,
                weightKg: 80,
                durationMinutes: 60
            )
        )
        let running = try XCTUnwrap(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                intensity: .runningModerate,
                weightKg: 80,
                durationMinutes: 60
            )
        )

        XCTAssertEqual(basketball, 420, accuracy: 0.001)
        XCTAssertEqual(running, 630, accuracy: 0.001)
    }

    func testWalkingAndStrengthUseNetActiveEnergy() throws {
        let walking = try XCTUnwrap(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                intensity: .walkingModerate,
                weightKg: 80,
                durationMinutes: 60
            )
        )
        let strength = try XCTUnwrap(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                intensity: .strengthGeneral,
                weightKg: 80,
                durationMinutes: 60
            )
        )

        XCTAssertEqual(walking, 235.2, accuracy: 0.001)
        XCTAssertEqual(strength, 210, accuracy: 0.001)
    }

    func testMissingActiveEnergyGuidanceNeverConvertsStepsSilently() {
        XCTAssertTrue(
            HealthActivityGuidance.shouldOfferManualWalking(
                steps: 9_500,
                includeActiveEnergy: true
            )
        )
        XCTAssertTrue(
            HealthActivityGuidance.shouldSuggestManualWalking(
                steps: 9_500,
                hasActiveEnergySamples: false,
                includeActiveEnergy: true
            )
        )
        XCTAssertFalse(
            HealthActivityGuidance.shouldSuggestManualWalking(
                steps: 9_500,
                hasActiveEnergySamples: true,
                includeActiveEnergy: true
            )
        )
        XCTAssertFalse(
            HealthActivityGuidance.shouldSuggestManualWalking(
                steps: 9_500,
                hasActiveEnergySamples: false,
                includeActiveEnergy: false
            )
        )
        XCTAssertFalse(
            HealthActivityGuidance.shouldOfferManualWalking(
                steps: 999,
                includeActiveEnergy: true
            )
        )
    }

    func testOneMETProducesZeroActiveEnergy() throws {
        let result = try XCTUnwrap(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                met: 1,
                weightKg: 80,
                durationMinutes: 60
            )
        )

        XCTAssertEqual(result, 0)
    }

    func testValidRangesAreInclusive() {
        XCTAssertNotNil(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                met: 1,
                weightKg: 20,
                durationMinutes: 1
            )
        )
        XCTAssertNotNil(
            ExerciseEnergyEngine.estimateActiveEnergyKcal(
                met: 25,
                weightKg: 350,
                durationMinutes: 600
            )
        )
    }

    func testRejectsOutOfRangeAndNonFiniteInputs() {
        let invalidInputs: [(Double, Double, Double)] = [
            (0.99, 80, 60),
            (25.01, 80, 60),
            (6, 19.99, 60),
            (6, 350.01, 60),
            (6, 80, 0.99),
            (6, 80, 600.01),
            (.nan, 80, 60),
            (6, .infinity, 60),
            (6, 80, -.infinity),
        ]

        for (met, weight, duration) in invalidInputs {
            XCTAssertNil(
                ExerciseEnergyEngine.estimateActiveEnergyKcal(
                    met: met,
                    weightKg: weight,
                    durationMinutes: duration
                )
            )
        }
    }

    func testExerciseEntryKeepsCalculationSnapshots() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let entry = try XCTUnwrap(
            ExerciseEntry.estimated(
                startDate: start,
                durationMinutes: 60,
                intensity: .basketballGeneral,
                weightKg: 80
            )
        )

        XCTAssertEqual(entry.activityType, .basketball)
        XCTAssertEqual(entry.intensity, .basketballGeneral)
        XCTAssertEqual(entry.name, "篮球 · 一般强度")
        XCTAssertEqual(entry.compendiumCode, "15050")
        XCTAssertEqual(entry.metSnapshot, 6)
        XCTAssertEqual(entry.weightKgSnapshot, 80)
        XCTAssertEqual(entry.estimatedActiveEnergyKcal, 420, accuracy: 0.001)
        XCTAssertEqual(entry.calculationVersion, 1)
        XCTAssertEqual(entry.endDate, start.addingTimeInterval(3_600))
    }

    func testGeneratedExerciseNameFollowsInterfaceLocale() throws {
        let entry = try XCTUnwrap(
            ExerciseEntry.estimated(
                durationMinutes: 60,
                intensity: .basketballGeneral,
                weightKg: 80
            )
        )

        XCTAssertEqual(
            entry.displayName(locale: Locale(identifier: "en")),
            "Basketball · General Intensity"
        )
        XCTAssertEqual(
            entry.displayName(locale: Locale(identifier: "zh-Hant")),
            "籃球 · 一般強度"
        )

        let walking = try XCTUnwrap(
            ExerciseEntry.estimated(
                durationMinutes: 60,
                intensity: .walkingModerate,
                weightKg: 80
            )
        )
        XCTAssertEqual(
            walking.displayName(locale: Locale(identifier: "en")),
            "Walking · Moderate Walk"
        )
        XCTAssertEqual(
            walking.displayName(locale: Locale(identifier: "zh-Hant")),
            "走路 · 一般步行"
        )
    }

    func testCustomExerciseNameIsNeverTranslated() throws {
        let entry = try XCTUnwrap(
            ExerciseEntry.estimated(
                durationMinutes: 60,
                intensity: .runningModerate,
                weightKg: 80,
                name: "Saturday run with Alex"
            )
        )

        XCTAssertEqual(
            entry.displayName(locale: Locale(identifier: "zh-Hant")),
            "Saturday run with Alex"
        )
    }

    func testExerciseEntryFactoryRejectsInvalidSnapshots() {
        let entry = ExerciseEntry.estimated(
            startDate: .now,
            durationMinutes: 0,
            intensity: .basketballGeneral,
            weightKg: 80
        )

        XCTAssertNil(entry)
    }
}
