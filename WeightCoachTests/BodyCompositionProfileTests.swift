import XCTest
@testable import WeightCoach

final class BodyCompositionProfileTests: XCTestCase {
    func testSyntheticFixtureKeepsMeasurementDefinitionsSeparate() throws {
        let profile = BodyCompositionTestFixture.syntheticProfile()

        XCTAssertEqual(profile.calibratedBodyFatPercent.value, 20)
        XCTAssertEqual(profile.calibratedBodyFatPercent.lowerBound, 19)
        XCTAssertEqual(profile.calibratedBodyFatPercent.upperBound, 21)
        XCTAssertEqual(profile.fatMassKg.value, 16)
        XCTAssertEqual(profile.fatFreeMassKg.value, 64)
        XCTAssertEqual(profile.fitdaysMuscleMassKg.value, 58)
        XCTAssertEqual(profile.skeletalMuscleMassKg.value, 34)
        XCTAssertEqual(profile.smiKgPerSquareMeter.value, 8)
        XCTAssertEqual(profile.historicalDEXA.bodyFatPercent.value, 22)
        XCTAssertEqual(profile.historicalDEXA.fatMassKg.value, 17.6)
        XCTAssertEqual(profile.historicalDEXA.leanSoftTissueKg.value, 59.4)
        XCTAssertEqual(profile.historicalDEXA.totalMassKg.value, 80)
        XCTAssertEqual(profile.referenceDailyIntakeKcal, 2_100)

        XCTAssertNotEqual(
            profile.fatFreeMassKg.note,
            profile.dexaLeanSoftTissueKg.note
        )
        XCTAssertNotEqual(
            profile.fitdaysMuscleMassKg.note,
            profile.skeletalMuscleMassKg.note
        )
        XCTAssertNil(profile.calibratedBodyFatPercent.measuredAt)
        XCTAssertNil(profile.historicalDEXA.bodyFatPercent.measuredAt)
    }

    func testRangeOnlyMeasurementsDoNotInventMidpoints() {
        let profile = BodyCompositionTestFixture.syntheticProfile()

        XCTAssertNil(profile.dexaLeanSoftTissueKg.value)
        XCTAssertEqual(profile.dexaLeanSoftTissueKg.lowerBound, 60)
        XCTAssertEqual(profile.dexaLeanSoftTissueKg.upperBound, 61)
        XCTAssertNil(profile.appendicularLeanMassKg.value)
        XCTAssertEqual(profile.appendicularLeanMassKg.lowerBound, 28)
        XCTAssertEqual(profile.appendicularLeanMassKg.upperBound, 29)
    }

    func testCodableRoundTripPreservesNilDatesRangesAndSources() throws {
        var original = BodyCompositionTestFixture.syntheticProfile()
        original.appendicularLeanMassKg.source = "真机复测"
        original.appendicularLeanMassKg.value = nil
        original.referenceDailyIntakeKcal = nil

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BodyCompositionProfile.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
