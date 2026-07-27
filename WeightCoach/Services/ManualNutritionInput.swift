import Foundation

/// 手动营养输入的统一解析规则：空白代表未知，明确的 0 代表零。
enum ManualNutritionInput {
    static func nonnegativeNumber(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized),
              value.isFinite,
              value >= 0 else {
            return nil
        }
        return value
    }

    static func optionalNonnegativeNumber(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : nonnegativeNumber(from: trimmed)
    }

    static func isValidOptionalNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || nonnegativeNumber(from: trimmed) != nil
    }
}
