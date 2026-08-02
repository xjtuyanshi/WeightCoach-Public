import Charts
import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \FoodEntry.date, order: .reverse) private var allFoods: [FoodEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var localWeights: [WeightEntry]
    @Query(sort: \ExerciseEntry.startDate, order: .reverse) private var allExercises: [ExerciseEntry]

    @State private var showAIScan = false
    @State private var showSentenceBackfill = false
    @State private var showBarcodeScan = false
    @State private var showCommonFoodSearch = false
    @State private var repeatingFoodKey: String?
    @State private var undoEntry: FoodEntry?
    @State private var repeatMessage: String?
    @State private var repeatError: String?
    @State private var isUndoingRepeat = false
    @State private var weeklyTrendResult = HistoricalTrendResult(points: [])
    @State private var weeklyTrendError: String?
    @State private var weeklyTrendRequestID = UUID()
    @State private var showTrends = false

    // MARK: - 数据合成

    private var todayFoods: [FoodEntry] {
        allFoods.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayMetrics: TodayBudgetMetrics {
        TodayBudgetMetrics.calculate(
            profile: profile,
            health: health,
            todayFoods: todayFoods,
            localWeights: localWeights,
            exercises: allExercises
        )
    }

    private var currentWeight: Double { todayMetrics.currentWeight }
    private var bmr: Double { todayMetrics.bmr }
    private var tdee: Double { todayMetrics.tdee }
    private var deficit: Double { todayMetrics.deficit }
    private var budget: Double { todayMetrics.budget }
    private var consumed: Double { todayMetrics.consumed }
    private var nutritionMetrics: TodayNutritionMetrics {
        TodayNutritionMetrics.calculate(foods: todayFoods)
    }
    private var caffeineMetrics: TodayCaffeineMetrics {
        TodayCaffeineMetrics.calculate(foods: todayFoods)
    }
    private var macroTargets: DailyMacroTargets? {
        MacroTargetEngine.calculate(
            currentWeightKg: currentWeight,
            budgetKcal: budget,
            dayStyle: profile.macroDayStyle()
        )
    }

    private var goalProgress: Double {
        let total = profile.goalStartWeight - profile.goalWeight
        guard total > 0 else { return 1 }
        return min(max((profile.goalStartWeight - currentWeight) / total, 0), 1)
    }

    private var weeklyTrendRefreshKey: String {
        let calibration =
            profile.bodyComposition.calibratedBodyFatPercent
        let components: [String] = [
            String(allFoods.count),
            allFoods.first?.date.timeIntervalSinceReferenceDate.description ?? "-",
            String(allExercises.count),
            allExercises.first?.startDate.timeIntervalSinceReferenceDate.description ?? "-",
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    quickLoggingCard

                    if let macroTargets {
                        MacroSummaryView(
                            metrics: nutritionMetrics,
                            targets: macroTargets,
                            consumedKcal: consumed,
                            allowsTrainingAdjustment: profile.trainingFuelAdjustmentEnabled
                        ) { style in
                            profile.setMacroDayStyle(style)
                        }
                    }

                    weeklyTrendCard

                    EnergyExpenditureCard(
                        bmrKcal: bmr,
                        healthActiveEnergyKcal: todayMetrics.healthActiveEnergy,
                        manualExerciseEstimatedKcal: todayMetrics.manualExerciseEstimatedEnergy,
                        manualExerciseHealthOverlapKcal: todayMetrics.manualExerciseHealthOverlap,
                        manualExerciseSupplementKcal: todayMetrics.manualExerciseSupplementalEnergy,
                        tdeeKcal: tdee,
                        deficitKcal: deficit,
                        budgetKcal: budget,
                        activityFactor: profile.activityFactor,
                        includeActiveEnergy: profile.includeActiveEnergy
                    )

                    CaffeineSummaryCard(metrics: caffeineMetrics)

                    goalCard

                    if (!health.isAvailable || health.latestWeightKg == nil) && !DemoMode.isActive {
                        healthHintCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshHealthAndReminders() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable { await refreshHealthAndReminders() }
            .task {
                await refreshHealthAndReminders()
                if DemoMode.demoCommonFoodEnabled
                    || DemoMode.demoFoodAutocompleteEnabled
                    || DemoMode.demoStarbucksEnabled {
                    showCommonFoodSearch = true
                }
                if DemoMode.demoTrendsEnabled {
                    showTrends = true
                }
                if DemoMode.demoSentenceBackfillEnabled {
                    showSentenceBackfill = true
                }
            }
            .task(id: weeklyTrendRefreshKey) {
                await reloadWeeklyTrends()
            }
            .navigationDestination(isPresented: $showTrends) {
                NutritionTrendsView()
            }
            .sheet(isPresented: $showSentenceBackfill) {
                SentenceFoodBackfillView(defaultDate: .now)
            }
            .sheet(isPresented: $showAIScan) { AIFoodScanView(defaultDate: .now) }
            .sheet(isPresented: $showBarcodeScan) { BarcodeScanView(defaultDate: .now) }
            .sheet(isPresented: $showCommonFoodSearch) {
                CommonFoodSearchView(
                    defaultDate: .now,
                    demoFoodID: DemoMode.demoCommonFoodEnabled ? "egg-hard-boiled" : nil,
                    demoQuery: DemoMode.demoFoodAutocompleteEnabled ? "西" : nil
                )
            }
            .safeAreaInset(edge: .bottom) {
                if let repeatMessage {
                    repeatToast(repeatMessage)
                }
            }
            .alert(
                "快捷记录失败",
                isPresented: Binding(
                    get: { repeatError != nil },
                    set: { if !$0 { repeatError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(interfaceLocalized(repeatError ?? "请稍后重试", locale: locale))
            }
        }
    }

    @MainActor
    private func refreshHealthAndReminders() async {
        await health.refreshAll()
        await reloadWeeklyTrends()
        await reminders.reconcile(
            context: modelContext,
            profile: profile,
            latestHealthWeightDate: health.latestWeightDate
        )
    }

    private var quickLoggingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("快速记录", systemImage: "bolt.fill")
                .font(.headline)

            Button {
                showSentenceBackfill = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble.fill")
                        .font(.title3)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(interfaceLocalized("一句话补记", locale: locale))
                            .font(.subheadline.bold())
                        Text(interfaceLocalized("例如：1 根烤肠、2 个鸡翅", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            quickAddButtons

            if !repeatFoodCards.isEmpty {
                Divider()
                repeatFoodSuggestionsSection
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var quickAddButtons: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    photoQuickButton
                    barcodeQuickButton
                    manualQuickButton
                }
            } else if AppLanguage.system.resolvedLanguage(systemLocale: locale) == .english {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        photoQuickButton
                        barcodeQuickButton
                    }
                    manualQuickButton
                }
            } else {
                HStack(spacing: 12) {
                    photoQuickButton
                    barcodeQuickButton
                    manualQuickButton
                }
            }
        }
    }

    private var photoQuickButton: some View {
        quickButton("拍照识别", icon: "camera.viewfinder") { showAIScan = true }
    }

    private var barcodeQuickButton: some View {
        quickButton("扫条形码", icon: "barcode.viewfinder") { showBarcodeScan = true }
    }

    private var manualQuickButton: some View {
        quickButton("自行填写", icon: "magnifyingglass") {
            showCommonFoodSearch = true
        }
    }

    private var weeklyTrendCard: some View {
        let summary = weeklyTrendResult.weeklySummary(
            referenceDate: DemoMode.demoTrendsEnabled
                ? DemoMode.trendReferenceDate()
                : .now,
            calendar: .current
        )
        let chartPoints = weeklyTrendResult.points.filter {
            $0.isCompleteDay && $0.energyBalanceKcal != nil
        }

        return Button {
            showTrends = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("本周能量账本", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if let balance = summary.cumulativeEnergyBalanceKcal {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(interfaceLocalized(balance >= 0 ? "估算缺口" : "估算盈余", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(abs(balance).kcalText)
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(balance >= 0 ? .green : .red)
                        Text("千卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if weeklyTrendError != nil {
                    Text("趋势读取失败，点此重试")
                        .font(.subheadline.bold())
                } else {
                    Text("数据不足，暂不能计算")
                        .font(.subheadline.bold())
                }

                if !chartPoints.isEmpty {
                    Chart(chartPoints) { point in
                        if let balance = point.energyBalanceKcal {
                            BarMark(
                                x: .value(interfaceLocalized("日期", locale: locale), point.dayStart, unit: .day),
                                y: .value(interfaceLocalized("能量差", locale: locale), balance)
                            )
                            .foregroundStyle(balance >= 0 ? .green : .red)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 54)
                    .accessibilityHidden(true)
                }

                Text(weeklyCoverageText(summary))
                .font(.caption)
                .foregroundStyle(.secondary)
                if weeklyTrendError != nil,
                   summary.cumulativeEnergyBalanceKcal != nil {
                    Text("最近刷新失败，当前周数据可能已过期；点开趋势页可重试。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text("正数为缺口，负数为盈余；只统计已记录且数据可用的日期。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开近 7 天和近 30 天详细趋势")
    }

    @MainActor
    private func reloadWeeklyTrends() async {
        let requestID = UUID()
        weeklyTrendRequestID = requestID
        do {
            let result = try await HistoricalTrendLoader.load(
                days: 7,
                profile: profile,
                health: health,
                foods: allFoods,
                exercises: allExercises,
                localWeights: localWeights
            )
            guard weeklyTrendRequestID == requestID else { return }
            weeklyTrendResult = result
            weeklyTrendError = nil
        } catch {
            guard weeklyTrendRequestID == requestID else { return }
            weeklyTrendError = "趋势读取失败，点此重试"
        }
    }

    private struct RepeatFoodCard: Identifiable {
        let food: FoodEntry
        let suggestion: FoodRepeatSuggestion

        var id: String { suggestion.key }
    }

    private var repeatFoodCards: [RepeatFoodCard] {
        let snapshots = allFoods.enumerated().map { index, food in
            FoodRepeatSuggestionSnapshot(
                sourceIndex: index,
                key: repeatKey(for: food),
                date: food.date
            )
        }
        let suggestions = FoodRepeatSuggestionEngine.makeSuggestions(
            snapshots: snapshots
        )
        return suggestions.all.compactMap { suggestion in
            guard allFoods.indices.contains(suggestion.sourceIndex) else {
                return nil
            }
            return RepeatFoodCard(
                food: allFoods[suggestion.sourceIndex],
                suggestion: suggestion
            )
        }
    }

    private var repeatFoodSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                Label("常吃与最近 · 点一下直接记", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.bold())
                Text("按上次份量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("常吃与最近 · 点一下直接记", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("按上次份量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(repeatFoodCards.indices, id: \.self) { index in
                        repeatFoodButton(repeatFoodCards[index])
                    }
                }
            }
        }
    }

    private func repeatFoodButton(_ card: RepeatFoodCard) -> some View {
        let food = card.food
        let key = repeatKey(for: food)
        return Button {
            repeatFood(food)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(
                        card.suggestion.isFrequent
                            ? interfaceLocalized("常吃", locale: locale)
                            : interfaceLocalized("最近", locale: locale),
                        systemImage: card.suggestion.isFrequent
                            ? "star.fill"
                            : "clock"
                    )
                    .font(.caption2.bold())
                    .foregroundStyle(
                        card.suggestion.isFrequent
                            ? Color.accentColor
                            : Color.secondary
                    )
                    Spacer()
                    if repeatingFoodKey == key {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(food.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(
                    food.portionText
                        ?? interfaceLocalized("按上次记录", locale: locale)
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(
                    interfaceCalorieText(
                        food.calories.kcalText,
                        locale: locale
                    )
                )
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                if card.suggestion.isFrequent {
                    Text(
                        repeatFrequencyText(
                            dayCount: card.suggestion.distinctDayCount
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
            }
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 240 : 150,
                alignment: .topLeading
            )
            .frame(
                minHeight: dynamicTypeSize.isAccessibilitySize ? 180 : 105,
                alignment: .topLeading
            )
            .padding(12)
            .background(
                card.suggestion.isFrequent
                    ? Color.accentColor.opacity(0.08)
                    : Color(.secondarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(repeatingFoodKey != nil || isUndoingRepeat)
        .accessibilityLabel(
            repeatFoodAccessibilityLabel(
                food,
                suggestion: card.suggestion
            )
        )
    }

    private func repeatToast(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            if undoEntry != nil {
                Button {
                    undoQuickRepeat()
                } label: {
                    if isUndoingRepeat {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("撤销")
                    }
                }
                .font(.subheadline.bold())
                .disabled(isUndoingRepeat)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6, y: 2)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func repeatFood(_ food: FoodEntry) {
        let key = repeatKey(for: food)
        guard repeatingFoodKey == nil, !isUndoingRepeat else { return }
        repeatingFoodKey = key
        repeatMessage = nil
        undoEntry = nil
        let now = Date()
        let draft = FoodEntryDraft(
            repeating: food,
            date: now,
            mealType: MealType.suggested(for: now)
        )
        Task { @MainActor in
            do {
                let saved = try await FoodEntryWriter.save(
                    drafts: [draft],
                    context: modelContext,
                    health: health,
                    reminders: reminders
                )
                undoEntry = saved.first
                repeatMessage = recordedFoodMessage(food.name)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                repeatError = error.localizedDescription
            }
            repeatingFoodKey = nil
        }
    }

    private func undoQuickRepeat() {
        guard let entry = undoEntry, !isUndoingRepeat else { return }
        isUndoingRepeat = true
        Task { @MainActor in
            do {
                try await FoodEntryWriter.delete(
                    entry,
                    context: modelContext,
                    health: health
                )
                undoEntry = nil
                repeatMessage = interfaceLocalized("已撤销", locale: locale)
                await reminders.reconcile(
                    context: modelContext,
                    profile: profile,
                    latestHealthWeightDate: health.latestWeightDate
                )
            } catch {
                repeatError = error.localizedDescription
            }
            isUndoingRepeat = false
        }
    }

    private func repeatKey(for food: FoodEntry) -> String {
        FoodRepeatIdentity.key(
            productID: food.foodProductID,
            barcode: food.barcode,
            // 一键再记会把来源改成 quickRepeat；身份不能依赖 source，
            // 否则同一条参考库食物会被拆成「reference」和「name」两组。
            referenceCatalogID: CommonFoodCatalog.referenceID(
                forStoredName: food.name
            ),
            name: food.name
        )
    }

    private func quickButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(interfaceLocalized(title, locale: locale))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(Color.accentColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("减重目标", systemImage: "flag.checkered")
                    .font(.subheadline.bold())
                Spacer()
                Text(remainingDaysText(profile.remainingDays))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: goalProgress)
                .tint(.accentColor)
            HStack {
                Text("\(profile.goalStartWeight.kgText) kg")
                Spacer()
                Text(currentWeightText(currentWeight))
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("\(profile.goalWeight.kgText) kg")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            let lost = profile.goalStartWeight - currentWeight
            let toGo = currentWeight - profile.goalWeight
            // 实际缺口：预算触及安全底线时会小于目标缺口
            let effectiveDeficit = max(0, tdee - budget)
            Text(goalProgressText(lost: lost, toGo: toGo, effectiveDeficit: effectiveDeficit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var healthHintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("连接 Apple 健康", systemImage: "heart.text.square")
                .font(.subheadline.bold())
            Text(
                interfaceLocalized(
                    health.authorizationErrorDescription != nil
                        ? "无法请求 Apple 健康授权。请到系统设置检查权限后重试。"
                        : health.isAvailable
                        ? "尚未读取到体重数据。请确认已授权本 App 读取健康数据（设置 → 健康 → 数据访问与设备），或在「体重」页手动记录一次。"
                        : "当前设备不支持 HealthKit，将使用手动记录的数据。",
                    locale: locale
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重新请求授权") {
                Task { @MainActor in
                    await health.requestAuthorization()
                    await reminders.reconcile(
                        context: modelContext,
                        profile: profile,
                        latestHealthWeightDate: health.latestWeightDate
                    )
                }
            }
            .font(.caption.bold())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func weeklyCoverageText(_ summary: HistoricalTrendWeeklySummary) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Through yesterday · \(summary.eligibleDayCount) of \(summary.completedDayCount) days calculable"
        case .traditionalChinese:
            return "截至昨天 · \(summary.eligibleDayCount)/\(summary.completedDayCount) 天可計算"
        case .simplifiedChinese, .system:
            return "截至昨天 · \(summary.eligibleDayCount)/\(summary.completedDayCount) 天可计算"
        }
    }

    private func recordedFoodMessage(_ name: String) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Logged \(name)"
        case .traditionalChinese:
            return "已記錄 \(name)"
        case .simplifiedChinese, .system:
            return "已记录 \(name)"
        }
    }

    private func repeatFoodAccessibilityLabel(
        _ food: FoodEntry,
        suggestion: FoodRepeatSuggestion
    ) -> String {
        let calories = interfaceCalorieText(food.calories.kcalText, locale: locale)
        let portion = food.portionText
            ?? interfaceLocalized("按上次记录", locale: locale)
        let status = suggestion.isFrequent
            ? "\(interfaceLocalized("常吃", locale: locale))，\(repeatFrequencyText(dayCount: suggestion.distinctDayCount))"
            : interfaceLocalized("最近", locale: locale)
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(status). Log \(food.name) again, \(portion), \(calories)"
        case .traditionalChinese:
            return "\(status)。再次記錄\(food.name)，\(portion)，\(calories)"
        case .simplifiedChinese, .system:
            return "\(status)。再次记录\(food.name)，\(portion)，\(calories)"
        }
    }

    private func repeatFrequencyText(dayCount: Int) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(dayCount) days in the last 30"
        case .traditionalChinese:
            return "近 30 天吃過 \(dayCount) 天"
        case .simplifiedChinese, .system:
            return "近 30 天吃过 \(dayCount) 天"
        }
    }

    private func remainingDaysText(_ days: Int) -> String {
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "\(days) days left"
        case .traditionalChinese, .simplifiedChinese, .system:
            return "剩 \(days) 天"
        }
    }

    private func currentWeightText(_ weight: Double) -> String {
        let value = "\(weight.kgText) kg"
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Current \(value)"
        case .traditionalChinese:
            return "目前 \(value)"
        case .simplifiedChinese, .system:
            return "当前 \(value)"
        }
    }

    private func goalProgressText(
        lost: Double,
        toGo: Double,
        effectiveDeficit: Double
    ) -> String {
        if toGo <= 0 {
            return interfaceLocalized("🎉 已达成目标！继续保持", locale: locale)
        }

        let lostText = String(format: "%.1f", max(0, lost))
        let toGoText = String(format: "%.1f", toGo)
        let weeklyText = String(
            format: "%.1f",
            effectiveDeficit * 7 / CalorieEngine.kcalPerKg
        )
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Lost \(lostText) kg, \(toGoText) kg to go. At the current deficit, about \(weeklyText) kg per week."
        case .traditionalChinese:
            return "已減 \(lostText) kg，還差 \(toGoText) kg。按目前缺口約每週減 \(weeklyText) kg"
        case .simplifiedChinese, .system:
            return "已减 \(lostText) kg，还差 \(toGoText) kg。按当前缺口约每周减 \(weeklyText) kg"
        }
    }
}
