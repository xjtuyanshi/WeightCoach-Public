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
        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 0)
        XCTAssertFalse(result.usedHealthWorkoutCoverage)
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

    func testMatchingWorkoutFullyCoveredUsesHealthInsteadOfToppingUpToMET() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: 300
                ),
            ],
            healthWorkouts: [
                workout(from: 10, to: 11, type: .running),
            ]
        )

        XCTAssertEqual(result.estimatedActiveEnergyKcal, 500)
        XCTAssertEqual(result.overlappingHealthEnergyKcal, 300)
        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 60, accuracy: 0.001)
        XCTAssertTrue(result.usedHealthWorkoutCoverage)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 0, accuracy: 0.001)
    }

    func testMatchingWorkoutHalfCoverageOnlySupplementsUncoveredDuration() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(10.5),
                    energyKcal: 100
                ),
            ],
            healthWorkouts: [
                workout(from: 10, to: 10.5, type: .running),
            ]
        )

        XCTAssertEqual(result.overlappingHealthEnergyKcal, 100)
        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 30, accuracy: 0.001)
        XCTAssertTrue(result.usedHealthWorkoutCoverage)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 250, accuracy: 0.001)
    }

    func testOverlappingMatchingWorkoutsUseUnionWithoutDoubleCountingCoverage() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 600,
            activityType: .running
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [],
            healthWorkouts: [
                workout(from: 10, to: 10 + 40.0 / 60, type: .running),
                workout(from: 10 + 20.0 / 60, to: 10 + 50.0 / 60, type: .running),
            ]
        )

        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 50, accuracy: 0.001)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 100, accuracy: 0.001)
    }

    func testDifferentWorkoutTypeFallsBackToOverlappingHealthEnergy() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: 125
                ),
            ],
            healthWorkouts: [
                workout(from: 10, to: 11, type: .walking),
            ]
        )

        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 0)
        XCTAssertFalse(result.usedHealthWorkoutCoverage)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 375)
    }

    func testMatchingWorkoutWithoutActiveEnergyFallsBackToHealthEnergy() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: 125
                ),
            ],
            healthWorkouts: [
                workout(
                    from: 10,
                    to: 11,
                    type: .running,
                    hasActiveEnergy: false
                ),
            ]
        )

        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 0)
        XCTAssertFalse(result.usedHealthWorkoutCoverage)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 375)
    }

    func testDelayedMatchingWorkoutReplacesMETTopUpWithCoverage() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let healthSample = HealthActiveEnergySample(
            startDate: date(10),
            endDate: date(11),
            energyKcal: 300
        )

        let beforeWorkoutSync = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [healthSample]
        )
        let afterWorkoutSync = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [healthSample],
            healthWorkouts: [workout(from: 10, to: 11, type: .running)]
        )

        XCTAssertEqual(beforeWorkoutSync.supplementalActiveEnergyKcal, 200)
        XCTAssertFalse(beforeWorkoutSync.usedHealthWorkoutCoverage)
        XCTAssertEqual(afterWorkoutSync.supplementalActiveEnergyKcal, 0)
        XCTAssertTrue(afterWorkoutSync.usedHealthWorkoutCoverage)
    }

    func testPartialWorkoutDoesNotTopUpEnergyAlreadyCoveringWholeExercise() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [
                HealthActiveEnergySample(
                    startDate: date(10),
                    endDate: date(11),
                    energyKcal: 500
                ),
            ],
            healthWorkouts: [
                workout(from: 10, to: 10.5, type: .running),
            ]
        )

        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 30, accuracy: 0.001)
        XCTAssertEqual(result.overlappingHealthEnergyKcal, 500, accuracy: 0.001)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 0, accuracy: 0.001)
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

    func testMatchingWorkoutCoverageIsClippedAcrossMidnight() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(23.5),
            endDate: date(24.5),
            estimatedActiveEnergyKcal: 500,
            activityType: .running
        )
        let dayTwo = DateInterval(start: date(24), end: date(48))
        let result = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [],
            healthWorkouts: [
                workout(from: 23.75, to: 24.25, type: .running),
            ],
            within: dayTwo
        )

        XCTAssertEqual(result.estimatedActiveEnergyKcal, 250, accuracy: 0.001)
        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 15, accuracy: 0.001)
        XCTAssertTrue(result.usedHealthWorkoutCoverage)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 125, accuracy: 0.001)
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

    func testMovingCandidateOutsideManualEntryClearsOverlap() {
        let existing = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )

        XCTAssertTrue(
            ManualExerciseSupplementEngine.overlaps(
                startDate: date(10.5),
                durationMinutes: 30,
                existingExercises: [existing]
            )
        )
        XCTAssertFalse(
            ManualExerciseSupplementEngine.overlaps(
                startDate: date(11.5),
                durationMinutes: 30,
                existingExercises: [existing]
            )
        )
    }

    func testHealthOverlapIsDeductedButNeverTreatedAsManualDuplicate() {
        let exercise = ExerciseEnergyInterval(
            startDate: date(10),
            endDate: date(11),
            estimatedActiveEnergyKcal: 500
        )
        let healthSample = HealthActiveEnergySample(
            startDate: date(10),
            endDate: date(11),
            energyKcal: 125
        )

        XCTAssertFalse(
            ManualExerciseSupplementEngine.overlaps(
                startDate: exercise.startDate,
                durationMinutes: 60,
                existingExercises: []
            )
        )

        let supplement = ManualExerciseSupplementEngine.calculate(
            exercise: exercise,
            healthSamples: [healthSample]
        )
        XCTAssertEqual(supplement.overlappingHealthEnergyKcal, 125)
        XCTAssertEqual(supplement.supplementalActiveEnergyKcal, 375)
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

    func testCalculateTotalSumsWorkoutCoverageAndReportsWorkoutUse() {
        let exercises = [
            ExerciseEnergyInterval(
                startDate: date(10),
                endDate: date(11),
                estimatedActiveEnergyKcal: 600,
                activityType: .running
            ),
            ExerciseEnergyInterval(
                startDate: date(14),
                endDate: date(14.5),
                estimatedActiveEnergyKcal: 300,
                activityType: .walking
            ),
        ]
        let result = ManualExerciseSupplementEngine.calculateTotal(
            exercises: exercises,
            healthSamples: [],
            healthWorkouts: [
                workout(from: 10, to: 10.5, type: .running),
                workout(from: 14, to: 14.5, type: .walking),
            ]
        )

        XCTAssertEqual(result.healthWorkoutCoveredMinutes, 60, accuracy: 0.001)
        XCTAssertTrue(result.usedHealthWorkoutCoverage)
        XCTAssertEqual(result.supplementalActiveEnergyKcal, 300, accuracy: 0.001)
    }

    private func workout(
        from startHour: Double,
        to endHour: Double,
        type: ExerciseActivityType?,
        hasActiveEnergy: Bool = true
    ) -> HealthWorkoutInterval {
        HealthWorkoutInterval(
            startDate: date(startHour),
            endDate: date(endHour),
            activityType: type,
            hasActiveEnergy: hasActiveEnergy
        )
    }

    private func date(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: hours * hour)
    }
}
