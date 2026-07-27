import CoreGraphics
import XCTest
@testable import WeightCoach

final class NutritionLabelParserTests: XCTestCase {
    func testParsesEnglishNutritionFactsAndIgnoresDailyValuePercentages() throws {
        let result = NutritionLabelParser.parse(lines: [
            line("Nutrition Facts"),
            line("8 servings per container"),
            line("Serving size 2/3 cup (55g)"),
            line("Amount per serving"),
            line("Calories 230"),
            line("Total Fat 8g 10%"),
            line("Saturated Fat 1g 5%"),
            line("Trans Fat 0g"),
            line("Cholesterol 0mg 0%"),
            line("Sodium 160mg 7%"),
            line("Total Carbohydrate 37g 13%"),
            line("Dietary Fiber 4g 14%"),
            line("Total Sugars 12g"),
            line("Includes 10g Added Sugars 20%"),
            line("Protein 3g")
        ])

        let column = try XCTUnwrap(result.columns.first)
        XCTAssertEqual(result.columns.count, 1)
        XCTAssertEqual(column.basis, .perServing)
        XCTAssertFalse(column.basisRequiresConfirmation)
        XCTAssertEqual(column.values.energyKcal, 230)
        XCTAssertEqual(column.values.fatG, 8)
        XCTAssertEqual(column.values.saturatedFatG, 1)
        XCTAssertEqual(column.values.transFatG, 0)
        XCTAssertEqual(column.values.sodiumMg, 160)
        XCTAssertEqual(column.values.carbohydratesG, 37)
        XCTAssertEqual(column.values.fiberG, 4)
        XCTAssertEqual(column.values.sugarG, 12)
        XCTAssertEqual(column.values.addedSugarG, 10)
        XCTAssertEqual(column.values.proteinG, 3)
        XCTAssertEqual(result.servingGrams?.amount, 55)
        XCTAssertEqual(result.servingsPerPackage?.amount, 8)
        XCTAssertEqual(result.servingsPerPackage?.qualifier, .exact)
    }

    func testParsesDemoEnglishLabelWithoutMistakingContainerCountForASecondColumn() throws {
        let result = NutritionLabelParser.parse(lines: [
            line("Nutrition Facts"),
            line("About 4 servings per container"),
            line("Serving size 5 pieces (85g)"),
            line("Calories 210"),
            line("Total Fat 9g 12%"),
            line("Saturated Fat 2g 10%"),
            line("Sodium 520mg 23%"),
            line("Total Carbohydrate 18g 7%"),
            line("Dietary Fiber 3g 11%"),
            line("Total Sugars 2g"),
            line("Protein 14g")
        ])

        XCTAssertEqual(result.columns.count, 1)
        let column = try XCTUnwrap(result.columns.first)
        XCTAssertEqual(column.basis, .perServing)
        XCTAssertFalse(column.basisRequiresConfirmation)
        XCTAssertEqual(column.values.energyKcal, 210)
        XCTAssertEqual(column.values.sodiumMg, 520)
        XCTAssertEqual(column.values.fatG, 9)
        XCTAssertEqual(column.values.proteinG, 14)
        XCTAssertEqual(result.servingGrams?.amount, 85)
        XCTAssertEqual(result.unitsPerServing?.amount, 5)
        XCTAssertEqual(result.servingsPerPackage?.amount, 4)
        XCTAssertEqual(result.servingsPerPackage?.qualifier, .approximate)
    }

    func testParsesChinesePer100GramLabelAndConvertsKilojoules() throws {
        let result = NutritionLabelParser.parse(lines: [
            line("营养成分表 每100克 NRV%"),
            line("能量 1680千焦 20%"),
            line("蛋白质 8.0克 13%"),
            line("脂肪 12克 20%"),
            line("碳水化合物 62克 21%"),
            line("钠 360毫克 18%")
        ])

        let column = try XCTUnwrap(result.columns.first)
        XCTAssertEqual(column.basis, .per100Grams)
        XCTAssertEqual(
            try XCTUnwrap(column.values.energyKcal).doubleValue,
            1680 / 4.184,
            accuracy: 0.001
        )
        XCTAssertEqual(column.values.proteinG, 8)
        XCTAssertEqual(column.values.fatG, 12)
        XCTAssertEqual(column.values.carbohydratesG, 62)
        XCTAssertEqual(column.values.sodiumMg, 360)
    }

    func testParsesChineseServingSizeUnitsAndApproximatePackageCount() {
        let result = NutritionLabelParser.parse(lines: [
            line("每份 5块（85克）"),
            line("本包装含约4份"),
            line("热量 210千卡")
        ])

        XCTAssertEqual(result.columns.first?.basis, .perServing)
        XCTAssertEqual(result.servingGrams?.amount, 85)
        XCTAssertEqual(result.unitsPerServing?.amount, 5)
        XCTAssertEqual(result.servingsPerPackage?.amount, 4)
        XCTAssertEqual(result.servingsPerPackage?.qualifier, .approximate)
        XCTAssertTrue(result.servingsPerPackage?.requiresConfirmation == true)
    }

    func testPrefersExplicitKilocaloriesWhenEnergyAlsoContainsKilojoules() {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving"),
            line("Energy 500 kJ / 120 kcal")
        ])

        XCTAssertEqual(result.columns.first?.values.energyKcal, 120)
    }

    func testDoesNotTreatDailyValueAsSodiumAmount() {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving"),
            line("Sodium 520mg 23%")
        ])

        let sodium = result.columns.first?.field(.sodiumMg)
        XCTAssertEqual(sodium?.amount, 520)
        XCTAssertEqual(sodium?.unit, .milligrams)
        XCTAssertFalse(sodium?.requiresConfirmation ?? true)
    }

    func testLowOCRConfidenceRequiresConfirmation() {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving"),
            line("Calories 210", confidence: 0.62)
        ])

        let calories = result.columns.first?.field(.energyKcal)
        XCTAssertEqual(calories?.amount, 210)
        XCTAssertEqual(calories?.confidence, 0.62)
        XCTAssertTrue(calories?.requiresConfirmation == true)
    }

    func testLowOCRConfidenceOnDetectedBasisRequiresConfirmation() throws {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving", confidence: 0.62),
            line("Calories 210")
        ])

        let column = try XCTUnwrap(result.columns.first)
        XCTAssertEqual(column.basis, .perServing)
        XCTAssertEqual(column.basisConfidence, 0.62)
        XCTAssertTrue(column.basisRequiresConfirmation)
        XCTAssertFalse(column.field(.energyKcal)?.requiresConfirmation ?? true)
    }

    func testIgnoresUSGeneralNutritionAdviceCalorieFootnote() throws {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving"),
            line("Protein 3g"),
            line("2,000 calories a day is used for general nutrition advice.")
        ])

        let column = try XCTUnwrap(result.columns.first)
        XCTAssertNil(column.values.energyKcal)
        XCTAssertEqual(column.values.proteinG, 3)
    }

    func testMergesVisionFragmentsOnTheSameVisualRow() throws {
        let result = NutritionLabelParser.parse(lines: [
            positionedLine("Amount per", x: 0.05, y: 0.82, width: 0.28),
            positionedLine("serving", x: 0.37, y: 0.82, width: 0.20),
            positionedLine("Calories", x: 0.05, y: 0.70, width: 0.28),
            positionedLine("210", x: 0.76, y: 0.70, width: 0.12),
            positionedLine("Total Fat", x: 0.05, y: 0.58, width: 0.30),
            positionedLine("9g", x: 0.76, y: 0.58, width: 0.12)
        ])

        let column = try XCTUnwrap(result.columns.first)
        XCTAssertEqual(column.basis, .perServing)
        XCTAssertFalse(column.basisRequiresConfirmation)
        XCTAssertEqual(column.values.energyKcal, 210)
        XCTAssertEqual(column.values.fatG, 9)
    }

    func testRecognizesBasicDualServingAndPackageColumns() throws {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving / per container"),
            line("Calories 210 420"),
            line("Total Fat 9g 18g"),
            line("Protein 14g 28g")
        ])

        XCTAssertEqual(result.columns.map(\.basis), [.perServing, .perPackage])
        let serving = try XCTUnwrap(result.columns.first)
        let package = try XCTUnwrap(result.columns.last)
        XCTAssertEqual(serving.values.energyKcal, 210)
        XCTAssertEqual(package.values.energyKcal, 420)
        XCTAssertEqual(serving.values.fatG, 9)
        XCTAssertEqual(package.values.fatG, 18)
        XCTAssertEqual(serving.values.proteinG, 14)
        XCTAssertEqual(package.values.proteinG, 28)
        XCTAssertTrue(serving.basisRequiresConfirmation)
        XCTAssertTrue(package.basisRequiresConfirmation)
        XCTAssertTrue(serving.field(.energyKcal)?.requiresConfirmation == true)
    }

    func testPreservesLessThanQualifier() {
        let result = NutritionLabelParser.parse(lines: [
            line("Amount per serving"),
            line("Trans Fat <1g")
        ])

        let transFat = result.columns.first?.field(.transFatG)
        XCTAssertEqual(transFat?.amount, 1)
        XCTAssertEqual(transFat?.qualifier, .lessThan)
        XCTAssertTrue(transFat?.requiresConfirmation == true)
    }

    private func line(
        _ text: String,
        confidence: Float = 0.96
    ) -> RecognizedNutritionTextLine {
        RecognizedNutritionTextLine(
            text: text,
            confidence: confidence,
            boundingBox: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.04)
        )
    }

    private func positionedLine(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        confidence: Float = 0.96
    ) -> RecognizedNutritionTextLine {
        RecognizedNutritionTextLine(
            text: text,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: 0.05)
        )
    }
}
