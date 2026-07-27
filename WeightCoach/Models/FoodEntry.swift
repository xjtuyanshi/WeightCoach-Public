import Foundation
import SwiftData

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "cup.and.saucer"
        }
    }

    /// 根据当前时间推荐餐次
    static func suggested(for date: Date = .now) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }
}

enum FoodSource: String, Codable {
    case manual
    case ai
    case barcode
    case quickRepeat
    case referenceCatalog
    case brandCalculator

    var label: String {
        switch self {
        case .manual: return "手动"
        case .ai: return "AI 识别"
        case .barcode: return "扫码"
        case .quickRepeat: return "快捷再记"
        case .referenceCatalog: return "食物参考库"
        case .brandCalculator: return "品牌配方估算"
        }
    }
}

/// 饮食热量与 Apple 健康的同步状态。
///
/// `nil` 是旧版本迁移值：有 UUID 的旧记录按已同步处理，没有 UUID 的旧记录按未请求处理，
/// 避免升级后把历史记录全部错误标成失败。
enum FoodHealthSyncStatus: String, Codable, Sendable {
    case notRequested
    case pending
    case synced
    case failed
    case uncertain

    var needsAttention: Bool {
        // `.pending` 也必须可重试：若 App 在远端写入或状态落盘期间退出，
        // 下一次启动没有仍在运行的 Task 可以把它自动推进到 synced。
        self == .pending || self == .failed || self == .uncertain
    }
}

@Model
final class FoodEntry {
    var name: String
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var portionText: String?
    var mealTypeRaw: String
    var sourceRaw: String
    var date: Date
    var barcode: String?
    var healthKitSampleUUID: UUID?
    /// 可选字段保证旧 SwiftData store 可以轻量迁移。
    var healthKitSyncStatusRaw: String?
    var foodProductID: UUID?
    var amountValue: Double?
    var amountUnitRaw: String?
    var calculationVersion: Int?
    var fiber: Double?
    var sugar: Double?
    var sodiumMg: Double?
    var caffeineMg: Double?
    var calorieLowerBound: Double?
    var calorieUpperBound: Double?
    @Attribute(.externalStorage) var imageData: Data?

    init(
        name: String,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        portionText: String? = nil,
        mealType: MealType,
        source: FoodSource,
        date: Date = .now,
        barcode: String? = nil,
        healthKitSampleUUID: UUID? = nil,
        healthKitSyncStatus: FoodHealthSyncStatus? = nil,
        foodProductID: UUID? = nil,
        amountValue: Double? = nil,
        amountUnit: FoodQuantityUnit? = nil,
        calculationVersion: Int? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodiumMg: Double? = nil,
        caffeineMg: Double? = nil,
        calorieLowerBound: Double? = nil,
        calorieUpperBound: Double? = nil,
        imageData: Data? = nil
    ) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.portionText = portionText
        self.mealTypeRaw = mealType.rawValue
        self.sourceRaw = source.rawValue
        self.date = date
        self.barcode = barcode
        self.healthKitSampleUUID = healthKitSampleUUID
        self.healthKitSyncStatusRaw = healthKitSyncStatus?.rawValue
        self.foodProductID = foodProductID
        self.amountValue = amountValue
        self.amountUnitRaw = amountUnit?.rawValue
        self.calculationVersion = calculationVersion
        self.fiber = fiber
        self.sugar = sugar
        self.sodiumMg = sodiumMg
        self.caffeineMg = caffeineMg
        self.calorieLowerBound = calorieLowerBound
        self.calorieUpperBound = calorieUpperBound
        self.imageData = imageData
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var healthKitSyncStatus: FoodHealthSyncStatus {
        get {
            if let healthKitSyncStatusRaw,
               let status = FoodHealthSyncStatus(rawValue: healthKitSyncStatusRaw) {
                // 远端样本已删除但本地删除落盘失败时，清 UUID 的恢复写入
                // 可能成功；此时不能继续把一条纯本地记录显示成“已同步”。
                if status == .synced, healthKitSampleUUID == nil {
                    return .notRequested
                }
                return status
            }
            return healthKitSampleUUID == nil ? .notRequested : .synced
        }
        set {
            healthKitSyncStatusRaw = newValue.rawValue
        }
    }

    var amountUnit: FoodQuantityUnit? {
        get { amountUnitRaw.flatMap(FoodQuantityUnit.init(rawValue:)) }
        set { amountUnitRaw = newValue?.rawValue }
    }
}
