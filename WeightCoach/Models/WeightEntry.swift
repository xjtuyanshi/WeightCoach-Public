import Foundation
import SwiftData

@Model
final class WeightEntry {
    var date: Date
    var weightKg: Double
    /// 体脂率，0-100
    var bodyFatPercent: Double?
    var syncedToHealthKit: Bool

    init(date: Date = .now, weightKg: Double, bodyFatPercent: Double? = nil, syncedToHealthKit: Bool = false) {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.syncedToHealthKit = syncedToHealthKit
    }
}
