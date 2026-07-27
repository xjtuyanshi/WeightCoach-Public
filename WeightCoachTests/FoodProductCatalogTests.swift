import XCTest
import SwiftData
@testable import WeightCoach

final class BarcodeNormalizerTests: XCTestCase {
    func testNormalizesSupportedBarcodeLengthsWithoutLosingLeadingZeros() {
        XCTAssertEqual(
            BarcodeNormalizer.gtin14(from: "096619365475"),
            "00096619365475"
        )
        XCTAssertEqual(
            BarcodeNormalizer.gtin14(from: "  01234567  "),
            "00000001234567"
        )
        XCTAssertEqual(
            BarcodeNormalizer.gtin14(from: "00123456789012"),
            "00123456789012"
        )
    }

    func testRejectsNonGTINInsteadOfGuessing() {
        XCTAssertNil(BarcodeNormalizer.gtin14(from: "ABC123"))
        XCTAssertNil(BarcodeNormalizer.gtin14(from: "123456"))
        XCTAssertNil(BarcodeNormalizer.gtin14(from: "1234-5678"))
    }
}

final class OpenFoodFactsParsingTests: XCTestCase {
    func testParsesStringServingQuantityAndKeepsOneNutritionBasis() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Protein Bar",
            "brands": "Kirkland Signature",
            "serving_size": "1 bar (60g)",
            "serving_quantity": "60",
            "serving_quantity_unit": "g",
            "servings_per_package": "20",
            "nutriments": {
              "energy-kcal_100g": 316.6667,
              "proteins_100g": "35",
              "carbohydrates_100g": 36.6667,
              "fat_100g": 11.6667,
              "fiber_100g": 16.6667,
              "sugars_100g": 3.3333,
              "sodium_100g": 0.3667,
              "energy-kcal_serving": 190
            }
          }
        }
        """

        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "096619365475"
        )

        XCTAssertEqual(product.servingQuantityG, 60)
        XCTAssertEqual(product.servingsPerPackage, 20)
        XCTAssertEqual(product.nutritionBasis, .per100Grams)
        XCTAssertEqual(product.source, .openFoodFacts)
        XCTAssertEqual(product.canonicalNutrition?.basis, .per100Grams)
        XCTAssertEqual(
            product.nutritionPer100Grams?.sodiumMg?.doubleValue ?? 0,
            366.7,
            accuracy: 0.001
        )
        let serving = try XCTUnwrap(
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: .servings(1)
            )
        )
        XCTAssertEqual(serving.energyKcal?.doubleValue ?? 0, 190, accuracy: 0.01)
        XCTAssertEqual(serving.proteinG?.doubleValue ?? 0, 21, accuracy: 0.01)
    }

    func testConvertsKilojoulesWhenKcalIsMissing() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Soup",
            "product_quantity_unit": "g",
            "nutriments": { "energy_100g": 418.4 }
          }
        }
        """
        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "12345678"
        )
        XCTAssertEqual(product.kcalPer100g ?? 0, 100, accuracy: 0.001)
    }

    func testParsesLiquidPer100MillilitersWithoutTreatingItAsGrams() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Oat Milk",
            "serving_size": "1 cup (240 ml)",
            "serving_quantity": "240",
            "serving_quantity_unit": "ml",
            "product_quantity_unit": "ml",
            "nutriments": {
              "energy-kcal_100g": 50,
              "proteins_100g": 1.5
            }
          }
        }
        """

        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "11111111"
        )

        XCTAssertEqual(product.nutritionBasis, .per100Milliliters)
        XCTAssertEqual(product.millilitersPerServing, 240)
        XCTAssertNil(product.servingQuantityG)
        XCTAssertNil(product.kcalPer100g)
        XCTAssertEqual(product.kcalPer100ml, 50)
        XCTAssertNil(
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: .grams(240)
            )
        )
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: .milliliters(240)
            )?.energyKcal?.doubleValue ?? 0,
            120,
            accuracy: 0.001
        )
    }

    func testParsesLiquidServingQuantityInMillilitersForPerServingNutrition() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Cold Brew",
            "serving_size": "355 ml",
            "serving_quantity": 355,
            "serving_quantity_unit": "ml",
            "nutriments": {
              "energy-kcal_serving": 70,
              "proteins_serving": 2
            }
          }
        }
        """

        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "22222222"
        )

        XCTAssertEqual(product.nutritionBasis, .perServing)
        XCTAssertEqual(product.millilitersPerServing, 355)
        XCTAssertNil(product.servingQuantityG)
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: .milliliters(177.5)
            )?.energyKcal?.doubleValue ?? 0,
            35,
            accuracy: 0.001
        )
    }

    func testParsesSolidServingQuantityInGrams() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Crackers",
            "serving_size": "30 g",
            "serving_quantity": 30,
            "serving_quantity_unit": "g",
            "nutriments": {
              "energy-kcal_100g": 400
            }
          }
        }
        """

        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "33333333"
        )

        XCTAssertEqual(product.nutritionBasis, .per100Grams)
        XCTAssertEqual(product.servingQuantityG, 30)
        XCTAssertNil(product.millilitersPerServing)
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: .servings(1)
            )?.energyKcal?.doubleValue ?? 0,
            120,
            accuracy: 0.001
        )
    }

    func testLegacyServingSizeWithExplicitGramUnitRemainsCompatible() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Legacy Bar",
            "serving_size": "1 bar (60 g)",
            "serving_quantity": "60",
            "nutriments": {
              "energy-kcal_100g": 300
            }
          }
        }
        """

        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "44444444"
        )

        XCTAssertEqual(product.nutritionBasis, .per100Grams)
        XCTAssertEqual(product.servingQuantityG, 60)
        XCTAssertNil(product.millilitersPerServing)
    }

    func testAmbiguousPer100DataDoesNotGuessGramsOrLiquidDensity() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Unknown Product",
            "serving_quantity": "250",
            "nutriments": {
              "energy-kcal_100g": 80
            }
          }
        }
        """

        XCTAssertThrowsError(
            try OpenFoodFactsService.parseProduct(
                data: try XCTUnwrap(json.data(using: .utf8)),
                barcode: "55555555"
            )
        ) { error in
            guard case OpenFoodFactsError.missingNutrition = error else {
                return XCTFail("单位不明时应要求核对，而不是把 ml 当成 g")
            }
        }
    }

    func testConflictingUnitsFallBackToReliablePerServingValues() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Conflicting Product",
            "serving_size": "250 ml",
            "serving_quantity": "250",
            "serving_quantity_unit": "ml",
            "product_quantity_unit": "g",
            "nutriments": {
              "energy-kcal_100g": 80,
              "energy-kcal_serving": 160
            }
          }
        }
        """

        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "66666666"
        )

        XCTAssertEqual(product.nutritionBasis, .perServing)
        XCTAssertEqual(product.nutritionValues.energyKcal, 160)
        XCTAssertNil(product.servingQuantityG)
        XCTAssertNil(product.millilitersPerServing)
    }

    func testUsesServingAsExplicitBasisWhenPer100CaloriesAreMissing() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Single Cup",
            "serving_size": "1 cup",
            "nutriments": {
              "proteins_100g": 4,
              "energy-kcal_serving": 180,
              "proteins_serving": 12
            }
          }
        }
        """
        let product = try OpenFoodFactsService.parseProduct(
            data: try XCTUnwrap(json.data(using: .utf8)),
            barcode: "12345678"
        )

        XCTAssertEqual(product.nutritionBasis, .perServing)
        XCTAssertEqual(product.nutritionValues.energyKcal, 180)
        XCTAssertEqual(product.nutritionValues.proteinG, 12)
        XCTAssertNil(product.nutritionPer100Grams)
        XCTAssertEqual(product.nutritionPerServing, product.nutritionValues)
    }

    func testRejectsMissingProduct() throws {
        let data = try XCTUnwrap(#"{"status":0}"#.data(using: .utf8))
        XCTAssertThrowsError(
            try OpenFoodFactsService.parseProduct(data: data, barcode: "12345678")
        )
    }

    func testRejectsProductWithoutReliableCalories() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "product_name": "Incomplete Product",
            "nutriments": {
              "proteins_100g": 4,
              "fat_100g": 2
            }
          }
        }
        """

        XCTAssertThrowsError(
            try OpenFoodFactsService.parseProduct(
                data: try XCTUnwrap(json.data(using: .utf8)),
                barcode: "12345678"
            )
        ) { error in
            guard case OpenFoodFactsError.missingNutrition = error else {
                return XCTFail("应提示扫描包装营养表，而不是进入不可保存的份量页")
            }
        }
    }
}

@MainActor
final class FoodProductCatalogTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FoodEntry.self,
            WeightEntry.self,
            FoodProduct.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    func testUpsertReusesCanonicalGTINAndPreservesUsageState() throws {
        let context = try makeContext()
        let first = ScannedProduct(
            barcode: "096619365475",
            name: "Protein Bar",
            brand: "Kirkland",
            nutritionBasis: .per100Grams,
            nutritionValues: NutritionValues(energyKcal: 300, proteinG: 30),
            source: .openFoodFacts,
            servingSizeText: "60g",
            servingQuantityG: 60,
            millilitersPerServing: nil,
            unitsPerServing: 1,
            servingsPerPackage: 20,
            imageURL: nil
        )

        let stored = try XCTUnwrap(
            FoodProductCatalog.upsert(scanned: first, context: context)
        )
        FoodProductCatalog.markUsed(stored, amount: 1, unit: .servings, at: .now)
        let originalID = stored.id

        var refreshed = first
        refreshed.barcode = "00096619365475"
        refreshed.name = "Protein Bar Updated"
        let updated = try XCTUnwrap(
            FoodProductCatalog.upsert(scanned: refreshed, context: context)
        )
        try context.save()

        XCTAssertEqual(updated.id, originalID)
        XCTAssertEqual(updated.name, "Protein Bar Updated")
        XCTAssertEqual(updated.useCount, 1)
        XCTAssertEqual(updated.preferredUnit, .servings)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodProduct>()), 1)
    }

    func testUpsertPreservesNutritionLabelBasisAndSource() throws {
        let context = try makeContext()
        let labelProduct = ScannedProduct(
            barcode: "012345678905",
            name: "汤料整包",
            nutritionBasis: .perPackage,
            nutritionValues: NutritionValues(
                energyKcal: 480,
                proteinG: 16,
                sodiumMg: 900
            ),
            source: .nutritionLabel,
            servingSizeText: "每包 4 份",
            servingsPerPackage: 4
        )

        let stored = try XCTUnwrap(
            FoodProductCatalog.upsert(scanned: labelProduct, context: context)
        )
        try context.save()

        XCTAssertEqual(stored.nutritionBasis, .perPackage)
        XCTAssertEqual(stored.source, .nutritionLabel)
        XCTAssertEqual(stored.nutritionValues.energyKcal, 480)
        XCTAssertEqual(stored.servingsPerPackage, 4)
    }

    func testCachedProductRestoresEveryNonLegacyNutritionBasis() throws {
        let milliliterProduct = FoodProduct(
            barcodeRaw: "11111111",
            name: "牛奶",
            nutritionBasis: .per100Milliliters,
            nutrition: NutritionValues(energyKcal: 64),
            millilitersPerServing: 250,
            source: .nutritionLabel
        )
        let packageProduct = FoodProduct(
            barcodeRaw: "22222222",
            name: "家庭装",
            nutritionBasis: .perPackage,
            nutrition: NutritionValues(energyKcal: 600),
            servingsPerPackage: 3,
            source: .manual
        )
        let unitProduct = FoodProduct(
            barcodeRaw: "33333333",
            name: "鸡蛋",
            nutritionBasis: .perUnit,
            nutrition: NutritionValues(energyKcal: 90),
            unitsPerServing: 2,
            source: .demo
        )

        let cachedMilliliters = ScannedProduct(cached: milliliterProduct)
        let cachedPackage = ScannedProduct(cached: packageProduct)
        let cachedUnit = ScannedProduct(cached: unitProduct)

        XCTAssertEqual(cachedMilliliters.nutritionBasis, .per100Milliliters)
        XCTAssertEqual(cachedMilliliters.source, .nutritionLabel)
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: cachedMilliliters.nutritionProfile,
                amount: .milliliters(250)
            )?.energyKcal,
            160
        )

        XCTAssertEqual(cachedPackage.nutritionBasis, .perPackage)
        XCTAssertEqual(cachedPackage.source, .manual)
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: cachedPackage.nutritionProfile,
                amount: .servings(1)
            )?.energyKcal?.doubleValue ?? 0,
            200,
            accuracy: 0.000_001
        )

        XCTAssertEqual(cachedUnit.nutritionBasis, .perUnit)
        XCTAssertEqual(cachedUnit.source, .demo)
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: cachedUnit.nutritionProfile,
                amount: .units(2)
            )?.energyKcal,
            180
        )
    }

    func testFoodProductPersistsAndScalesCaffeine() throws {
        let product = FoodProduct(
            name: "罐装咖啡",
            nutritionBasis: .perServing,
            nutrition: NutritionValues(
                energyKcal: 120,
                caffeineMg: 160
            ),
            source: .manual
        )

        XCTAssertEqual(product.caffeineMg, 160)
        XCTAssertEqual(product.nutritionValues.caffeineMg, 160)
        XCTAssertEqual(
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: .servings(0.5)
            )?.caffeineMg,
            80
        )
    }
}
