import Foundation

/// Selects the authoritative daily active-energy value shown by the app.
///
/// Activity Summary is the same daily Move value exposed by HealthKit. Minute
/// statistics remain a fallback for devices or days without an activity
/// summary, and are also retained separately for manual-exercise overlap.
enum HealthActivityEnergyResolver {
    static func dailyTotal(
        activitySummaryKcal: Double?,
        statisticsIntervals: [HealthActiveEnergyInterval]
    ) -> Double {
        if let activitySummaryKcal,
           activitySummaryKcal.isFinite,
           activitySummaryKcal >= 0 {
            return activitySummaryKcal
        }

        return statisticsIntervals.reduce(0.0) { total, interval in
            guard interval.kcal.isFinite, interval.kcal >= 0 else { return total }
            let sum = total + interval.kcal
            return sum.isFinite ? sum : .greatestFiniteMagnitude
        }
    }
}
