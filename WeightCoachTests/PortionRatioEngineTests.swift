import XCTest
@testable import WeightCoach

final class PortionRatioEngineTests: XCTestCase {
    func testParsesDecimalAndCommonFractionForms() throws {
        XCTAssertEqual(try PortionRatioEngine.parse("0.75"), 0.75)
        XCTAssertEqual(try PortionRatioEngine.parse("1.3"), 1.3)
        XCTAssertEqual(try PortionRatioEngine.parse("3/4"), 0.75)
        XCTAssertEqual(try PortionRatioEngine.parse("¾"), 0.75)
        XCTAssertEqual(try PortionRatioEngine.parse("1 1/2"), 1.5)
        XCTAssertEqual(try PortionRatioEngine.parse("1½"), 1.5)
    }

    func testParsesFullWidthSlashDigitsAndFlexibleWhitespace() throws {
        XCTAssertEqual(try PortionRatioEngine.parse("  3 ／ 4  "), 0.75)
        XCTAssertEqual(try PortionRatioEngine.parse("３／４"), 0.75)
        XCTAssertEqual(try PortionRatioEngine.parse("\n 1   1 / 2 \t"), 1.5)
        XCTAssertEqual(try PortionRatioEngine.parse("０．７５"), 0.75)
    }

    func testAcceptsDecimalCommaForSelectedLocales() throws {
        XCTAssertEqual(try PortionRatioEngine.parse("0,75"), 0.75)
        XCTAssertEqual(try PortionRatioEngine.parse("０，７５"), 0.75)
    }

    func testRejectsBlankZeroAndNegativeValuesWithSpecificErrors() {
        assertError(.empty, for: "  \n ")
        assertError(.mustBePositive, for: "0")
        assertError(.mustBePositive, for: "0/4")
        assertError(.negative, for: "-0.5")
        assertError(.negative, for: "1 -1/2")
        assertError(.negative, for: "−¾")
    }

    func testRejectsDivisionByZeroAndMalformedFractions() {
        assertError(.divisionByZero, for: "1/0")
        assertError(.divisionByZero, for: "1 1／0")

        for value in ["/2", "1/", "1/2/3", "one half", "1.5/2", "1 ½ ¾"] {
            assertError(.invalidFormat, for: value)
        }
    }

    func testRejectsNonFiniteAndValuesAboveSuggestedMaximum() {
        for value in ["nan", "NaN", "inf", "-inf", "1e309"] {
            let expected: PortionRatioValidationError = value == "-inf"
                ? .negative
                : .notFinite
            assertError(expected, for: value)
        }

        XCTAssertEqual(try PortionRatioEngine.parse("10"), 10)
        assertError(
            .exceedsMaximum(maximum: PortionRatioEngine.suggestedMaximum),
            for: "10.01"
        )
        assertError(.exceedsMaximum(maximum: 2), for: "3", maximum: 2)
    }

    func testFormatsCommonFractionsForDisplayAndDecimalsForEditing() {
        let locale = Locale(identifier: "en_US_POSIX")

        XCTAssertEqual(
            PortionRatioEngine.formattedForDisplay(0.75, locale: locale),
            "¾"
        )
        XCTAssertEqual(
            PortionRatioEngine.formattedForDisplay(1.5, locale: locale),
            "1½"
        )
        XCTAssertEqual(
            PortionRatioEngine.formattedForDisplay(1.3, locale: locale),
            "1.3"
        )
        XCTAssertEqual(
            PortionRatioEngine.formattedForEditing(0.75, locale: locale),
            "0.75"
        )
        XCTAssertEqual(
            PortionRatioEngine.formattedForEditing(1.3, locale: locale),
            "1.3"
        )
    }

    func testFormattingRejectsNonFiniteValues() {
        XCTAssertEqual(PortionRatioEngine.formattedForDisplay(.nan), "")
        XCTAssertEqual(PortionRatioEngine.formattedForEditing(.infinity), "")
    }

    private func assertError(
        _ expected: PortionRatioValidationError,
        for text: String,
        maximum: Double = PortionRatioEngine.suggestedMaximum,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PortionRatioEngine.parse(text, maximum: maximum),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PortionRatioValidationError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
