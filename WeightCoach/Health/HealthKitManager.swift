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
/// HealthKit 的 observer 回调可能跨线程；它们只捕获本对象后立即切回 MainActor，
/// 可观察状态也只在 MainActor 标记的方法中更新。
@Observable
final class HealthKitManager: DietaryEnergyHealthManaging, @unchecked Sendable {
    let store = HKHealthStore()
    @ObservationIgnored
    private let healthDataAvailable: () -> Bool
    @ObservationIgnored
    private var activityObserverQueries: [String: HKObserverQuery] = [:]
    @ObservationIgnored
    private var activityRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var activityRefreshPending = false

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
    var todayWorkoutIntervals: [HealthWorkoutInterval] = []
    var todayWorkoutCoverageAvailable = false
    var todayBasalEnergyKcal: Double = 0
    var todaySteps: Double = 0
    var lastActivityRefreshDate: Date?
    var activityDataErrorDescription: String?

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
            HKObjectType.workoutType(),
            HKObjectType.activitySummaryType(),
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
            startObservingActivityChangesIfNeeded()
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

        await refreshTodayActivityCoalesced()
        todayBasalEnergyKcal = (try? await todaySum(
            .basalEnergyBurned,
            unit: .kilocalorie()
        )) ?? 0
        startObservingActivityChangesIfNeeded()
    }

    /// 刷新步数和活动能量，但保持两者是独立 HealthKit 数据。
    /// 步数绝不会在这里静默换算成热量。
    @MainActor
    private func refreshTodayActivity() async {
        var errors: [String] = []
        // 查询完成前先停用手动补差，避免刷新窗口继续使用旧 workout 快照。
        todayWorkoutCoverageAvailable = false

        do {
            let now = Date.now
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: now)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(86_400)
            let intervals = try await todayActiveEnergySamples()
            // Activity Summary 是更合适的日总口径，但它是可选增强：权限、设备
            // 或当日数据导致查询不可用时，仍保留已经成功取得的统计回退值。
            let summaryByDay = (try? await fetchActivitySummaryEnergyByDay(
                from: dayStart,
                to: dayEnd,
                calendar: calendar
            )) ?? [:]
            todayActiveEnergyIntervals = intervals
            // Activity Summary 是 Apple 活动圆环对当天活动能量的权威口径；
            // 没有可用 summary（例如没有活动圆环数据）时才回退到统计查询。
            todayActiveEnergyKcal = HealthActivityEnergyResolver.dailyTotal(
                activitySummaryKcal: summaryByDay[dayStart],
                statisticsIntervals: intervals
            )
        } catch {
            // 查询失败时必须 fail closed，不能把上一次（尤其昨天）的活动热量
            // 继续带入今天的 TDEE。
            todayActiveEnergyIntervals = []
            todayActiveEnergyKcal = 0
            errors.append(error.localizedDescription)
        }

        do {
            let now = Date.now
            let start = Calendar.current.startOfDay(for: now)
            todayWorkoutIntervals = try await fetchWorkoutIntervals(
                from: start,
                to: now
            )
            todayWorkoutCoverageAvailable = true
        } catch {
            // Workout 只用于判断手动补记是否已被健康数据覆盖。它的查询失败
            // 不应抹掉刚刚成功读取的活动能量，更不能改变活动能量日总。
            todayWorkoutIntervals = []
            todayWorkoutCoverageAvailable = false
            errors.append(error.localizedDescription)
        }

        do {
            todaySteps = try await todaySum(.stepCount, unit: .count())
        } catch {
            todaySteps = 0
            errors.append(error.localizedDescription)
        }

        if errors.isEmpty {
            activityDataErrorDescription = nil
            lastActivityRefreshDate = .now
        } else {
            activityDataErrorDescription = errors.joined(separator: "\n")
        }
    }

    /// HealthKit 数据在 App 持续前台时也可能变化。Observer 只负责触发重新查询；
    /// 实际数值仍由上面的同一查询路径产生。后台唤醒不在本次范围内。
    @MainActor
    private func startObservingActivityChangesIfNeeded() {
        let sampleTypes: [HKSampleType] = [
            Self.quantityType(.activeEnergyBurned),
            Self.quantityType(.stepCount),
            HKObjectType.workoutType(),
        ]

        for sampleType in sampleTypes {
            let identifier = sampleType.identifier
            guard activityObserverQueries[identifier] == nil else { continue }

            let query = HKObserverQuery(
                sampleType: sampleType,
                predicate: nil
            ) { [weak self] observerQuery, completion, error in
                guard let self else {
                    completion()
                    return
                }

                Task { @MainActor in
                    await self.refreshTodayActivityCoalesced()
                    if let error {
                        let observerError = error.localizedDescription
                        if let queryError = self.activityDataErrorDescription,
                           !queryError.isEmpty,
                           queryError != observerError {
                            self.activityDataErrorDescription =
                                queryError + "\n" + observerError
                        } else {
                            self.activityDataErrorDescription = observerError
                        }
                        if let stored = self.activityObserverQueries[identifier],
                           stored === observerQuery {
                            self.store.stop(stored)
                            self.activityObserverQueries.removeValue(forKey: identifier)
                        }
                    }
                    completion()
                }
            }
            activityObserverQueries[identifier] = query
            store.execute(query)
        }
    }

    @MainActor
    private func refreshTodayActivityCoalesced() async {
        activityRefreshPending = true
        if let activityRefreshTask {
            await activityRefreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.activityRefreshPending {
                self.activityRefreshPending = false
                await self.refreshTodayActivity()
            }
            self.activityRefreshTask = nil
        }
        activityRefreshTask = task
        await task.value
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

    private func todaySum(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let start = Calendar.current.startOfDay(for: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: Self.quantityType(id),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// 读取今天开始至当前时刻的 HealthKit 活动能量统计分钟桶。
    ///
    /// 不能把 `HKSampleQuery` 返回的原始样本直接相加：Apple Watch、iPhone
    /// 和第三方运动 App 可能在同一时段分别写入样本。分钟统计只用于手动运动
    /// 的时间重叠与无 Activity Summary 时的回退；当天展示总数优先采用
    /// `HKActivitySummary.activeEnergyBurned`。
    private func todayActiveEnergySamples() async throws -> [HealthActiveEnergyInterval] {
        let now = Date.now
        let start = Calendar.current.startOfDay(for: now)
        return try await mergedActiveEnergyIntervals(from: start, to: now)
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

        async let statisticsTask = fetchDailyActiveEnergyStatistics(
            from: start,
            to: end,
            calendar: calendar
        )
        async let summaryTask = fetchActivitySummaryEnergyByDay(
            from: start,
            to: end,
            calendar: calendar
        )
        let statistics = try await statisticsTask
        let summaries = (try? await summaryTask) ?? [:]

        let statisticsByDay = Dictionary(
            statistics.map {
                (calendar.startOfDay(for: $0.dayStart), $0.kcal)
            },
            uniquingKeysWith: { _, newest in newest }
        )
        var readings: [DailyActiveEnergyReading] = []
        var dayStart = start
        while dayStart < end {
            let statisticsValue = statisticsByDay[dayStart] ?? nil
            readings.append(
                DailyActiveEnergyReading(
                    dayStart: dayStart,
                    kcal: summaries[dayStart] ?? statisticsValue
                )
            )
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: dayStart
            ), nextDay > dayStart else {
                break
            }
            dayStart = nextDay
        }
        return readings
    }

    private func fetchDailyActiveEnergyStatistics(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) async throws -> [DailyActiveEnergyReading] {

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

    /// 读取 Apple 活动圆环的每日活动能量。返回字典仅包含 HealthKit 实际提供
    /// summary 的日期；调用方可对缺失日期回退到 quantity statistics。
    private func fetchActivitySummaryEnergyByDay(
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar
    ) async throws -> [Date: Double] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard end > start else { return [:] }

        // HealthKit 要求 activity-summary predicate 的日期组件使用公历；结果
        // 再映射回调用方日历的 dayStart，避免非公历系统设置查不到 summary。
        var predicateCalendar = Calendar(identifier: .gregorian)
        predicateCalendar.timeZone = calendar.timeZone
        let components: Set<Calendar.Component> = [.era, .year, .month, .day]
        var startComponents = predicateCalendar.dateComponents(
            components,
            from: start
        )
        startComponents.calendar = predicateCalendar
        let lastIncludedDate = end.addingTimeInterval(-1)
        var endComponents = predicateCalendar.dateComponents(
            components,
            from: lastIncludedDate
        )
        endComponents.calendar = predicateCalendar
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComponents,
            end: endComponents
        )

        let summaries = try await HKActivitySummaryQueryDescriptor(
            predicate: predicate
        ).result(for: store)
        var byDay: [Date: Double] = [:]
        for summary in summaries {
            let kcal = summary.activeEnergyBurned.doubleValue(
                for: .kilocalorie()
            )
            guard kcal.isFinite, kcal >= 0,
                  let date = predicateCalendar.date(
                    from: summary.dateComponents(for: predicateCalendar)
                  ) else {
                continue
            }
            byDay[calendar.startOfDay(for: date)] = kcal
        }
        return byDay
    }

    /// 读取与手动运动区间重叠的活动能量原始样本，用于历史补差去重。
    func fetchActiveEnergyIntervals(
        overlapping intervals: [DateInterval]
    ) async throws -> [HealthActiveEnergyInterval] {
        guard isAvailable else { return [] }
        let merged = Self.merge(intervals: intervals)
        guard !merged.isEmpty else { return [] }

        return try await withThrowingTaskGroup(
            of: [HealthActiveEnergyInterval].self
        ) { group in
            for interval in merged {
                group.addTask {
                    try await self.mergedActiveEnergyIntervals(
                        from: interval.start,
                        to: interval.end
                    )
                }
            }

            var results: [HealthActiveEnergyInterval] = []
            for try await batch in group {
                results.append(contentsOf: batch)
            }
            return results.sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }
        }
    }

    /// 读取指定时间范围内与之相交的 HealthKit 运动快照。
    ///
    /// Workout 能量只表示对应手动补记已经有健康记录覆盖；这里不会把它加入
    /// 活动能量日总，避免和 `activeEnergyBurned` 再算一次。
    func fetchWorkoutIntervals(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthWorkoutInterval] {
        guard isAvailable,
              startDate.timeIntervalSinceReferenceDate.isFinite,
              endDate.timeIntervalSinceReferenceDate.isFinite,
              endDate > startDate else {
            return []
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HealthWorkoutInterval], Error>) in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: []
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let activeEnergyType = Self.quantityType(.activeEnergyBurned)
                let intervals = (samples as? [HKWorkout])?.compactMap {
                    workout -> HealthWorkoutInterval? in
                    guard workout.startDate < endDate,
                          workout.endDate > startDate,
                          workout.endDate > workout.startDate,
                          let activityType = Self.exerciseActivityType(
                              for: workout.workoutActivityType
                          ) else {
                        return nil
                    }

                    let activeEnergyKcal = workout
                        .statistics(for: activeEnergyType)?
                        .sumQuantity()?
                        .doubleValue(for: .kilocalorie())
                    let hasActiveEnergy = activeEnergyKcal.map {
                        $0.isFinite && $0 > 0
                    } ?? false

                    return HealthWorkoutInterval(
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        activityType: activityType,
                        hasActiveEnergy: hasActiveEnergy
                    )
                } ?? []
                continuation.resume(returning: intervals)
            }
            store.execute(query)
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
        let workoutIntervals: [HealthWorkoutInterval]
        let manualOverlapDataAvailable: Bool
        if includeActiveEnergy {
            dailyActiveEnergy = try await fetchDailyActiveEnergy(
                from: startDate,
                to: endDate,
                calendar: calendar
            )
            if exerciseIntervals.isEmpty {
                activeEnergyIntervals = []
                workoutIntervals = []
                manualOverlapDataAvailable = true
            } else {
                activeEnergyIntervals = try await fetchActiveEnergyIntervals(
                    overlapping: exerciseIntervals
                )
                // Workout 是更高置信的覆盖证据，但不是趋势页读取成功的
                // 前置条件；失败时趋势仍可显示饮食等数据，但手动补差必须
                // fail closed，不能把“查询失败”误当成“没有 workout”。
                do {
                    workoutIntervals = try await fetchWorkoutIntervals(
                        from: startDate,
                        to: endDate
                    )
                    manualOverlapDataAvailable = true
                } catch {
                    workoutIntervals = []
                    manualOverlapDataAvailable = false
                }
            }
        } else {
            dailyActiveEnergy = []
            activeEnergyIntervals = []
            workoutIntervals = []
            manualOverlapDataAvailable = true
        }

        return try await HistoricalTrendHealthData(
            dailyActiveEnergy: dailyActiveEnergy,
            activeEnergyIntervals: activeEnergyIntervals,
            workoutIntervals: workoutIntervals,
            weightPoints: weightPoints,
            bodyFatPoints: bodyFatPoints,
            manualOverlapDataAvailable: manualOverlapDataAvailable
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

    /// HealthKit minute statistics preserve timing information for manual
    /// exercise overlap. Daily totals prefer Activity Summary instead of
    /// summing raw Watch, phone, and third-party samples ourselves.
    private func mergedActiveEnergyIntervals(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthActiveEnergyInterval] {
        guard startDate.timeIntervalSinceReferenceDate.isFinite,
              endDate.timeIntervalSinceReferenceDate.isFinite,
              endDate > startDate else {
            return []
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HealthActiveEnergyInterval], Error>) in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: []
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: Self.quantityType(.activeEnergyBurned),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: DateComponents(minute: 1)
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

                var intervals: [HealthActiveEnergyInterval] = []
                collection.enumerateStatistics(from: startDate, to: endDate) {
                    statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let kcal = quantity.doubleValue(for: .kilocalorie())
                    let bucketStart = max(startDate, statistics.startDate)
                    let bucketEnd = min(endDate, statistics.endDate)
                    guard kcal.isFinite,
                          kcal > 0,
                          let interval = HealthActiveEnergyInterval(
                              startDate: bucketStart,
                              endDate: bucketEnd,
                              kcal: kcal
                          ) else {
                        return
                    }
                    intervals.append(interval)
                }
                continuation.resume(returning: intervals)
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

    private static func exerciseActivityType(
        for workoutType: HKWorkoutActivityType
    ) -> ExerciseActivityType? {
        switch workoutType {
        case .running:
            return .running
        case .walking:
            return .walking
        case .basketball:
            return .basketball
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .strengthTraining
        default:
            return nil
        }
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
