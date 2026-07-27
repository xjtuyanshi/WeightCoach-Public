import Foundation

/// 只汇总用户已经确认或可靠来源给出的咖啡因；缺失值不会被当成 0。
struct TodayCaffeineMetrics: Equatable {
    let knownTotalMg: Double
    let knownEntryCount: Int
    let unknownLikelyCaffeinatedCount: Int

    var hasKnownData: Bool {
        knownEntryCount > 0
    }

    static func calculate(foods: [FoodEntry]) -> TodayCaffeineMetrics {
        var knownTotal = 0.0
        var knownCount = 0
        var unknownLikelyCount = 0

        for food in foods {
            if let caffeine = food.caffeineMg,
               caffeine.isFinite,
               caffeine >= 0 {
                knownTotal += caffeine
                knownCount += 1
            } else if likelyContainsCaffeine(food.name) {
                unknownLikelyCount += 1
            }
        }

        return TodayCaffeineMetrics(
            knownTotalMg: knownTotal,
            knownEntryCount: knownCount,
            unknownLikelyCaffeinatedCount: unknownLikelyCount
        )
    }

    static func likelyContainsCaffeine(_ name: String) -> Bool {
        let normalized = name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "zh_Hans")
            )
            .lowercased()
        return caffeineKeywords.contains { normalized.contains($0) }
    }

    private static let caffeineKeywords = [
        "咖啡", "星巴克", "拿铁", "浓缩", "冰摇", "冷萃", "美式", "摩卡",
        "coffee", "starbucks", "latte", "espresso", "cold brew", "americano",
        "抹茶", "matcha", "能量饮料", "energy drink",
    ]
}
