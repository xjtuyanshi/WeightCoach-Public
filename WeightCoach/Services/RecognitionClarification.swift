import Foundation

enum RecognitionClarificationKind: Equatable {
    case oilOrSauce
    case portion
}

struct RecognitionClarification: Equatable {
    let foodID: UUID
    let foodName: String
    let kind: RecognitionClarificationKind

    func prompt(
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> String {
        switch kind {
        case .oilOrSauce:
            let suffix = interfaceLocalized(
                "有额外的烹调油或酱汁吗？",
                locale: locale
            )
            return "\(foodName) \(suffix)"
        case .portion:
            let suffix = interfaceLocalized(
                "的份量更接近哪一个？",
                locale: locale
            )
            return "\(foodName) \(suffix)"
        }
    }
}

struct RecognitionClarificationSession: Equatable {
    private(set) var pending: RecognitionClarification?

    mutating func begin(with foods: [RecognizedFood]) {
        pending = RecognitionClarificationSelector.mostImportant(for: foods)
    }

    mutating func dismiss(foodID: UUID) {
        guard pending?.foodID == foodID else { return }
        pending = nil
    }

    mutating func reset() {
        pending = nil
    }
}

enum RecognitionClarificationSelector {
    /// 一次只问最影响热量的一项：油酱优先，其次才是把握最低的份量。
    /// 不把拍摄角度、LiDAR 或第二张照片当作默认前置条件。
    static func mostImportant(for foods: [RecognizedFood]) -> RecognitionClarification? {
        let candidates = foods.filter { food in
            food.needsConfirmation || (food.confidence ?? 1) < 0.6
        }
        guard !candidates.isEmpty else { return nil }

        if let oilOrSauce = candidates
            .filter(mentionsOilOrSauce)
            .min(by: { confidenceScore($0) < confidenceScore($1) }) {
            return clarification(for: oilOrSauce, kind: .oilOrSauce)
        }

        guard let lowestConfidence = candidates.min(
            by: { confidenceScore($0) < confidenceScore($1) }
        ) else {
            return nil
        }
        return clarification(for: lowestConfidence, kind: .portion)
    }

    private static func clarification(
        for food: RecognizedFood,
        kind: RecognitionClarificationKind
    ) -> RecognitionClarification {
        RecognitionClarification(foodID: food.id, foodName: food.name, kind: kind)
    }

    private static func mentionsOilOrSauce(_ food: RecognizedFood) -> Bool {
        let text = [food.name, food.note ?? "", food.portion]
            .joined(separator: " ")
            .lowercased()
        return [
            "烹调油",
            "食用油",
            "额外油",
            "用油",
            "油量",
            "油和",
            "油或",
            "酱汁",
            "酱料",
            "沙拉酱",
            "烹調油",
            "食用油",
            "額外油",
            "用油",
            "油量",
            "油和",
            "油或",
            "醬汁",
            "醬料",
            "沙拉醬",
            "dressing",
            "sauce",
        ].contains {
            text.contains($0)
        }
    }

    private static func confidenceScore(_ food: RecognizedFood) -> Double {
        food.confidence ?? 0.7
    }
}
