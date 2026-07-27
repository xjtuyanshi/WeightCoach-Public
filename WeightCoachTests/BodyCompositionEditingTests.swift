import XCTest
@testable import WeightCoach

final class BodyCompositionEditingTests: XCTestCase {
    func testRangeOnlyDraftKeepsExactValueAndUnknownDateEmpty() throws {
        let original = BodyCompositionTestFixture.syntheticProfile().dexaLeanSoftTissueKg
        let draft = BodyCompositionMeasurementDraft(
            measurement: original,
            fallbackDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let saved = try draft.validatedMeasurement(unit: original.unit)

        XCTAssertNil(saved.value)
        XCTAssertEqual(saved.lowerBound, 60)
        XCTAssertEqual(saved.upperBound, 61)
        XCTAssertNil(saved.measuredAt)
    }

    func testDraftRejectsInvertedRange() {
        var draft = BodyCompositionMeasurementDraft(
            measurement: .empty(unit: .percent)
        )
        draft.lowerBoundText = "30"
        draft.upperBoundText = "20"

        XCTAssertEqual(
            draft.validationMessage(unit: .percent),
            "范围下限不能大于上限。"
        )
    }

    func testDraftRejectsExactValueOutsideRange() {
        var draft = BodyCompositionMeasurementDraft(
            measurement: .empty(unit: .kilograms)
        )
        draft.valueText = "25"
        draft.lowerBoundText = "20"
        draft.upperBoundText = "24"

        XCTAssertEqual(
            draft.validationMessage(unit: .kilograms),
            "精确值必须落在填写的范围内。"
        )
    }

    func testDraftRejectsInvalidAndImplausibleValues() {
        var draft = BodyCompositionMeasurementDraft(
            measurement: .empty(unit: .percent)
        )
        draft.valueText = "不是数字"
        XCTAssertEqual(
            draft.validationMessage(unit: .percent),
            "精确值必须是有效数字。"
        )

        draft.valueText = "100"
        XCTAssertEqual(
            draft.validationMessage(unit: .percent),
            "精确值超出合理的 % 范围。"
        )
    }

    func testClearingDraftDoesNotInventAValueDateOrSource() throws {
        var draft = BodyCompositionMeasurementDraft(
            measurement: BodyCompositionTestFixture.syntheticProfile().fatMassKg
        )

        draft.clear()
        let saved = try draft.validatedMeasurement(unit: .kilograms)

        XCTAssertNil(saved.value)
        XCTAssertNil(saved.lowerBound)
        XCTAssertNil(saved.upperBound)
        XCTAssertNil(saved.source)
        XCTAssertNil(saved.measuredAt)
        XCTAssertNil(saved.note)
    }

    func testPresentationMakesMissingMetadataAndApproximateTotalExplicit() {
        let profile = BodyCompositionTestFixture.syntheticProfile()

        XCTAssertEqual(
            BodyCompositionPresentation.dateText(profile.calibratedBodyFatPercent),
            "未提供"
        )
        XCTAssertEqual(
            BodyCompositionPresentation.primaryValueText(
                profile.historicalDEXA.totalMassKg,
                approximate: true
            ),
            "约 80 kg"
        )
        XCTAssertEqual(
            BodyCompositionPresentation.rangeText(profile.appendicularLeanMassKg),
            "28–29 kg"
        )
    }

    func testPresentationLocalizesGeneratedMissingCopyButPreservesUserSource() {
        let missing = BodyCompositionMeasurement.empty(unit: .percent)
        var customSource = missing
        customSource.source = "My DEXA Lab"

        XCTAssertEqual(
            BodyCompositionPresentation.primaryValueText(
                missing,
                locale: Locale(identifier: "en")
            ),
            "Exact value not provided"
        )
        XCTAssertEqual(
            BodyCompositionPresentation.sourceText(
                missing,
                locale: Locale(identifier: "zh-Hant")
            ),
            "未提供"
        )
        XCTAssertEqual(
            BodyCompositionPresentation.sourceText(
                customSource,
                locale: Locale(identifier: "zh-Hant")
            ),
            "My DEXA Lab"
        )
    }

    func testDraftValidationMessagesUseRequestedLocale() {
        var invalidNumber = BodyCompositionMeasurementDraft(
            measurement: .empty(unit: .percent)
        )
        invalidNumber.valueText = "not a number"
        XCTAssertEqual(
            invalidNumber.validationMessage(
                unit: .percent,
                locale: Locale(identifier: "en")
            ),
            "Exact Value must be a valid number."
        )

        invalidNumber.valueText = "100"
        XCTAssertEqual(
            invalidNumber.validationMessage(
                unit: .percent,
                locale: Locale(identifier: "zh-Hant")
            ),
            "精確值超出合理的 % 範圍。"
        )
    }

    func testDailyReferenceMayBeClearedButRejectsImplausibleValues() throws {
        XCTAssertNil(try DailyIntakeReferenceDraft(value: nil).validatedValue())

        var draft = DailyIntakeReferenceDraft(value: 2_000)
        draft.valueText = "10000"
        XCTAssertNotNil(draft.validationMessage)

        draft.valueText = "1950"
        XCTAssertEqual(try draft.validatedValue(), 1_950)
    }

    func testDailyReferenceValidationUsesRequestedLocale() {
        var draft = DailyIntakeReferenceDraft(value: nil)
        draft.valueText = "10000"

        XCTAssertEqual(
            draft.validationMessage(locale: Locale(identifier: "en")),
            "The daily reference must be a valid calorie value greater than 0 and less than 10,000."
        )
    }
}
