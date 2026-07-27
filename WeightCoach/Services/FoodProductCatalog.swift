import Foundation
import SwiftData

enum BarcodeNormalizer {
    /// GTIN-8 / UPC-A / EAN-13 / GTIN-14 统一左补零为 GTIN-14；非标准码不猜。
    static func gtin14(from rawCode: String) -> String? {
        let digits = rawCode.filter { !$0.isWhitespace }
        guard digits.allSatisfy(\.isNumber),
              [8, 12, 13, 14].contains(digits.count) else {
            return nil
        }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }

    static func trimmedRaw(_ rawCode: String) -> String {
        rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
enum FoodProductCatalog {
    static func cachedProduct(
        barcode: String,
        context: ModelContext
    ) throws -> FoodProduct? {
        let raw = BarcodeNormalizer.trimmedRaw(barcode)
        if let canonical = BarcodeNormalizer.gtin14(from: raw) {
            var descriptor = FetchDescriptor<FoodProduct>(
                predicate: #Predicate { $0.gtin14 == canonical }
            )
            descriptor.fetchLimit = 1
            if let match = try context.fetch(descriptor).first {
                return match
            }
        }

        var descriptor = FetchDescriptor<FoodProduct>(
            predicate: #Predicate { $0.barcodeRaw == raw }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    static func upsert(
        scanned product: ScannedProduct,
        context: ModelContext,
        fallbackNutrition: NutritionValues? = nil
    ) throws -> FoodProduct? {
        guard let canonical = product.canonicalNutrition
            ?? fallbackNutrition.map({ (.perServing, $0) }) else {
            return nil
        }

        let stored: FoodProduct
        if let existing = try cachedProduct(barcode: product.barcode, context: context) {
            stored = existing
        } else {
            stored = FoodProduct(
                barcodeRaw: BarcodeNormalizer.trimmedRaw(product.barcode),
                gtin14: BarcodeNormalizer.gtin14(from: product.barcode),
                name: product.name,
                brand: product.brand,
                nutritionBasis: canonical.basis,
                nutrition: canonical.values,
                source: product.source
            )
            context.insert(stored)
        }

        stored.barcodeRaw = BarcodeNormalizer.trimmedRaw(product.barcode)
        stored.gtin14 = BarcodeNormalizer.gtin14(from: product.barcode)
        stored.name = product.name
        stored.brand = product.brand
        stored.nutritionBasis = canonical.basis
        stored.setNutrition(canonical.values)
        stored.servingSizeText = product.servingSizeText
        stored.gramsPerServing = product.servingQuantityG
        stored.millilitersPerServing = product.millilitersPerServing
        stored.unitsPerServing = product.unitsPerServing
        stored.servingsPerPackage = product.servingsPerPackage
        stored.imageURLString = product.imageURL?.absoluteString
        stored.source = product.source
        stored.updatedAt = .now
        return stored
    }

    static func markUsed(
        _ product: FoodProduct,
        amount: Double,
        unit: FoodQuantityUnit,
        at date: Date
    ) {
        product.preferredAmount = amount
        product.preferredUnit = unit
        product.useCount += 1
        product.lastUsedAt = date
        product.updatedAt = .now
    }
}

extension ScannedProduct {
    init(cached product: FoodProduct) {
        self.init(
            barcode: product.barcodeRaw ?? product.gtin14 ?? "",
            name: product.name,
            brand: product.brand,
            nutritionBasis: product.nutritionBasis,
            nutritionValues: product.nutritionValues,
            source: product.source,
            servingSizeText: product.servingSizeText,
            servingQuantityG: product.gramsPerServing,
            millilitersPerServing: product.millilitersPerServing,
            unitsPerServing: product.unitsPerServing,
            servingsPerPackage: product.servingsPerPackage,
            imageURL: product.imageURL,
            cachedProductID: product.id,
            preferredAmount: product.preferredAmount,
            preferredUnit: product.preferredUnit,
            isCached: true
        )
    }
}
