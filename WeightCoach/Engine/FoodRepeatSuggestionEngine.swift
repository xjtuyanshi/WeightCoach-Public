import Foundation

struct FoodRepeatSuggestionSnapshot: Equatable, Sendable {
    let sourceIndex: Int
    let key: String
    let date: Date
}

struct FoodRepeatSuggestion: Equatable, Identifiable, Sendable {
    let key: String
    let sourceIndex: Int
    let distinctDayCount: Int
    let occurrenceCount: Int
    let latestDate: Date
    let isFrequent: Bool

    var id: String { key }
}

struct FoodRepeatSuggestionResult: Equatable, Sendable {
    let frequent: [FoodRepeatSuggestion]
    let recent: [FoodRepeatSuggestion]

    var all: [FoodRepeatSuggestion] {
        frequent + recent
    }

    static let empty = FoodRepeatSuggestionResult(frequent: [], recent: [])
}

/// 从饮食历史实时生成「常吃 + 最近」，不新增持久化字段或迁移。
///
/// - 常吃：最近 30 个日历日内至少在 2 个不同日期出现。
/// - 最近：没有进入常吃的最新一次性食物。
/// - 再记模板：每组永远使用最新一条记录，因此沿用用户上次的份量。
enum FoodRepeatSuggestionEngine {
    static func makeSuggestions(
        snapshots: [FoodRepeatSuggestionSnapshot],
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        lookbackDays: Int = 30,
        frequentLimit: Int = 4,
        totalLimit: Int = 6
    ) -> FoodRepeatSuggestionResult {
        guard lookbackDays > 0, frequentLimit >= 0, totalLimit > 0 else {
            return .empty
        }

        let referenceDay = calendar.startOfDay(for: referenceDate)
        guard
            let earliestDay = calendar.date(
                byAdding: .day,
                value: -(lookbackDays - 1),
                to: referenceDay
            ),
            let tomorrow = calendar.date(
                byAdding: .day,
                value: 1,
                to: referenceDay
            )
        else {
            return .empty
        }

        struct Group {
            var latestSourceIndex: Int
            var latestDate: Date
            var occurrenceCount: Int
            var days: Set<Date>
        }

        var groups: [String: Group] = [:]
        for snapshot in snapshots {
            guard
                !snapshot.key.isEmpty,
                snapshot.date >= earliestDay,
                snapshot.date < tomorrow
            else {
                continue
            }

            let day = calendar.startOfDay(for: snapshot.date)
            if var group = groups[snapshot.key] {
                group.occurrenceCount += 1
                group.days.insert(day)
                if snapshot.date > group.latestDate
                    || (
                        snapshot.date == group.latestDate
                        && snapshot.sourceIndex < group.latestSourceIndex
                    ) {
                    group.latestDate = snapshot.date
                    group.latestSourceIndex = snapshot.sourceIndex
                }
                groups[snapshot.key] = group
            } else {
                groups[snapshot.key] = Group(
                    latestSourceIndex: snapshot.sourceIndex,
                    latestDate: snapshot.date,
                    occurrenceCount: 1,
                    days: [day]
                )
            }
        }

        let rankedGroups = groups.map { key, group in
            FoodRepeatSuggestion(
                key: key,
                sourceIndex: group.latestSourceIndex,
                distinctDayCount: group.days.count,
                occurrenceCount: group.occurrenceCount,
                latestDate: group.latestDate,
                isFrequent: group.days.count >= 2
            )
        }

        let frequent = rankedGroups
            .filter(\.isFrequent)
            .sorted(by: frequentSort)
            .prefix(min(frequentLimit, totalLimit))

        let recentCapacity = max(0, totalLimit - frequent.count)
        let recent = rankedGroups
            .filter { !$0.isFrequent }
            .sorted(by: recentSort)
            .prefix(recentCapacity)

        return FoodRepeatSuggestionResult(
            frequent: Array(frequent),
            recent: Array(recent)
        )
    }

    private static func frequentSort(
        _ lhs: FoodRepeatSuggestion,
        _ rhs: FoodRepeatSuggestion
    ) -> Bool {
        if lhs.distinctDayCount != rhs.distinctDayCount {
            return lhs.distinctDayCount > rhs.distinctDayCount
        }
        if lhs.occurrenceCount != rhs.occurrenceCount {
            return lhs.occurrenceCount > rhs.occurrenceCount
        }
        if lhs.latestDate != rhs.latestDate {
            return lhs.latestDate > rhs.latestDate
        }
        return lhs.key < rhs.key
    }

    private static func recentSort(
        _ lhs: FoodRepeatSuggestion,
        _ rhs: FoodRepeatSuggestion
    ) -> Bool {
        if lhs.latestDate != rhs.latestDate {
            return lhs.latestDate > rhs.latestDate
        }
        return lhs.key < rhs.key
    }
}

enum FoodRepeatIdentity {
    static func key(
        productID: UUID?,
        barcode: String?,
        referenceCatalogID: String?,
        name: String
    ) -> String {
        if let productID {
            return "product:\(productID.uuidString.lowercased())"
        }
        if let barcode {
            let digits = barcode.filter(\.isNumber)
            if !digits.isEmpty {
                return "barcode:\(digits)"
            }
        }
        if let referenceCatalogID, !referenceCatalogID.isEmpty {
            return "reference:\(referenceCatalogID)"
        }
        return "name:\(normalizedName(name))"
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive,
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
