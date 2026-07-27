import Foundation
import WidgetKit

/// App Group 中的版本化轻量快照。Widget 不直接打开主 App 的 SwiftData 数据库。
private struct StoredWidgetBudgetSnapshot: Codable {
    let schemaVersion: Int
    let dayStart: Date
    let updatedAt: Date
    let budgetKcal: Double
    let consumedKcal: Double
}

enum WidgetBudgetPublisher {
    static let appGroupIdentifier = "group.com.lukegogogo.WeightCoach"
    static let storageKey = "widget.todayBudget.snapshot"
    static let widgetKind = "WeightCoachTodayBudget"

    static func publish(metrics: TodayBudgetMetrics, now: Date = .now) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            assertionFailure("无法访问 Widget App Group")
            return
        }

        let calendar = Calendar.current
        let snapshot = StoredWidgetBudgetSnapshot(
            schemaVersion: 1,
            dayStart: calendar.startOfDay(for: now),
            updatedAt: now,
            budgetKcal: metrics.budget,
            consumedKcal: metrics.consumed
        )

        do {
            let encoder = PropertyListEncoder()
            let decoder = PropertyListDecoder()
            if
                let existingData = defaults.data(forKey: storageKey),
                let existing = try? decoder.decode(StoredWidgetBudgetSnapshot.self, from: existingData),
                existing.schemaVersion == snapshot.schemaVersion,
                calendar.isDate(existing.dayStart, inSameDayAs: snapshot.dayStart),
                Int(existing.budgetKcal.rounded()) == Int(snapshot.budgetKcal.rounded()),
                Int(existing.consumedKcal.rounded()) == Int(snapshot.consumedKcal.rounded())
            {
                return
            }

            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: storageKey)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        } catch {
            assertionFailure("写入 Widget 快照失败：\(error)")
        }
    }
}
