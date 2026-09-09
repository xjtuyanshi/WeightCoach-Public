import Foundation
import SwiftUI

/// 决定每日热量预算采用哪一种目标缺口策略；不改变 BMR 或 TDEE 计算。
enum DeficitStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
    case rapidFatLoss
    case deadlinePaced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rapidFatLoss: return "尽快减脂（750 千卡/天）"
        case .deadlinePaced: return "按日期达标（动态）"
        }
    }
}

/// 用户档案与减重目标。持久化到 UserDefaults。
final class ProfileStore: ObservableObject {
    enum Keys {
        static let heightCm = "profile.heightCm"
        static let birthYear = "profile.birthYear"
        static let isMale = "profile.isMale"
        static let goalStartDate = "goal.startDate"
        static let goalEndDate = "goal.endDate"
        static let goalStartWeight = "goal.startWeight"
        static let goalWeight = "goal.weight"
        static let deficitStrategy = "calc.deficitStrategy"
        static let activityFactor = "calc.activityFactor"
        static let includeActiveEnergy = "calc.includeActiveEnergy"
        static let foodReminderEnabled = "reminder.food.enabled"
        static let weightReminderEnabled = "reminder.weight.enabled"
        static let trainingFuelAdjustmentEnabled = "nutrition.trainingFuelAdjustment.enabled"
        static let trainingDayDate = "nutrition.trainingDayDate"
        static let onboarded = "app.onboarded"
        static let bodyCompositionData = "profile.bodyComposition.v1"
        static let bodyCompositionSeedVersion = "profile.bodyComposition.seedVersion"
    }

    private let defaults: UserDefaults

    @Published var heightCm: Double { didSet { defaults.set(heightCm, forKey: Keys.heightCm) } }
    @Published var birthYear: Int { didSet { defaults.set(birthYear, forKey: Keys.birthYear) } }
    @Published var isMale: Bool { didSet { defaults.set(isMale, forKey: Keys.isMale) } }

    @Published var goalStartDate: Date { didSet { defaults.set(goalStartDate, forKey: Keys.goalStartDate) } }
    @Published var goalEndDate: Date { didSet { defaults.set(goalEndDate, forKey: Keys.goalEndDate) } }
    @Published var goalStartWeight: Double { didSet { defaults.set(goalStartWeight, forKey: Keys.goalStartWeight) } }
    @Published var goalWeight: Double { didSet { defaults.set(goalWeight, forKey: Keys.goalWeight) } }
    @Published var deficitStrategy: DeficitStrategy {
        didSet { defaults.set(deficitStrategy.rawValue, forKey: Keys.deficitStrategy) }
    }

    /// 基础活动系数（久坐 1.2 / 轻度 1.375 / 中度 1.55）
    @Published var activityFactor: Double { didSet { defaults.set(activityFactor, forKey: Keys.activityFactor) } }
    /// 是否把 Apple 健康的活动能量计入每日消耗
    @Published var includeActiveEnergy: Bool { didSet { defaults.set(includeActiveEnergy, forKey: Keys.includeActiveEnergy) } }
    @Published var foodReminderEnabled: Bool { didSet { defaults.set(foodReminderEnabled, forKey: Keys.foodReminderEnabled) } }
    @Published var weightReminderEnabled: Bool { didSet { defaults.set(weightReminderEnabled, forKey: Keys.weightReminderEnabled) } }
    @Published var trainingFuelAdjustmentEnabled: Bool {
        didSet {
            defaults.set(
                trainingFuelAdjustmentEnabled,
                forKey: Keys.trainingFuelAdjustmentEnabled
            )
        }
    }
    @Published private(set) var trainingDayDate: Date? {
        didSet {
            if let trainingDayDate {
                defaults.set(trainingDayDate, forKey: Keys.trainingDayDate)
            } else {
                defaults.removeObject(forKey: Keys.trainingDayDate)
            }
        }
    }
    @Published var bodyComposition: BodyCompositionProfile {
        didSet { persistBodyComposition() }
    }
    @Published private(set) var isOnboardingComplete: Bool

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults

        let calendar = Calendar.current
        let defaultBirthYear = calendar.component(.year, from: now) - 30
        let defaultGoalEnd = calendar.date(byAdding: .day, value: 90, to: now) ?? now
        let hadLegacyProfile = [
            Keys.heightCm,
            Keys.birthYear,
            Keys.isMale,
            Keys.goalStartWeight,
            Keys.goalWeight,
        ].contains { defaults.object(forKey: $0) != nil }

        if defaults.object(forKey: Keys.onboarded) != nil {
            isOnboardingComplete = defaults.bool(forKey: Keys.onboarded)
        } else {
            // 已经在用旧版本的设备不应被新 onboarding 打断；只有真正的新安装
            // 才要求用户明确填写个人资料，避免继承某位开发者的默认身体数据。
            isOnboardingComplete = hadLegacyProfile
            defaults.set(hadLegacyProfile, forKey: Keys.onboarded)
        }

        heightCm = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.heightCm,
            defaultValue: 170.0
        )
        birthYear = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.birthYear,
            defaultValue: defaultBirthYear
        )
        isMale = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.isMale,
            defaultValue: false
        )

        goalStartDate = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.goalStartDate,
            defaultValue: now
        )
        goalEndDate = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.goalEndDate,
            defaultValue: defaultGoalEnd
        )
        goalStartWeight = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.goalStartWeight,
            defaultValue: 80.0
        )
        goalWeight = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.goalWeight,
            defaultValue: 75.0
        )
        if let rawStrategy = defaults.string(forKey: Keys.deficitStrategy),
           let storedStrategy = DeficitStrategy(rawValue: rawStrategy) {
            deficitStrategy = storedStrategy
        } else {
            // 公开版保留按日期动态调整的默认行为；固定 750 必须由使用者主动选择。
            deficitStrategy = .deadlinePaced
            defaults.set(
                DeficitStrategy.deadlinePaced.rawValue,
                forKey: Keys.deficitStrategy
            )
        }

        activityFactor = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.activityFactor,
            defaultValue: 1.2
        )
        includeActiveEnergy = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.includeActiveEnergy,
            defaultValue: true
        )
        foodReminderEnabled = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.foodReminderEnabled,
            defaultValue: false
        )
        weightReminderEnabled = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.weightReminderEnabled,
            defaultValue: false
        )
        trainingFuelAdjustmentEnabled = Self.existingOrSeed(
            defaults: defaults,
            key: Keys.trainingFuelAdjustmentEnabled,
            defaultValue: false
        )
        trainingDayDate = defaults.object(forKey: Keys.trainingDayDate) as? Date

        if let storedObject = defaults.object(forKey: Keys.bodyCompositionData) {
            if let data = storedObject as? Data,
               let decoded = try? JSONDecoder().decode(BodyCompositionProfile.self, from: data) {
                bodyComposition = decoded
                defaults.set(1, forKey: Keys.bodyCompositionSeedVersion)
            } else {
                // 数据异常时不以默认值覆盖；保留空档案，等待用户明确编辑。
                bodyComposition = .empty
                defaults.set(1, forKey: Keys.bodyCompositionSeedVersion)
            }
        } else if defaults.integer(forKey: Keys.bodyCompositionSeedVersion) >= 1 {
            // 用户曾经清空整个档案时，不在下次启动重新灌入。
            bodyComposition = .empty
        } else {
            // 新安装必须从空档案开始，绝不把某位用户的身体成分或 DEXA
            // 数据当作产品默认值写入。已有持久化数据仍由上方分支原样读取。
            bodyComposition = .empty
            if let encoded = try? JSONEncoder().encode(bodyComposition) {
                defaults.set(encoded, forKey: Keys.bodyCompositionData)
            }
            defaults.set(1, forKey: Keys.bodyCompositionSeedVersion)
        }
    }

    var age: Int {
        max(10, Calendar.current.component(.year, from: .now) - birthYear)
    }

    var remainingDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: goalEndDate)).day ?? 0)
    }

    var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: goalStartDate), to: Calendar.current.startOfDay(for: goalEndDate)).day ?? 1)
    }

    func macroDayStyle(on date: Date = .now) -> MacroDayStyle {
        guard trainingFuelAdjustmentEnabled,
              let trainingDayDate,
              Calendar.current.isDate(trainingDayDate, inSameDayAs: date) else {
            return .standard
        }
        return .training
    }

    func setMacroDayStyle(_ style: MacroDayStyle, on date: Date = .now) {
        trainingDayDate = style == .training ? date : nil
    }

    func completeOnboarding() {
        isOnboardingComplete = true
        defaults.set(true, forKey: Keys.onboarded)
    }

    private func persistBodyComposition() {
        guard let encoded = try? JSONEncoder().encode(bodyComposition) else { return }
        defaults.set(encoded, forKey: Keys.bodyCompositionData)
        defaults.set(1, forKey: Keys.bodyCompositionSeedVersion)
    }

    private static func existingOrSeed<Value>(
        defaults: UserDefaults,
        key: String,
        defaultValue: Value
    ) -> Value {
        if let existing = defaults.object(forKey: key) as? Value {
            return existing
        }
        defaults.set(defaultValue, forKey: key)
        return defaultValue
    }
}
