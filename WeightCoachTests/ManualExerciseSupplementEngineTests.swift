import XCTest
@testable import WeightCoach

final class ManualExerciseSupplementEngineTests: XCTestCase {
    private let hour: TimeInterval = 3_600

    func testNoHealthSamplesUsesFullManualEstimate() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )

        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: []
        )

        XCTAssertEqual(result.estimatedActiveEnergyKcal, 500)
        XCTAssertEqual(result.overlappingHealthEnergyKcal, 0)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 500)
    }

    func testIntervalSampleIsDeductedByOverlapFraction() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )
        let sample = HealthActiveEnergySample(
            startDate: date(9.5),
            endDate: date(10.5),
            energyKcal: 200
        )

        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [sample]
        )

        XCTAssertEqual(result.overlappingHealthEnergyKcal, 100, accuracy: 0.001)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 400, accuracy: 0.001)
    }

    func testPointSampleInsideExerciseIsDeductedInFull() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )

        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(date: date(10.25), energyKcal: 120),
                HealthActiveEnergySample(date: date(11), energyKcal: 90),
            ]
        )

        XCTAssertEqual(result.overlappingHealthEnergyKcal, 120)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 380)
    }

    func testDelayedHealthDataReducesSupplementWithoutGoingNegative() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )
        let initial = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: []
        )
        let refreshed = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: 700
                ),
            ]
        )

        XCTAssertEqual(initial.supplementalActiveEnergyKcal, 500)
        XCTAssertEqual(refreshed.overlappingHealthEnergyKcal, 700)
        XCTAssertEqual(refreshed.supplementalActiveEnergyKcal, 0)
    }

    func testCrossMidnightExerciseIsClippedToQueryDay() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(23.6),
            endDate: date(24.6),
            estimatedActiveEnergyKcal: 500
        )
        let dayTwo = DateInterval(start: date(24), end: date(48))
        let healthSample = HealthActiveEnergySample(
            startDate: date(23.75),
            endDate: date(24.25),
            energyKcal: 100
        )

        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [healthSample],
            within: dayTwo
        )

        XCTAssertEqual(result.estimatedActiveEnergyKcal, 300, accuracy: 0.001)
        XCTAssertEqual(result.overlappingHealthEnergyKcal, 50, accuracy: 0.001)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 250, accuracy: 0.001)
    }

    func testInvalidAndNonFiniteDataIsIgnored() {
        let invalidExercise = ExerciseEnergyInterval(
            startDate: date(11),
            endDate: date(10),
            estimatedActiveEnergyKcal: .infinity
        )
        let invalidResult = ManualExerciseSupplementEngine.calculate(
            exercise: invalidExercise,
            healthSamples: []
        )
        XCTAssertEqual(invalidResult.supplementalActiveEnergyKcal, 0)

        let validExercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: validExercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: .nan
                ),
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: -100
                ),
            ]
        )

        XCTAssertEqual(result.supplementalActiveEnergyKcal, 500)

        let nonFiniteDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let nonFiniteResult = ManualExerciseSupplementEngine.calculate(
            exercise: ExerciseEnergyInterval(
                startDate: date(10),
                endDate: date(11),
                estimatedActiveEnergyKcal: 500
            ),
            healthSamples: [
                HealthActiveEnergySample(date: nonFiniteDate, energyKcal: 200),
            ]
        )
        XCTAssertEqual(nonFiniteResult.supplementalActiveEnergyKcal, 500)
    }

    func testOverlapDetectionTreatsTouchingIntervalsAsNonOverlapping() {
        let existing = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )

        XCTAssertTrue(
            ManualExerciseSupplementEngine.overlaps(
                startDate: date(10.5),
                durationMinutes: 60,
                existingExercises: [existing]
            )
        )
        XCTAssertFalse(
            ManualExerciseSupplementEngine.overlaps(
                startDate: date(11),
                durationMinutes: 30,
                existingExercises: [existing]
            )
        )
    }

    func testCalculateTotalSumsIndependentExerciseSupplements() {
        let exercises = [
            ExerciseEnergyInterval(
                startDate: date(10),
                endDate: date(11),
                estimatedActiveEnergyKcal: 500
            ),
            ExerciseEnergyInterval(
                startDate: date(14),
                endDate: date(14.5),
                estimatedActiveEnergyKcal: 300
            ),
        ]
        let samples = [
            HealthActiveEnergySample(date: date(10.5), energyKcal: 100),
            HealthActiveEnergySample(date: date(14.25), energyKcal: 50),
        ]

        let result = ManualExerciseSupplementEngine.calculateTotal(
            exercises: exercises,
            healthSamples: samples
        )

        XCTAssertEqual(result.estimatedActiveEnergyKcal, 800)
        XCTAssertEqual(result.overlappingHealthEnergyKcal, 150)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 650)
    }

    private func date(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: hours * hour)
    }
}
