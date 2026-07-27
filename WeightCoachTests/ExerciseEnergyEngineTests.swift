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
        ]

        for (intensity, activity, met, code) in expected {
            XCTAssertEqual(intensity.activityType, activity)
            XCTAssertEqual(intensity.metValue, met)
            XCTAssertEqual(intensity.compendiumCode, code)
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
