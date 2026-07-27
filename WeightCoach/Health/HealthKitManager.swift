import Foundation
import HealthKit
import Observation

enum HealthKitManagerError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "当前设备无法访问 Apple 健康"
        }
    }
}

struct DietaryEnergyWrite: Sendable {
    let kcal: Double
    let name: String
    let date: Date
}

/// Apple 健康中的一条活动能量样本，已转换为可跨并发边界传递的纯值。
///
/// `startDate == endDate` 表示点样本；负数、非有限热量及倒序时间区间不会进入该类型。
struct HealthActiveEnergyInterval: Sendable, Equatable {
    let startDate: Date
    let endDate: Date
    let kcal: Double

    init?(startDate: Date, endDate: Date, kcal: Double) {
        guard kcal.isFinite, kcal >= 0, endDate >= startDate else { return nil }
        self.startDate = startDate
        self.endDate = endDate
        self.kcal = kcal
    }
}

/// 样本 UUID 在写入 HealthKit 前已经确定，可先随本地记录一次落盘，避免远端孤儿样本。
struct PreparedDietaryEnergyBatch {
    let samplesByIndex: [HKQuantitySample?]

    var sampleUUIDs: [UUID?] {
        samplesByIndex.map { $0?.uuid }
    }
}

protocol DietaryEnergyHealthManaging: AnyObject {
    func prepareDietaryEnergy(_ writes: [DietaryEnergyWrite]) -> PreparedDietaryEnergyBatch
    func saveDietaryEnergy(_ batch: PreparedDietaryEnergyBatch) async throws
    func deleteDietaryEnergy(sampleUUID: UUID) async throws
}

/// 与 Apple 健康交互：读取身体数据与活动能量，写入体重/体脂/饮食能量
@Observable
final class HealthKitManager: DietaryEnergyHealthManaging {
    let store = HKHealthStore()
    @ObservationIgnored
    private let healthDataAvailable: () -> Bool

    var isAvailable: Bool { healthDataAvailable() }
    var authorizationRequested = false
    var authorizationErrorDescription: String?

    // 最新身体数据
    var latestWeightKg: Double?
    var latestWeightDate: Date?
    var latestBodyFatPercent: Double?   // 0-100
    var latestBodyFatDate: Date?
    var heightCm: Double?
    var ageYears: Int?
    var isMale: Bool?

    // 今日能量
    var todayActiveEnergyKcal: Double = 0
    var todayActiveEnergyIntervals: [HealthActiveEnergyInterval] = []
    var todayBasalEnergyKcal: Double = 0
    var todaySteps: Double = 0

    init(
        healthDataAvailable: @escaping () -> Bool = {
            HKHealthStore.isHealthDataAvailable()
        }
    ) {
        self.healthDataAvailable = healthDataAvailable
    }

    private static func quantityType(_ id: HKQuantityTypeIdentifier) -> HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: id)!
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            Self.quantityType(.bodyMass),
            Self.quantityType(.bodyFatPercentage),
            Self.quantityType(.height),
            Self.quantityType(.activeEnergyBurned),
            Self.quantityType(.basalEnergyBurned),
            Self.quantityType(.stepCount),
            Self.quantityType(.dietaryEnergyConsumed),
        ]
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        [
            Self.quantityType(.bodyMass),
            Self.quantityType(.bodyFatPercentage),
            Self.quantityType(.dietaryEnergyConsumed),
        ]
    }

    // MARK: - 授权

    @MainActor
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            authorizationRequested = true
            authorizationErrorDescription = nil
            await refreshAll()
            return true
        } catch {
            authorizationErrorDescription = error.localizedDescription
            return false
        }
    }

    // MARK: - 读取

    @MainActor
    func refreshAll() async {
        guard isAvailable else { return }

        readCharacteristics()

        if let sample = await latestSample(.bodyMass) {
            latestWeightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            latestWeightDate = sample.startDate
        }
        if let sample = await latestSample(.bodyFatPercentage) {
            latestBodyFatPercent = sample.quantity.doubleValue(for: .percent()) * 100
            latestBodyFatDate = sample.startDate
        }
        if let sample = await latestSample(.height) {
            heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
        }

        let activeEnergyIntervals = await todayActiveEnergySamples()
        todayActiveEnergyIntervals = activeEnergyIntervals
        todayActiveEnergyKcal = activeEnergyIntervals.reduce(0) { $0 + $1.kcal }
        todayBasalEnergyKcal = await todaySum(.basalEnergyBurned, unit: .kilocalorie())
        todaySteps = await todaySum(.stepCount, unit: .count())
    }

    private func readCharacteristics() {
        if let dob = try? store.dateOfBirthComponents() {
            ageYears = Self.calculatedAgeYears(
                dateOfBirth: dob,
                now: .now,
                calendar: .current
            )
        }
        if let sexObject = try? store.biologicalSex() {
            switch sexObject.biologicalSex {
            case .male: isMale = true
            case .female: isMale = false
            default: break
            }
        }
    }

    static func calculatedAgeYears(
        dateOfBirth: DateComponents,
        now: Date,
        calendar: Calendar
    ) -> Int? {
        guard let birthDate = calendar.date(from: dateOfBirth),
              birthDate <= now,
              let years = calendar.dateComponents(
                [.year],
                from: birthDate,
                to: now
              ).year else {
            return nil
        }
        return max(1, years)
    }

    private func latestSample(_ id: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: Self.quantityType(id),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let start = Calendar.current.startOfDay(for: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: Self.quantityType(id),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// 读取今天开始至当前时刻的活动能量原始样本。
    ///
    /// 今日总活动能量由这组区间直接求和，确保总数和后续按时间重叠去重使用同一份数据。
    private func todayActiveEnergySamples() async -> [HealthActiveEnergyInterval] {
        await withCheckedContinuation { continuation in
            let now = Date.now
            let start = Calendar.current.startOfDay(for: now)
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: now,
                options: .strictStartDate
            )
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: Self.quantityType(.activeEnergyBurned),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let intervals = (samples as? [HKQuantitySample])?.compactMap { sample in
                    HealthActiveEnergyInterval(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        kcal: sample.quantity.doubleValue(for: .kilocalorie())
                    )
                } ?? []
                continuation.resume(returning: intervals)
            }
            store.execute(query)
        }
    }

    /// 拉取一段时间内按自然日分桶的活动能量。
    ///
    /// `kcal == nil` 表示该日没有读到统计值，不会被解释成 0 千卡。
    func fetchDailyActiveEnergy(
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = .current
    ) async throws -> [DailyActiveEnergyReading] {
        guard isAvailable else { return [] }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard end > start else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: []
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: Self.quantityType(.activeEnergyBurned),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var readings: [DailyActiveEnergyReading] = []
                collection.enumerateStatistics(from: start, to: end) {
                    statistics, _ in
                    guard statistics.startDate < end else { return }
                    readings.append(
                        DailyActiveEnergyReading(
                            dayStart: calendar.startOfDay(
                                for: statistics.startDate
                            ),
                            kcal: statistics
                                .sumQuantity()?
                                .doubleValue(for: .kilocalorie())
                        )
                    )
                }
                continuation.resume(returning: readings)
            }
            store.execute(query)
        }
    }

    /// 读取与手动运动区间重叠的活动能量原始样本，用于历史补差去重。
    func fetchActiveEnergyIntervals(
        overlapping intervals: [DateInterval]
    ) async throws -> [HealthActiveEnergyInterval] {
        guard isAvailable else { return [] }
        let merged = Self.merge(intervals: intervals)
        guard !merged.isEmpty else { return [] }

        return try await withThrowingTaskGroup(
            of: [(UUID, HealthActiveEnergyInterval)].self
        ) { group in
            for interval in merged {
                group.addTask {
                    try await self.fetchIdentifiedActiveEnergyIntervals(
                        overlapping: interval
                    )
                }
            }

            var byUUID: [UUID: HealthActiveEnergyInterval] = [:]
            for try await batch in group {
                for (uuid, interval) in batch {
                    byUUID[uuid] = interval
                }
            }
            return byUUID.values.sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }
        }
    }

    /// 趋势页所需的 HealthKit 历史输入。体重/体脂会额外带上区间前最后一笔，
    /// 避免在第一天错误地回退到档案值。
    func fetchHistoricalTrendHealthData(
        from startDate: Date,
        to endDate: Date,
        exerciseIntervals: [DateInterval],
        includeActiveEnergy: Bool,
        calendar: Calendar = .current
    ) async throws -> HistoricalTrendHealthData {
        guard isAvailable else {
            return HistoricalTrendHealthData(
                dailyActiveEnergy: [],
                activeEnergyIntervals: [],
                weightPoints: [],
                bodyFatPoints: [],
                manualOverlapDataAvailable: exerciseIntervals.isEmpty
            )
        }

        async let weightPoints = fetchHistoryIncludingBaseline(
            .bodyMass,
            from: startDate,
            to: endDate
        ) {
            $0.doubleValue(for: .gramUnit(with: .kilo))
        }
        async let bodyFatPoints = fetchHistoryIncludingBaseline(
            .bodyFatPercentage,
            from: startDate,
            to: endDate
        ) {
            $0.doubleValue(for: .percent()) * 100
        }

        let dailyActiveEnergy: [DailyActiveEnergyReading]
        let activeEnergyIntervals: [HealthActiveEnergyInterval]
        if includeActiveEnergy {
            dailyActiveEnergy = try await fetchDailyActiveEnergy(
                from: startDate,
                to: endDate,
                calendar: calendar
            )
            activeEnergyIntervals = try await fetchActiveEnergyIntervals(
                overlapping: exerciseIntervals
            )
        } else {
            dailyActiveEnergy = []
            activeEnergyIntervals = []
        }

        return try await HistoricalTrendHealthData(
            dailyActiveEnergy: dailyActiveEnergy,
            activeEnergyIntervals: activeEnergyIntervals,
            weightPoints: weightPoints,
            bodyFatPoints: bodyFatPoints,
            manualOverlapDataAvailable: true
        )
    }

    /// 拉取一段时间内的体重记录（升序），用于趋势图
    func fetchWeightHistory(since startDate: Date) async -> [(date: Date, valueKg: Double)] {
        await fetchHistory(.bodyMass, since: startDate) { $0.doubleValue(for: .gramUnit(with: .kilo)) }
    }

    /// 拉取一段时间内的体脂率记录（升序，0-100）
    func fetchBodyFatHistory(since startDate: Date) async -> [(date: Date, valueKg: Double)] {
        await fetchHistory(.bodyFatPercentage, since: startDate) { $0.doubleValue(for: .percent()) * 100 }
    }

    private func fetchHistory(
        _ id: HKQuantityTypeIdentifier,
        since startDate: Date,
        convert: @escaping (HKQuantity) -> Double
    ) async -> [(date: Date, valueKg: Double)] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: Self.quantityType(id),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let points = (samples as? [HKQuantitySample])?.map {
                    (date: $0.startDate, valueKg: convert($0.quantity))
                } ?? []
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func fetchHistoryIncludingBaseline(
        _ id: HKQuantityTypeIdentifier,
        from startDate: Date,
        to endDate: Date,
        convert: @escaping (HKQuantity) -> Double
    ) async throws -> [HistoricalBodyPoint] {
        async let baseline = fetchHistoryPoints(
            id,
            predicate: HKQuery.predicateForSamples(
                withStart: nil,
                end: startDate,
                options: .strictEndDate
            ),
            limit: 1,
            ascending: false,
            convert: convert
        )
        async let range = fetchHistoryPoints(
            id,
            predicate: HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            ),
            limit: HKObjectQueryNoLimit,
            ascending: true,
            convert: convert
        )

        return try await (baseline + range)
            .filter { $0.date < endDate }
            .sorted { $0.date < $1.date }
    }

    private func fetchHistoryPoints(
        _ id: HKQuantityTypeIdentifier,
        predicate: NSPredicate,
        limit: Int,
        ascending: Bool,
        convert: @escaping (HKQuantity) -> Double
    ) async throws -> [HistoricalBodyPoint] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: ascending
            )
            let query = HKSampleQuery(
                sampleType: Self.quantityType(id),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let points = (samples as? [HKQuantitySample])?.compactMap {
                    sample -> HistoricalBodyPoint? in
                    let value = convert(sample.quantity)
                    guard value.isFinite else { return nil }
                    return HistoricalBodyPoint(
                        date: sample.startDate,
                        value: value
                    )
                } ?? []
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func fetchIdentifiedActiveEnergyIntervals(
        overlapping interval: DateInterval
    ) async throws -> [(UUID, HealthActiveEnergyInterval)] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: interval.start,
                end: interval.end,
                options: []
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: Self.quantityType(.activeEnergyBurned),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let identified = (samples as? [HKQuantitySample])?.compactMap {
                    sample -> (UUID, HealthActiveEnergyInterval)? in
                    guard sample.startDate < interval.end,
                          sample.endDate >= interval.start,
                          let value = HealthActiveEnergyInterval(
                              startDate: sample.startDate,
                              endDate: sample.endDate,
                              kcal: sample.quantity.doubleValue(
                                  for: .kilocalorie()
                              )
                          ) else {
                        return nil
                    }
                    return (sample.uuid, value)
                } ?? []
                continuation.resume(returning: identified)
            }
            store.execute(query)
        }
    }

    private static func merge(
        intervals: [DateInterval]
    ) -> [DateInterval] {
        let sorted = intervals
            .filter {
                $0.start.timeIntervalSinceReferenceDate.isFinite
                    && $0.end.timeIntervalSinceReferenceDate.isFinite
                    && $0.duration.isFinite
                    && $0.duration > 0
            }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var merged: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(
                    start: current.start,
                    end: max(current.end, interval.end)
                )
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    // MARK: - 写入

    func saveWeight(kg: Double, bodyFatPercent: Double?, date: Date) async throws {
        guard isAvailable else {
            throw HealthKitManagerError.healthDataUnavailable
        }
        var samples: [HKQuantitySample] = [
            HKQuantitySample(
                type: Self.quantityType(.bodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                start: date,
                end: date
            )
        ]
        if let bf = bodyFatPercent, bf > 0 {
            samples.append(
                HKQuantitySample(
                    type: Self.quantityType(.bodyFatPercentage),
                    quantity: HKQuantity(unit: .percent(), doubleValue: bf / 100),
                    start: date,
                    end: date
                )
            )
        }
        try await store.save(samples)
    }

    @discardableResult
    func saveDietaryEnergy(kcal: Double, name: String, date: Date) async throws -> UUID? {
        let batch = prepareDietaryEnergy(
            [DietaryEnergyWrite(kcal: kcal, name: name, date: date)]
        )
        try await saveDietaryEnergy(batch)
        return batch.sampleUUIDs.first ?? nil
    }

    /// 先构造样本；返回 UUID 与输入下标对齐。此步骤不会修改 HealthKit。
    func prepareDietaryEnergy(_ writes: [DietaryEnergyWrite]) -> PreparedDietaryEnergyBatch {
        guard isAvailable else {
            return PreparedDietaryEnergyBatch(
                samplesByIndex: Array(repeating: nil, count: writes.count)
            )
        }

        let samples = writes.map { write -> HKQuantitySample? in
            guard write.kcal.isFinite, write.kcal > 0 else { return nil }
            return HKQuantitySample(
                type: Self.quantityType(.dietaryEnergyConsumed),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: write.kcal),
                start: write.date,
                end: write.date,
                metadata: [HKMetadataKeyFoodType: write.name]
            )
        }
        return PreparedDietaryEnergyBatch(samplesByIndex: samples)
    }

    /// 一次写入预先构造的样本；其 UUID 已经可以在调用前持久化。
    func saveDietaryEnergy(_ batch: PreparedDietaryEnergyBatch) async throws {
        let samples = batch.samplesByIndex.compactMap { $0 }
        guard !samples.isEmpty else { return }
        try await store.save(samples)
    }

    /// 兼容单独调用方：准备并写入，返回值仍与输入下标对齐。
    func saveDietaryEnergy(_ writes: [DietaryEnergyWrite]) async throws -> [UUID?] {
        let batch = prepareDietaryEnergy(writes)
        try await saveDietaryEnergy(batch)
        return batch.sampleUUIDs
    }

    /// 删除由本 App 写入的饮食热量样本。样本已在健康中被删除时按成功处理。
    func deleteDietaryEnergy(sampleUUID: UUID) async throws {
        guard isAvailable else { throw HealthKitManagerError.healthDataUnavailable }
        let predicate = HKQuery.predicateForObject(with: sampleUUID)
        let _: Int = try await store.deleteObjects(
            of: Self.quantityType(.dietaryEnergyConsumed),
            predicate: predicate
        )
    }
}
