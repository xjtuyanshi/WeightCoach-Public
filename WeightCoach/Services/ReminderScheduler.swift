import Foundation
import SwiftData
import UserNotifications

enum ReminderKind: String, CaseIterable {
    case food
    case weight

    fileprivate var identifierPrefix: String {
        "weightcoach.reminder.\(rawValue)."
    }

    fileprivate var hour: Int {
        switch self {
        case .food: return 20
        case .weight: return 8
        }
    }

    fileprivate var minute: Int {
        switch self {
        case .food: return 30
        case .weight: return 0
        }
    }

}

struct ReminderNotificationCopy: Equatable {
    let title: String
    let body: String

    static func make(
        for kind: ReminderKind,
        language: AppLanguage,
        systemLocale: Locale = .autoupdatingCurrent
    ) -> ReminderNotificationCopy {
        switch language.resolvedLanguage(systemLocale: systemLocale) {
        case .system:
            preconditionFailure("系统语言必须先解析为具体语言")
        case .simplifiedChinese:
            return ReminderNotificationCopy(
                title: "减重助手",
                body: kind == .food ? "今天还没记录饮食" : "早上好，记得称重"
            )
        case .traditionalChinese:
            return ReminderNotificationCopy(
                title: "減重助手",
                body: kind == .food ? "今天還沒記錄飲食" : "早安，記得量體重"
            )
        case .english:
            return ReminderNotificationCopy(
                title: "WeightCoach",
                body: kind == .food
                    ? "You haven't logged any food today"
                    : "Good morning — remember to weigh in"
            )
        }
    }
}

/// 通过滚动安排一次性通知，在已有当天记录时跳过对应提醒。
final class ReminderScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let windowDays = 28
    @MainActor private var scheduleGeneration = 0
    @MainActor private var desiredIdentifiers: Set<String> = []

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    @MainActor
    func cancel(_ kind: ReminderKind, on date: Date) {
        let id = identifier(for: kind, date: date)
        desiredIdentifiers.remove(id)
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    @MainActor
    func removePending(for kind: ReminderKind) async {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        desiredIdentifiers = desiredIdentifiers.filter { !$0.hasPrefix(kind.identifierPrefix) }
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(kind.identifierPrefix) }
        guard generation == scheduleGeneration else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    @MainActor
    func reconcile(
        context: ModelContext,
        profile: ProfileStore,
        latestHealthWeightDate: Date?,
        language: AppLanguage? = nil,
        now: Date = .now
    ) async {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        let enabledKinds = Set(ReminderKind.allCases.filter {
            switch $0 {
            case .food: return profile.foodReminderEnabled
            case .weight: return profile.weightReminderEnabled
            }
        })

        guard !enabledKinds.isEmpty else {
            desiredIdentifiers.removeAll()
            let identifiers = await pendingWeightCoachIdentifiers()
            guard generation == scheduleGeneration else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            return
        }

        let isAuthorized = await authorizationIsGranted()
        guard generation == scheduleGeneration else { return }
        guard isAuthorized else {
            desiredIdentifiers.removeAll()
            let identifiers = await pendingWeightCoachIdentifiers()
            guard generation == scheduleGeneration else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: windowDays, to: start) else { return }

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )

        guard let foods = try? context.fetch(foodDescriptor),
              let weights = try? context.fetch(weightDescriptor) else {
            desiredIdentifiers.removeAll()
            let identifiers = await pendingWeightCoachIdentifiers()
            guard generation == scheduleGeneration else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            return
        }
        let foodDays = Set(foods.map { dayKey(for: $0.date) })
        var weightDays = Set(weights.map { dayKey(for: $0.date) })
        if let latestHealthWeightDate,
           latestHealthWeightDate >= start,
           latestHealthWeightDate < end {
            weightDays.insert(dayKey(for: latestHealthWeightDate))
        }

        var desired: [String: UNNotificationRequest] = [:]
        let notificationLanguage = language ?? AppLanguage.sharedSelection()
        for offset in 0..<windowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for kind in enabledKinds {
                let hasRecord: Bool
                switch kind {
                case .food: hasRecord = foodDays.contains(dayKey(for: day))
                case .weight: hasRecord = weightDays.contains(dayKey(for: day))
                }
                guard !hasRecord,
                      let fireDate = calendar.date(
                        bySettingHour: kind.hour,
                        minute: kind.minute,
                        second: 0,
                        of: day
                      ),
                      fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                let copy = ReminderNotificationCopy.make(
                    for: kind,
                    language: notificationLanguage
                )
                content.title = copy.title
                content.body = copy.body
                content.sound = .default
                content.threadIdentifier = "weightcoach.reminders"

                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                let id = identifier(for: kind, date: day)
                desired[id] = UNNotificationRequest(
                    identifier: id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            }
        }

        let desiredIDs = Set(desired.keys)
        desiredIdentifiers = desiredIDs
        let pending = await center.pendingNotificationRequests()
        guard generation == scheduleGeneration else { return }
        let existingRequests = Dictionary(
            pending
                .filter { isWeightCoachIdentifier($0.identifier) }
                .map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingIDs = Set(existingRequests.keys)
        let changedIDs = desiredIDs.filter { id in
            guard let existing = existingRequests[id], let replacement = desired[id] else {
                return false
            }
            return existing.content.title != replacement.content.title
                || existing.content.body != replacement.content.body
        }
        let identifiersToRemove = existingIDs.subtracting(desiredIDs).union(changedIDs)
        center.removePendingNotificationRequests(
            withIdentifiers: Array(identifiersToRemove)
        )

        let identifiersToAdd = desiredIDs.subtracting(existingIDs).union(changedIDs)
        for id in identifiersToAdd.sorted() {
            guard generation == scheduleGeneration else { return }
            guard desiredIdentifiers.contains(id) else { continue }
            guard let request = desired[id] else { continue }
            try? await center.add(request)
            if !desiredIdentifiers.contains(id) {
                center.removePendingNotificationRequests(withIdentifiers: [id])
            }
            guard generation == scheduleGeneration else { return }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func authorizationIsGranted() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    private func pendingWeightCoachIdentifiers() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(isWeightCoachIdentifier)
    }

    private func isWeightCoachIdentifier(_ identifier: String) -> Bool {
        ReminderKind.allCases.contains { identifier.hasPrefix($0.identifierPrefix) }
    }

    private func identifier(for kind: ReminderKind, date: Date) -> String {
        "\(kind.identifierPrefix)\(dayKey(for: date))"
    }

    private func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
