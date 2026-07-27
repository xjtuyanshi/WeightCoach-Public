import Charts
import SwiftData
import SwiftUI

enum HistoricalTrendRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sevenDays: return "近 7 天"
        case .thirtyDays: return "近 30 天"
        }
    }
}

enum HistoricalTrendMetric: String, CaseIterable, Identifiable {
    case energy
    case protein
    case carbs
    case fat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: return "能量"
        case .protein: return "蛋白质"
        case .carbs: return "碳水"
        case .fat: return "脂肪"
        }
    }

    var color: Color {
        switch self {
        case .energy: return .green
        case .protein: return .blue
        case .carbs: return .orange
        case .fat: return .pink
        }
    }
}

@MainActor
enum HistoricalTrendLoader {
    static func load(
        days: Int,
        profile: ProfileStore,
        health: HealthKitManager,
        foods: [FoodEntry],
        exercises: [ExerciseEntry],
        localWeights: [WeightEntry],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) async throws -> HistoricalTrendResult {
        let effectiveReferenceDate = DemoMode.demoTrendsEnabled
            ? DemoMode.trendReferenceDate(calendar: calendar)
            : referenceDate
        let todayStart = calendar.startOfDay(for: effectiveReferenceDate)
        let start = calendar.date(
            byAdding: .day,
            value: -(max(1, days) - 1),
            to: todayStart
        ) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart)
            ?? todayStart.addingTimeInterval(86_400)
        let relevantExerciseIntervals = exercises
            .map(\.energyInterval)
            .filter { $0.startDate < end && $0.endDate > start }
            .map {
                DateInterval(start: $0.startDate, end: $0.endDate)
            }

        let healthData: HistoricalTrendHealthData
        if DemoMode.demoTrendsEnabled {
            healthData = DemoMode.historicalTrendHealthData(
                from: start,
                to: end,
                calendar: calendar
            )
        } else {
            healthData = try await health.fetchHistoricalTrendHealthData(
                from: start,
                to: end,
                exerciseIntervals: relevantExerciseIntervals,
                includeActiveEnergy: profile.includeActiveEnergy,
                calendar: calendar
            )
        }

        let calibration = profile.bodyComposition.calibratedBodyFatPercent
        let configuration = HistoricalTrendConfiguration(
            heightCm: health.heightCm ?? profile.heightCm,
            age: health.ageYears ?? profile.age,
            isMale: health.isMale ?? profile.isMale,
            activityFactor: profile.activityFactor,
            includeActiveEnergy: profile.includeActiveEnergy,
            fallbackWeightKg: profile.goalStartWeight,
            calibratedBodyFatPercent: calibration.unit == .percent
                ? calibration.value
                : nil,
            calibratedBodyFatMeasuredAt: calibration.measuredAt
        )
        let localWeightPoints = localWeights.map {
            HistoricalBodyPoint(date: $0.date, value: $0.weightKg)
        }
        let localBodyFatPoints = localWeights.compactMap { entry in
            entry.bodyFatPercent.map {
                HistoricalBodyPoint(date: entry.date, value: $0)
            }
        }

        return HistoricalTrendEngine.calculate(
            from: start,
            to: end,
            referenceDate: effectiveReferenceDate,
            calendar: calendar,
            configuration: configuration,
            foods: foods.map(HistoricalTrendFood.init),
            exercises: exercises.map(HistoricalTrendExercise.init),
            localWeights: localWeightPoints,
            localBodyFat: localBodyFatPoints,
            healthData: healthData
        )
    }
}

struct NutritionTrendsView: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \ExerciseEntry.startDate, order: .reverse)
    private var exercises: [ExerciseEntry]
    @Query(sort: \WeightEntry.date, order: .reverse)
    private var localWeights: [WeightEntry]
    @Environment(\.locale) private var locale

    @State private var selectedRange: HistoricalTrendRange = .sevenDays
    @State private var selectedMetric: HistoricalTrendMetric = .energy
    @State private var result = HistoricalTrendResult(points: [])
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var loadRequestID = UUID()

    private var visibleResult: HistoricalTrendResult {
        result.suffix(days: selectedRange.rawValue)
    }

    private var weeklySummary: HistoricalTrendWeeklySummary {
        result.weeklySummary(
            referenceDate: DemoMode.demoTrendsEnabled
                ? DemoMode.trendReferenceDate()
                : .now,
            calendar: .current
        )
    }

    private var refreshKey: String {
        let calibration =
            profile.bodyComposition.calibratedBodyFatPercent
        let components: [String] = [
            String(foods.count),
            foods.first?.date.timeIntervalSinceReferenceDate.description ?? "-",
            String(exercises.count),
            exercises.first?.startDate.timeIntervalSinceReferenceDate.description ?? "-",
            String(localWeights.count),
            localWeights.first?.date.timeIntervalSinceReferenceDate.description ?? "-",
            profile.includeActiveEnergy.description,
            profile.activityFactor.description,
            profile.heightCm.description,
            String(profile.age),
            profile.isMale.description,
            profile.goalStartWeight.description,
            calibration.value?.description ?? "-",
            calibration.measuredAt?
                .timeIntervalSinceReferenceDate.description ?? "-",
            calibration.unit.rawValue,
            health.authorizationRequested.description,
            health.heightCm?.description ?? "-",
            health.ageYears.map(String.init) ?? "-",
            health.isMale?.description ?? "-",
            health.latestWeightKg?.description ?? "-",
            health.latestWeightDate?.timeIntervalSinceReferenceDate.description ?? "-",
            health.latestBodyFatPercent?.description ?? "-",
            health.latestBodyFatDate?.timeIntervalSinceReferenceDate.description ?? "-",
        ]
        return components.joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("时间范围", selection: $selectedRange) {
                    ForEach(HistoricalTrendRange.allCases) { range in
                        Text(interfaceLocalized(range.label, locale: locale)).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                weeklySummaryCard

                Picker("趋势指标", selection: $selectedMetric) {
                    ForEach(HistoricalTrendMetric.allCases) { metric in
                        Text(interfaceLocalized(metric.label, locale: locale)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                if isLoading && result.points.isEmpty {
                    ProgressView("正在读取历史数据…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if let loadError, result.points.isEmpty {
                    ContentUnavailableView(
                        "趋势暂时不可用",
                        systemImage: "chart.xyaxis.line",
                        description: Text(loadError)
                    )
                    Button("重试") {
                        Task { await reload() }
                    }
                } else if selectedMetric == .energy {
                    energyCharts
                } else {
                    macroChart
                }

                coverageCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("饮食与能量趋势")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task(id: refreshKey) { await reload() }
    }

    private var weeklySummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本周能量账本", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Text("截至昨天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if weeklySummary.completedDayCount == 0 {
                Text("本周还没有已结束的日期")
                    .font(.title3.bold())
            } else if let balance = weeklySummary.cumulativeEnergyBalanceKcal {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(interfaceLocalized(
                        balance >= 0 ? "估算缺口" : "估算盈余",
                        locale: locale
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(abs(balance).kcalText)
                        .font(.system(.title, design: .rounded).bold())
                        .foregroundStyle(balance >= 0 ? .green : .red)
                    Text("千卡")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("数据不足，暂不能计算本周能量差")
                    .font(.title3.bold())
            }

            Text(weeklyCoverageText)
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("正数为缺口，负数为盈余；周末多吃会抵消之前的缺口。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var energyCharts: some View {
        VStack(spacing: 16) {
            chartCard(title: "每日摄入与估算消耗") {
                Chart {
                    ForEach(visibleResult.points) { point in
                        if let intake = point.intakeKcal {
                            BarMark(
                                x: .value(interfaceLocalized("日期", locale: locale), point.dayStart, unit: .day),
                                y: .value(interfaceLocalized("千卡", locale: locale), intake)
                            )
                            .position(by: .value(interfaceLocalized("系列", locale: locale), interfaceLocalized("已记录摄入", locale: locale)))
                            .foregroundStyle(by: .value(interfaceLocalized("系列", locale: locale), interfaceLocalized("已记录摄入", locale: locale)))
                        }
                        if let expenditure = point.estimatedExpenditureKcal {
                            BarMark(
                                x: .value(interfaceLocalized("日期", locale: locale), point.dayStart, unit: .day),
                                y: .value(interfaceLocalized("千卡", locale: locale), expenditure)
                            )
                            .position(by: .value(interfaceLocalized("系列", locale: locale), interfaceLocalized("估算消耗", locale: locale)))
                            .foregroundStyle(by: .value(interfaceLocalized("系列", locale: locale), interfaceLocalized("估算消耗", locale: locale)))
                        }
                    }
                }
                .chartForegroundStyleScale([
                    interfaceLocalized("已记录摄入", locale: locale): Color.orange,
                    interfaceLocalized("估算消耗", locale: locale): Color.blue,
                ])
                .chartLegend(position: .bottom)
                .chartXAxis { dateAxis }
                .frame(height: 220)
                .accessibilityLabel(
                    "\(interfaceLocalized(selectedRange.label, locale: locale)) \(interfaceLocalized("每日摄入与估算消耗", locale: locale))"
                )
            }

            chartCard(title: "每日估算能量差") {
                Chart {
                    RuleMark(y: .value(interfaceLocalized("平衡", locale: locale), 0))
                        .foregroundStyle(.secondary)
                    ForEach(visibleResult.points) { point in
                        if let balance = point.energyBalanceKcal {
                            BarMark(
                                x: .value(interfaceLocalized("日期", locale: locale), point.dayStart, unit: .day),
                                y: .value(interfaceLocalized("能量差", locale: locale), balance)
                            )
                            .foregroundStyle(balance >= 0 ? .green : .red)
                            .accessibilityLabel(
                                "\(point.dayStart.formatted(.dateTime.month().day().locale(locale))), "
                                    + interfaceLocalized(balance >= 0 ? "缺口" : "盈余", locale: locale)
                                    + " "
                                    + interfaceCalorieText(abs(balance).kcalText, locale: locale)
                            )
                        }
                    }
                }
                .chartXAxis { dateAxis }
                .frame(height: 180)
                .accessibilityLabel(
                    "\(interfaceLocalized(selectedRange.label, locale: locale)) \(interfaceLocalized("每日估算能量差", locale: locale))"
                )
                Text("今天尚未结束，不进入能量差与本周累计。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var macroChart: some View {
        let points = visibleResult.points
        return chartCard(
            title: "\(interfaceLocalized(selectedMetric.label, locale: locale)) \(interfaceLocalized("趋势", locale: locale))"
        ) {
            Chart {
                ForEach(points) { point in
                    if let value = macroValue(for: point) {
                        BarMark(
                            x: .value(interfaceLocalized("日期", locale: locale), point.dayStart, unit: .day),
                            y: .value(interfaceLocalized("克", locale: locale), value)
                        )
                        .foregroundStyle(selectedMetric.color)
                        .opacity(
                            max(0.3, point.completeMacroCoverage ?? 0.3)
                        )
                        .accessibilityLabel(
                            "\(point.dayStart.formatted(.dateTime.month().day().locale(locale))), "
                                + "\(interfaceLocalized(selectedMetric.label, locale: locale)) \(value.formatted(.number.precision(.fractionLength(0)))) \(interfaceLocalized("克", locale: locale)), "
                                + coverageAccessibility(point.completeMacroCoverage)
                        )
                    }
                }
            }
            .chartXAxis { dateAxis }
            .frame(height: 260)
            .accessibilityLabel(
                "\(interfaceLocalized(selectedRange.label, locale: locale)) \(interfaceLocalized(selectedMetric.label, locale: locale)) \(interfaceLocalized("趋势", locale: locale))"
            )

            Text("柱子越浅，代表当天宏量营养数据越不完整；未知值不会按 0 计算。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var coverageCard: some View {
        let visible = visibleResult.points
        let foodDays = visible.filter { $0.foodEntryCount > 0 }.count
        let energyDays = visible.filter {
            $0.estimatedExpenditureKcal != nil
        }.count
        let macroDays = visible.filter {
            ($0.completeMacroCoverage ?? 0) >= 0.8
        }.count
        let fallbackWeightDays = visible.filter {
            $0.weightSource == .goalProfileFallback
        }.count
        let calibratedBodyFatDays = visible.filter {
            $0.bodyFatSource == .calibratedProfile
        }.count

        return VStack(alignment: .leading, spacing: 8) {
            Label("数据覆盖", systemImage: "checkmark.shield")
                .font(.subheadline.bold())
            Text(coverageText(
                foodDays: foodDays,
                energyDays: energyDays,
                macroDays: macroDays,
                totalDays: visible.count
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("结果会随 Apple 健康延迟同步而更新，只代表已记录数据，不是精密代谢测量。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if fallbackWeightDays > 0 {
                Text("部分日期缺少历史体重，已使用档案起始体重估算。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if calibratedBodyFatDays > 0 {
                Text("部分日期使用了有日期依据的校准体脂估算基础代谢。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let loadError {
                Text(refreshFailureText(loadError))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func refreshFailureText(_ message: String) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Latest refresh failed: \(message)"
        case .traditionalChinese:
            return "最近重新整理失敗：\(message)"
        case .simplifiedChinese, .system:
            return "最近刷新失败：\(message)"
        }
    }

    @AxisContentBuilder
    private var dateAxis: some AxisContent {
        let stride = selectedRange == .sevenDays ? 1 : 7
        AxisMarks(values: .stride(by: .day, count: stride)) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month().day())
        }
    }

    private func chartCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(interfaceLocalized(title, locale: locale)).font(.subheadline.bold())
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func macroValue(for point: DailyHistoricalTrendPoint) -> Double? {
        switch selectedMetric {
        case .energy: return nil
        case .protein: return point.proteinG
        case .carbs: return point.carbsG
        case .fat: return point.fatG
        }
    }

    private func coverageAccessibility(_ coverage: Double?) -> String {
        guard let coverage else {
            return interfaceLocalized("营养数据完整度未知", locale: locale)
        }
        let percentage = Int((coverage * 100).rounded())
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Nutrition data completeness \(percentage)%"
        case .traditionalChinese:
            return "營養資料完整度 \(percentage)%"
        case .simplifiedChinese, .system:
            return "营养数据完整度 \(percentage)%"
        }
    }

    private var weeklyCoverageText: String {
        let eligible = "\(weeklySummary.eligibleDayCount)/\(weeklySummary.completedDayCount)"
        let food = "\(weeklySummary.foodRecordedDayCount)/\(weeklySummary.completedDayCount)"
        let expenditure =
            "\(weeklySummary.expenditureKnownDayCount)/\(weeklySummary.completedDayCount)"
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(eligible) days calculable · \(food) days with food logs · \(expenditure) days with expenditure estimates"
        case .traditionalChinese:
            return "\(eligible) 天可計算 · \(food) 天有飲食記錄 · \(expenditure) 天有消耗估算"
        case .simplifiedChinese, .system:
            return "\(eligible) 天可计算 · \(food) 天有饮食记录 · \(expenditure) 天有消耗估算"
        }
    }

    private func coverageText(
        foodDays: Int,
        energyDays: Int,
        macroDays: Int,
        totalDays: Int
    ) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(foodDays)/\(totalDays) days with food logs · \(energyDays)/\(totalDays) days with expenditure estimates · \(macroDays)/\(totalDays) days with at least 80% macro coverage"
        case .traditionalChinese:
            return "\(foodDays)/\(totalDays) 天有飲食記錄 · \(energyDays)/\(totalDays) 天有消耗估算 · \(macroDays)/\(totalDays) 天宏量覆蓋至少 80%"
        case .simplifiedChinese, .system:
            return "\(foodDays)/\(totalDays) 天有饮食记录 · \(energyDays)/\(totalDays) 天有消耗估算 · \(macroDays)/\(totalDays) 天宏量覆盖至少 80%"
        }
    }

    @MainActor
    private func reload() async {
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        do {
            let loadedResult = try await HistoricalTrendLoader.load(
                days: HistoricalTrendRange.thirtyDays.rawValue,
                profile: profile,
                health: health,
                foods: foods,
                exercises: exercises,
                localWeights: localWeights
            )
            guard loadRequestID == requestID else { return }
            result = loadedResult
            loadError = nil
        } catch {
            guard loadRequestID == requestID else { return }
            loadError = interfaceLocalized("请稍后重试", locale: locale)
        }
        guard loadRequestID == requestID else { return }
        isLoading = false
    }
}
