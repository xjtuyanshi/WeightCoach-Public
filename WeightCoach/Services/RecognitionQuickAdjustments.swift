import Foundation

/// 账单或菜单识别后，由用户明确选择自己实际吃了整单的多少。
/// Bridge 只负责识别整单，绝不会在这里猜测用户的食用比例。
enum RecognitionOrderShare: CaseIterable, Equatable {
    case quarter
    case half
    case threeQuarters
    case all

    var factor: Double {
        switch self {
        case .quarter: 0.25
        case .half: 0.5
        case .threeQuarters: 0.75
        case .all: 1
        }
    }

    var buttonTitle: String {
        localizedButtonTitle(locale: AppLanguage.sharedSelection().locale)
    }

    func localizedButtonTitle(locale: Locale) -> String {
        switch self {
        case .quarter: "¼"
        case .half: "½"
        case .threeQuarters: "¾"
        case .all: interfaceLocalized("全部", locale: locale)
        }
    }

    var accessibilityTitle: String {
        localizedAccessibilityTitle(locale: AppLanguage.sharedSelection().locale)
    }

    func localizedAccessibilityTitle(locale: Locale) -> String {
        switch self {
        case .quarter: interfaceLocalized("四分之一", locale: locale)
        case .half: interfaceLocalized("二分之一", locale: locale)
        case .threeQuarters: interfaceLocalized("四分之三", locale: locale)
        case .all: interfaceLocalized("全部", locale: locale)
        }
    }

    func applying(
        to foods: [RecognizedFood],
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> [RecognizedFood] {
        foods.map { food in
            var adjusted = food
            adjusted.portion = [
                food.portion,
                "\(interfaceLocalized("整单", locale: locale)) "
                    + localizedButtonTitle(locale: locale)
                    + " (\(interfaceLocalized("估算", locale: locale)))",
            ].joined(separator: " · ")
            adjusted.calories = food.calories * factor
            adjusted.protein = food.protein.map { $0 * factor }
            adjusted.carbs = food.carbs.map { $0 * factor }
            adjusted.fat = food.fat.map { $0 * factor }
            adjusted.calorieLowerBound = food.calorieLowerBound.map { $0 * factor }
            adjusted.calorieUpperBound = food.calorieUpperBound.map { $0 * factor }
            adjusted.caffeineMg = food.caffeineMg.map { $0 * factor }
            adjusted.needsConfirmation = true
            adjusted.note = note(
                existing: food.note,
                addition: interfaceLocalized(
                    "整单食用比例：按原识别结果 ×{factor} 估算；请核对实际吃到的菜品与份量。",
                    locale: locale
                )
                .replacingOccurrences(
                    of: "{factor}",
                    with: factorText(locale: locale)
                ),
                locale: locale
            )
            return adjusted
        }
    }

    private func factorText(locale: Locale) -> String {
        factor.formatted(
            .number
                .precision(.fractionLength(0...2))
                .locale(locale)
        )
    }
}

/// 确认页上的快捷份量修正。所有数值都基于原识别结果等比例计算，
/// 不会为原本缺失的营养素补造数值。
enum RecognitionPortionMultiplier: CaseIterable {
    case half
    case original
    case oneAndHalf
    case double

    var factor: Double {
        switch self {
        case .half: 0.5
        case .original: 1
        case .oneAndHalf: 1.5
        case .double: 2
        }
    }

    var buttonTitle: String {
        localizedButtonTitle(locale: AppLanguage.sharedSelection().locale)
    }

    func localizedButtonTitle(locale: Locale) -> String {
        switch self {
        case .half:
            return "½ \(interfaceLocalized("份", locale: locale))"
        case .original:
            return interfaceLocalized("原份", locale: locale)
        case .oneAndHalf:
            return "1½ \(interfaceLocalized("份", locale: locale))"
        case .double:
            return "2 \(interfaceLocalized("份", locale: locale))"
        }
    }

    func applying(
        to food: RecognizedFood,
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> RecognizedFood {
        var adjusted = food
        adjusted.portion = "\(food.portion) · "
            + localizedButtonTitle(locale: locale)
            + " (\(interfaceLocalized("估算", locale: locale)))"
        adjusted.calories = food.calories * factor
        adjusted.protein = food.protein.map { $0 * factor }
        adjusted.carbs = food.carbs.map { $0 * factor }
        adjusted.fat = food.fat.map { $0 * factor }
        adjusted.calorieLowerBound = food.calorieLowerBound.map { $0 * factor }
        adjusted.calorieUpperBound = food.calorieUpperBound.map { $0 * factor }
        adjusted.caffeineMg = food.caffeineMg.map { $0 * factor }
        adjusted.needsConfirmation = true
        adjusted.note = note(
            existing: food.note,
            addition: interfaceLocalized(
                "快捷修正：按原识别结果 ×{factor} 估算；可撤销或手动修改。",
                locale: locale
            )
            .replacingOccurrences(
                of: "{factor}",
                with: factorText(locale: locale)
            ),
            locale: locale
        )
        return adjusted
    }

    private func factorText(locale: Locale) -> String {
        factor.formatted(
            .number
                .precision(.fractionLength(0...1))
                .locale(locale)
        )
    }
}

enum RecognitionQuickAddition {
    case teaspoonOfCookingOil
    case tablespoonOfCookingOil
    case sauceNeedsConfirmation

    var buttonTitle: String {
        localizedButtonTitle(locale: AppLanguage.sharedSelection().locale)
    }

    func localizedButtonTitle(locale: Locale) -> String {
        switch self {
        case .teaspoonOfCookingOil:
            interfaceLocalized("加 1 茶匙油", locale: locale)
        case .tablespoonOfCookingOil:
            interfaceLocalized("加 1 汤匙油", locale: locale)
        case .sauceNeedsConfirmation:
            interfaceLocalized("酱汁另算", locale: locale)
        }
    }

    func makeFood(
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> RecognizedFood {
        switch self {
        case .teaspoonOfCookingOil:
            return estimatedOil(
                portion: interfaceLocalized("1 茶匙（约 5 ml）", locale: locale),
                calories: 40,
                fat: 4.5,
                locale: locale
            )
        case .tablespoonOfCookingOil:
            return estimatedOil(
                portion: interfaceLocalized("1 汤匙（约 15 ml）", locale: locale),
                calories: 120,
                fat: 13.5,
                locale: locale
            )
        case .sauceNeedsConfirmation:
            return RecognizedFood(
                name: interfaceLocalized("酱汁（待确认）", locale: locale),
                portion: interfaceLocalized("请填写实际份量", locale: locale),
                calories: 0,
                needsConfirmation: true,
                note: interfaceLocalized(
                    "未估算酱汁热量；请按包装、食谱或实际用量填写。",
                    locale: locale
                )
            )
        }
    }

    private func estimatedOil(
        portion: String,
        calories: Double,
        fat: Double,
        locale: Locale
    ) -> RecognizedFood {
        RecognizedFood(
            name: interfaceLocalized("烹调油（估算）", locale: locale),
            portion: "\(portion) (\(interfaceLocalized("估算", locale: locale)))",
            calories: calories,
            fat: fat,
            needsConfirmation: true,
            note: interfaceLocalized(
                "快捷估算：按常见食用油计算；请按实际用量编辑，可撤销。",
                locale: locale
            )
        )
    }
}

private func note(
    existing: String?,
    addition: String,
    locale: Locale
) -> String {
    [existing, addition]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: noteSeparator(locale: locale))
}

private func noteSeparator(locale: Locale) -> String {
    locale.identifier.lowercased().hasPrefix("en") ? "; " : "；"
}
