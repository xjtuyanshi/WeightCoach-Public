import Foundation

/// 热量计算引擎：BMR / TDEE / 每日缺口 / 剩余可摄入
enum CalorieEngine {

    /// 每公斤脂肪约 7700 千卡
    static let kcalPerKg: Double = 7700

    /// 基础代谢率。
    /// 有体脂率时用 Katch-McArdle（更准），否则用 Mifflin-St Jeor。
    static func bmr(weightKg: Double, heightCm: Double, age: Int, isMale: Bool, bodyFatPercent: Double?) -> Double {
        if let bf = bodyFatPercent, bf > 3, bf < 70 {
            let leanMass = weightKg * (1 - bf / 100)
            return 370 + 21.6 * leanMass
        }
        let sexConstant: Double = isMale ? 5 : -161
        return 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sexConstant
    }

    /// 食物热效应系数：计入手表活动能量时，只在 BMR 上加约 10% 的消化产热。
    /// 手表的活动能量已覆盖全天所有身体活动（不只是锻炼），
    /// 若再乘完整活动系数会把日常活动算两遍。
    static let tefOnlyFactor = 1.1

    /// 当日总消耗估算。
    /// 计入手表活动能量：BMR × 1.1 + 实测活动能量（活动系数不参与）；
    /// 否则：BMR × 活动系数。
    static func tdee(bmr: Double, activityFactor: Double, activeEnergyKcal: Double, includeActiveEnergy: Bool) -> Double {
        if includeActiveEnergy {
            return bmr * tefOnlyFactor + activeEnergyKcal
        }
        return bmr * activityFactor
    }

    /// 根据剩余目标动态计算每日应有的热量缺口。
    /// 已达标返回 0；否则按 剩余公斤 × 7700 / 剩余天数，并限制在 250~1000 千卡的安全区间。
    static func dailyDeficit(currentWeightKg: Double, goalWeightKg: Double, goalEndDate: Date, now: Date = .now) -> Double {
        let remainingKg = currentWeightKg - goalWeightKg
        guard remainingKg > 0 else { return 0 }
        let remainingDays = max(1.0, goalEndDate.timeIntervalSince(now) / 86_400)
        let raw = remainingKg * kcalPerKg / remainingDays
        return min(max(raw, 250), 1000)
    }

    /// 今日热量预算（还能吃多少的上限）= TDEE − 缺口，且不低于安全底线。
    static func dailyBudget(tdee: Double, deficit: Double, isMale: Bool) -> Double {
        let floor: Double = isMale ? 1500 : 1200
        return max(tdee - deficit, floor)
    }

    /// 按当前平均减重速度估算达成目标的日期
    static func projectedGoalDate(
        currentWeightKg: Double,
        goalWeightKg: Double,
        recentPoints: [(date: Date, weightKg: Double)]
    ) -> Date? {
        guard currentWeightKg > goalWeightKg, recentPoints.count >= 2 else { return nil }
        let sorted = recentPoints.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        guard days >= 3 else { return nil }
        let ratePerDay = (first.weightKg - last.weightKg) / days
        guard ratePerDay > 0.005 else { return nil }
        let remainingDays = (currentWeightKg - goalWeightKg) / ratePerDay
        guard remainingDays < 365 * 3 else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(remainingDays.rounded()), to: .now)
    }
}
