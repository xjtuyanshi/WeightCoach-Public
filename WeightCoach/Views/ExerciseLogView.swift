import SwiftUI
import SwiftData

/// 不戴 Apple Watch 时补记运动。
///
/// 手动记录只保存在 App 内；仪表盘会按时间扣除 Apple 健康已经记录的活动能量，
/// 因此健康样本稍后同步到手机时，补差会自动减少。
struct ExerciseLogView: View {
    private struct ExerciseDeletionAlert: Identifiable {
        enum Content {
            case confirmation(ExerciseEntry)
            case failure(String)
        }

        let id = UUID()
        let content: Content
    }

    @EnvironmentObject private var profile: ProfileStore
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseEntry.startDate, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var localWeights: [WeightEntry]

    @State private var showAddExercise = false
    @State private var addExerciseInitialType: ExerciseActivityType =
        DemoMode.demoThirdPartyExerciseEnabled ? .running : .basketball
    @State private var deletionAlert: ExerciseDeletionAlert?
    @Environment(\.locale) private var locale

    private var todayInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    private var todayExercises: [ExerciseEntry] {
        exercises.filter {
            $0.startDate < todayInterval.end && $0.endDate > todayInterval.start
        }
    }

    private var todaySummary: ManualExerciseSupplement {
        let calculated = ManualExerciseSupplementEngine.calculateTotal(
            exercises: todayExercises.map(\.energyInterval),
            healthSamples: health.todayActiveEnergyIntervals.map(HealthActiveEnergySample.init),
            healthWorkouts: health.todayWorkoutIntervals,
            within: todayInterval
        )
        guard profile.includeActiveEnergy,
              !todayExercises.isEmpty,
              !health.todayWorkoutCoverageAvailable else {
            return calculated
        }
        return ManualExerciseSupplement(
            estimatedActiveEnergyKcal: calculated.estimatedActiveEnergyKcal,
            overlappingHealthEnergyKcal: 0,
            supplementalActiveEnergyKcal: 0
        )
    }

    private var currentWeight: Double {
        let healthWeight: (date: Date, value: Double)? = {
            guard let value = health.latestWeightKg, let date = health.latestWeightDate else {
                return nil
            }
            return (date, value)
        }()
        let localWeight = localWeights.first.map { (date: $0.date, value: $0.weightKg) }

        switch (healthWeight, localWeight) {
        case let (health?, local?):
            return health.date >= local.date ? health.value : local.value
        case let (health?, nil):
            return health.value
        case let (nil, local?):
            return local.value
        default:
            return profile.goalStartWeight
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    todaySummaryCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section("Apple 健康活动") {
                    LabeledContent(
                        "今日步数",
                        value: interfaceStepText(health.todaySteps, locale: locale)
                    )

                    if HealthActivityGuidance.shouldSuggestManualWalking(
                        steps: health.todaySteps,
                        hasActiveEnergySamples: !health.todayActiveEnergyIntervals.isEmpty,
                        includeActiveEnergy: profile.includeActiveEnergy
                    ) {
                        Label(
                            "手机已记录步数，但 Apple 健康今天没有提供活动能量；步数不会自动换算为热量。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    if HealthActivityGuidance.shouldOfferManualWalking(
                        steps: health.todaySteps,
                        includeActiveEnergy: profile.includeActiveEnergy
                    ) {
                        Button {
                            addExerciseInitialType = .walking
                            showAddExercise = true
                        } label: {
                            Label("补记运动", systemImage: "figure.walk")
                        }
                        .accessibilityIdentifier("exercise-log.add-exercise")
                    }

                    if profile.includeActiveEnergy,
                       !todayExercises.isEmpty,
                       !health.todayWorkoutCoverageAvailable {
                        Label(
                            "无法核对 Apple 健康运动记录，手动补记暂不计入热量预算。请刷新后重试。",
                            systemImage: "exclamationmark.shield.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier(
                            "exercise-log.coverage-unavailable"
                        )
                    }
                }

                Section {
                    Label {
                        Text("只补记 Apple 健康没有完整记录的运动。稍后同步到的健康数据会自动从补差中扣除。")
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }

                    Label {
                        Text("请填写实际运动时长；力量训练可包含正常组间休息，但应排除长时间停顿。")
                    } icon: {
                        Image(systemName: "timer")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("避免重复计算")
                } footer: {
                    Text("手动记录不会写回 Apple 健康。热量是基于体重与运动强度的群体估算，不是精密测量。")
                }

                if exercises.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "还没有运动补记",
                            systemImage: "figure.run.circle",
                            description: Text("不戴手表运动后，点右上角 + 记录篮球、跑步、走路或力量训练")
                        )
                    }
                } else {
                    Section("最近补记") {
                        ForEach(exercises.prefix(20)) { exercise in
                            exerciseRow(exercise)
                        }
                        .onDelete(perform: requestDeleteExercises)
                    }
                }
            }
            .navigationTitle("运动补记")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addExerciseInitialType = .basketball
                        showAddExercise = true
                    } label: {
                        Label("记录运动", systemImage: "plus")
                    }
                    .accessibilityIdentifier("exercise-log.add-exercise-toolbar")
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseView(
                    defaultWeightKg: currentWeight,
                    existingExercises: exercises,
                    initialActivityType: addExerciseInitialType
                )
            }
            .task {
                if !DemoMode.isActive {
                    await health.refreshAll()
                }
                if DemoMode.demoThirdPartyExerciseEnabled {
                    addExerciseInitialType = .running
                    showAddExercise = true
                } else if DemoMode.demoExerciseEnabled
                    || DemoMode.demoExerciseHealthQueryFailureEnabled {
                    showAddExercise = true
                }
            }
            .refreshable {
                if !DemoMode.isActive {
                    await health.refreshAll()
                }
            }
            .alert(item: $deletionAlert) { alert in
                switch alert.content {
                case let .confirmation(exercise):
                    return Alert(
                        title: Text("删除这条运动补记？"),
                        message: Text(deletionConfirmationMessage(for: exercise)),
                        primaryButton: .destructive(Text("删除")) {
                            deleteExercise(exercise)
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                case let .failure(message):
                    return Alert(
                        title: Text("删除失败"),
                        message: Text(message),
                        dismissButton: .cancel(Text("好"))
                    )
                }
            }
        }
    }

    private var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("今天的手动运动", systemImage: "figure.basketball")
                    .font(.headline)
                Spacer()
                Text(interfaceLocalized(
                    profile.includeActiveEnergy ? "自动去重" : "仅展示",
                    locale: locale
                ))
                    .font(.caption.bold())
                    .foregroundStyle(profile.includeActiveEnergy ? Color.green : Color.secondary)
            }

            HStack(spacing: 8) {
                summaryValue(
                    "估算活动",
                    value: todaySummary.estimatedActiveEnergyKcal,
                    color: .orange
                )
                if todaySummary.usedHealthWorkoutCoverage {
                    summaryDuration(
                        "健康覆盖",
                        minutes: todaySummary.healthWorkoutCoveredMinutes,
                        color: .blue
                    )
                } else {
                    summaryValue(
                        "健康已记",
                        value: todaySummary.overlappingHealthEnergyKcal,
                        color: .blue
                    )
                }
                summaryValue(
                    profile.includeActiveEnergy ? "实际补入" : "未计入预算",
                    value: todaySummary.supplementalActiveEnergyKcal,
                    color: profile.includeActiveEnergy ? .green : .secondary
                )
            }

            if !profile.includeActiveEnergy {
                Text("设置中当前使用活动系数模式，手动运动不会额外增加今天的热量预算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func summaryValue(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(interfaceLocalized(title, locale: locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(value.kcalText)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text("千卡")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryDuration(
        _ title: String,
        minutes: Double,
        color: Color
    ) -> some View {
        VStack(spacing: 3) {
            Text(interfaceLocalized(title, locale: locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(Int(minutes.rounded()))")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(interfaceLocalized("分钟", locale: locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseRow(_ exercise: ExerciseEntry) -> some View {
        let todaySupplement = supplementForToday(exercise)
        let primaryEnergy = todaySupplement?.supplementalActiveEnergyKcal
            ?? exercise.estimatedActiveEnergyKcal
        let primaryLabel: String
        if todaySupplement == nil {
            primaryLabel = "MET 估算"
        } else if profile.includeActiveEnergy {
            primaryLabel = "实际补入"
        } else {
            primaryLabel = "未计入预算"
        }

        return HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: exercise.activityType?.systemImage ?? "figure.run")
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.displayName(locale: locale))
                        .font(.subheadline.bold())
                    Text(
                        "\(exercise.startDate.formatted(.dateTime.month().day().hour().minute().locale(locale))) · \(Int(exercise.durationMinutes.rounded())) \(interfaceLocalized("分钟", locale: locale))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(
                        "MET \(exercise.metSnapshot, format: .number.precision(.fractionLength(1))) · \(interfaceLocalized("按", locale: locale)) \(exercise.weightKgSnapshot.kgText) kg"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(primaryEnergy.kcalText)
                        .font(.headline.monospacedDigit())
                    Text(interfaceLocalized(primaryLabel, locale: locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if todaySupplement != nil {
                        Text(
                            "\(interfaceLocalized("MET 估算", locale: locale)) \(exercise.estimatedActiveEnergyKcal.kcalText)"
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Button(role: .destructive) {
                requestDeletion(of: exercise)
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(deletionAccessibilityLabel(for: exercise))
            .accessibilityHint("删除后会立即从相关日期的运动统计中移除；若已计入热量预算，预算也会同步更新。此操作无法撤销。")
            .accessibilityIdentifier(
                "exercise.delete-\(exercise.startDate.timeIntervalSince1970)"
            )
        }
    }

    private func supplementForToday(
        _ exercise: ExerciseEntry
    ) -> ManualExerciseSupplement? {
        guard exercise.startDate < todayInterval.end,
              exercise.endDate > todayInterval.start else {
            return nil
        }
        let calculated = ManualExerciseSupplementEngine.calculate(
            exercise: exercise.energyInterval,
            healthSamples: health.todayActiveEnergyIntervals.map(
                HealthActiveEnergySample.init
            ),
            healthWorkouts: health.todayWorkoutIntervals,
            within: todayInterval
        )
        guard profile.includeActiveEnergy,
              !health.todayWorkoutCoverageAvailable else {
            return calculated
        }
        return ManualExerciseSupplement(
            estimatedActiveEnergyKcal: calculated.estimatedActiveEnergyKcal,
            overlappingHealthEnergyKcal: 0,
            supplementalActiveEnergyKcal: 0
        )
    }

    private func deletionConfirmationMessage(for exercise: ExerciseEntry) -> String {
        let date = exercise.startDate.formatted(
            .dateTime.month().day().hour().minute().locale(locale)
        )
        let details = "\(exercise.displayName(locale: locale)) · \(date) · \(exercise.estimatedActiveEnergyKcal.kcalText) \(interfaceLocalized("MET 估算", locale: locale))"
        return "\(details)\n\(interfaceLocalized("删除后会立即从相关日期的运动统计中移除；若已计入热量预算，预算也会同步更新。此操作无法撤销。", locale: locale))"
    }

    private func deletionAccessibilityLabel(for exercise: ExerciseEntry) -> String {
        let date = exercise.startDate.formatted(
            .dateTime.month().day().hour().minute().locale(locale)
        )
        return "\(interfaceLocalized("删除运动补记", locale: locale))：\(exercise.displayName(locale: locale))，\(date)"
    }

    private func requestDeletion(of exercise: ExerciseEntry) {
        deletionAlert = ExerciseDeletionAlert(content: .confirmation(exercise))
    }

    private func requestDeleteExercises(at offsets: IndexSet) {
        let visible = Array(exercises.prefix(20))
        guard let exercise = offsets.compactMap({ index in
            visible.indices.contains(index) ? visible[index] : nil
        }).first else { return }
        requestDeletion(of: exercise)
    }

    private func deleteExercise(_ exercise: ExerciseEntry) {
        do {
            modelContext.delete(exercise)
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            modelContext.rollback()
            let message = interfaceLocalized("请稍后重试", locale: locale)
            Task { @MainActor in
                await Task.yield()
                deletionAlert = ExerciseDeletionAlert(content: .failure(message))
            }
        }
    }
}

private struct ExerciseCoverageQuery: Hashable {
    let startDate: Date
    let endDate: Date
    let estimatedActiveEnergyKcal: Double
    let activityTypeRaw: String

    var interval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }

    var exercise: ExerciseEnergyInterval {
        ExerciseEnergyInterval(
            startDate: startDate,
            endDate: endDate,
            estimatedActiveEnergyKcal: estimatedActiveEnergyKcal,
            activityType: ExerciseActivityType(rawValue: activityTypeRaw)
        )
    }
}

struct AddExerciseView: View {
    let defaultWeightKg: Double
    let existingExercises: [ExerciseEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health

    @State private var activityType: ExerciseActivityType
    @State private var intensity: ExerciseIntensity
    @State private var startDate = Date().addingTimeInterval(-3_600)
    @State private var draftStartDate = Date().addingTimeInterval(-3_600)
    @State private var isEditingStartDate = false
    @State private var durationMinutes = 60.0
    @State private var weightText = ""
    @State private var errorMessage: String?
    @State private var healthPreview: ManualExerciseSupplement?
    @State private var previewedCoverageQuery: ExerciseCoverageQuery?
    @State private var isCheckingHealthCoverage = false
    @State private var healthCoverageQueryFailed = false
    @State private var didInjectDemoHealthCoverageFailure = false
    @State private var isSaving = false
    @Environment(\.locale) private var locale

    init(
        defaultWeightKg: Double,
        existingExercises: [ExerciseEntry],
        initialActivityType: ExerciseActivityType = .basketball
    ) {
        self.defaultWeightKg = defaultWeightKg
        self.existingExercises = existingExercises
        _activityType = State(initialValue: initialActivityType)
        _intensity = State(
            initialValue: ExerciseIntensity.defaultIntensity(
                for: initialActivityType
            )
        )
    }

    private var weightKg: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    private var estimatedActiveEnergy: Double? {
        guard let weightKg else { return nil }
        return ExerciseEnergyEngine.estimateActiveEnergyKcal(
            intensity: intensity,
            weightKg: weightKg,
            durationMinutes: durationMinutes
        )
    }

    private var selectedStartDate: Date {
        isEditingStartDate ? draftStartDate : startDate
    }

    private var endDate: Date {
        selectedStartDate.addingTimeInterval(durationMinutes * 60)
    }

    private var hasManualExerciseOverlap: Bool {
        ManualExerciseSupplementEngine.overlaps(
            startDate: selectedStartDate,
            durationMinutes: durationMinutes,
            existingExercises: existingExercises.map(\.energyInterval)
        )
    }

    private var coverageQuery: ExerciseCoverageQuery? {
        guard let estimatedActiveEnergy,
              estimatedActiveEnergy.isFinite,
              estimatedActiveEnergy >= 0,
              endDate > selectedStartDate,
              endDate <= Date() else {
            return nil
        }
        return ExerciseCoverageQuery(
            startDate: selectedStartDate,
            endDate: endDate,
            estimatedActiveEnergyKcal: estimatedActiveEnergy,
            activityTypeRaw: intensity.activityType.rawValue
        )
    }

    private var hasCurrentHealthPreview: Bool {
        guard let coverageQuery else { return false }
        return previewedCoverageQuery == coverageQuery
            && healthPreview != nil
            && !healthCoverageQueryFailed
    }

    private var isFullyCoveredByHealthWorkout: Bool {
        guard hasCurrentHealthPreview,
              let coverageQuery,
              let healthPreview,
              healthPreview.usedHealthWorkoutCoverage else {
            return false
        }
        let coveredSeconds = healthPreview.healthWorkoutCoveredMinutes * 60
        return coveredSeconds >= coverageQuery.interval.duration - 1
    }

    private var canSave: Bool {
        estimatedActiveEnergy != nil
            && endDate <= Date()
            && !hasManualExerciseOverlap
            && hasCurrentHealthPreview
            && !isCheckingHealthCoverage
            && !healthCoverageQueryFailed
            && !isFullyCoveredByHealthWorkout
            && !isSaving
    }

    private var startDateText: String {
        selectedStartDate.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(locale)
        )
    }

    private var endDateText: String {
        endDate.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(locale)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("运动类型") {
                    Picker("类型", selection: $activityType) {
                        ForEach(ExerciseActivityType.allCases) { activity in
                            Label(
                                interfaceLocalized(activity.label, locale: locale),
                                systemImage: activity.systemImage
                            )
                                .tag(activity)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("exercise.activity-type")

                    Picker("强度", selection: $intensity) {
                        ForEach(ExerciseIntensity.presets(for: activityType)) { preset in
                            Text(interfaceLocalized(preset.label, locale: locale)).tag(preset)
                        }
                    }
                    .accessibilityIdentifier("exercise.intensity")

                    Text(interfaceLocalized(intensity.detail, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(interfaceLocalized(
                        activityType.durationGuidance,
                        locale: locale
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("时间与体重") {
                    Button {
                        if isEditingStartDate {
                            startDate = draftStartDate
                            errorMessage = nil
                            withAnimation {
                                isEditingStartDate = false
                            }
                        } else {
                            draftStartDate = startDate
                            withAnimation {
                                isEditingStartDate = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("开始时间")
                            Spacer()
                            Text(startDateText)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: isEditingStartDate ? "chevron.up" : "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exercise.start-time-editor")
                    .accessibilityLabel("开始时间")
                    .accessibilityValue(startDateText)
                    .accessibilityHint(
                        isEditingStartDate
                            ? "时间选择器已展开，双击可收起并采用当前选择。"
                            : "双击展开日期和时间选择器。"
                    )

                    if isEditingStartDate {
                        DatePicker(
                            "开始时间",
                            selection: $draftStartDate,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("exercise.start-time-wheel")

                        HStack {
                            Button("取消") {
                                draftStartDate = startDate
                                withAnimation {
                                    isEditingStartDate = false
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("exercise.start-time-cancel")

                            Spacer()

                            Button("完成") {
                                startDate = draftStartDate
                                errorMessage = nil
                                withAnimation {
                                    isEditingStartDate = false
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("exercise.start-time-done")
                        }
                        .buttonStyle(.borderless)
                    }

                    LabeledContent("预计结束时间", value: endDateText)
                        .accessibilityIdentifier("exercise.end-time")

                    Stepper(
                        "\(interfaceLocalized("活动时长", locale: locale)): \(Int(durationMinutes)) \(interfaceLocalized("分钟", locale: locale))",
                        value: $durationMinutes,
                        in: 10...600,
                        step: 5
                    )
                    .accessibilityIdentifier("exercise.duration")

                    HStack {
                        Text("当时体重")
                        Spacer()
                        TextField("kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    if hasManualExerciseOverlap {
                        Label(
                            "该时间段与另一条 App 手动补记重叠；请调整开始时间或活动时长。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("exercise.manual-overlap-message")
                    }

                    if endDate > Date() {
                        Text("结束时间不能晚于现在，请调整开始时间或活动时长。")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("exercise.future-end-message")
                    }
                }

                coveragePreviewSection

                if let errorMessage {
                    Section {
                        Text(interfaceLocalized(errorMessage, locale: locale))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("补记运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isSaving)
                        .accessibilityIdentifier("exercise.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .accessibilityLabel("保存中")
                        } else {
                            Text("保存")
                        }
                    }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!canSave)
                        .accessibilityIdentifier("exercise.save")
                }
            }
            .onAppear {
                weightText = String(format: "%.1f", defaultWeightKg)
            }
            .onChange(of: activityType) { _, newValue in
                intensity = ExerciseIntensity.defaultIntensity(for: newValue)
            }
            .onChange(of: durationMinutes) { _, _ in
                errorMessage = nil
            }
            .onChange(of: draftStartDate) { _, _ in
                errorMessage = nil
            }
            .task(id: coverageQuery) {
                guard let coverageQuery else {
                    healthPreview = nil
                    previewedCoverageQuery = nil
                    isCheckingHealthCoverage = false
                    healthCoverageQueryFailed = false
                    return
                }
                errorMessage = nil
                healthPreview = nil
                previewedCoverageQuery = coverageQuery
                healthCoverageQueryFailed = false
                isCheckingHealthCoverage = true
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    return
                }
                await refreshHealthCoverage(for: coverageQuery)
            }
        }
    }

    private var coveragePreviewSection: some View {
        Section {
            LabeledContent("MET 估算") {
                if let estimatedActiveEnergy {
                    Text(interfaceCalorieText(
                        estimatedActiveEnergy.kcalText,
                        locale: locale
                    ))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.orange)
                } else {
                    Text("--")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("exercise.met-estimate")

            coverageStatus
        } header: {
            Text("补记预览")
        } footer: {
            Text("采用 2024 Adult Compendium 的 MET 群体估算。Apple 健康已记录同类型运动时，App 会按覆盖分钟只补未记录部分；完整覆盖则不会保存。")
        }
    }

    @ViewBuilder
    private var coverageStatus: some View {
        if isCheckingHealthCoverage {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在核对 Apple 健康记录…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("exercise.health-coverage-loading")
        } else if hasCurrentHealthPreview, let healthPreview {
            LabeledContent("健康覆盖") {
                Text(
                    "\(Int(healthPreview.healthWorkoutCoveredMinutes.rounded())) \(interfaceLocalized("分钟", locale: locale))"
                )
                .monospacedDigit()
            }
            .accessibilityIdentifier("exercise.health-covered-minutes")

            LabeledContent("预计实际补入") {
                Text(interfaceCalorieText(
                    healthPreview.supplementalActiveEnergyKcal.kcalText,
                    locale: locale
                ))
                .font(.headline.monospacedDigit())
                .foregroundStyle(
                    isFullyCoveredByHealthWorkout ? Color.secondary : Color.green
                )
            }
            .accessibilityIdentifier("exercise.expected-supplement")

            if isFullyCoveredByHealthWorkout {
                Label(
                    "Apple 健康已完整记录这次运动，无需再次补记。",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.callout.bold())
                .foregroundStyle(.orange)
                .accessibilityIdentifier("exercise.health-fully-covered")
            }
        } else if healthCoverageQueryFailed {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "无法核对 Apple 健康记录，未保存。请重试。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)

                Button("重试核对") {
                    guard let coverageQuery else { return }
                    Task {
                        await refreshHealthCoverage(for: coverageQuery)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("exercise.health-coverage-retry")
            }
            .accessibilityIdentifier("exercise.health-coverage-failed")
        }
    }

    private func refreshHealthCoverage(
        for query: ExerciseCoverageQuery
    ) async {
        errorMessage = nil
        isCheckingHealthCoverage = true
        healthCoverageQueryFailed = false
        healthPreview = nil
        previewedCoverageQuery = query

        if DemoMode.demoExerciseHealthQueryFailureEnabled,
           !didInjectDemoHealthCoverageFailure {
            didInjectDemoHealthCoverageFailure = true
            healthCoverageQueryFailed = true
            isCheckingHealthCoverage = false
            return
        }

        do {
            let preview = try await fetchHealthCoverage(for: query)
            guard !Task.isCancelled, coverageQuery == query else { return }
            healthPreview = preview
            healthCoverageQueryFailed = false
            isCheckingHealthCoverage = false
        } catch {
            guard !Task.isCancelled, coverageQuery == query else { return }
            healthPreview = nil
            healthCoverageQueryFailed = true
            isCheckingHealthCoverage = false
        }
    }

    private func fetchHealthCoverage(
        for query: ExerciseCoverageQuery
    ) async throws -> ManualExerciseSupplement {
        if DemoMode.isActive {
            return ManualExerciseSupplementEngine.calculate(
                exercise: query.exercise,
                healthSamples: health.todayActiveEnergyIntervals.map(
                    HealthActiveEnergySample.init
                ),
                healthWorkouts: health.todayWorkoutIntervals
            )
        }

        async let activeEnergyTask = health.fetchActiveEnergyIntervals(
            overlapping: [query.interval]
        )
        async let workoutTask = health.fetchWorkoutIntervals(
            from: query.startDate,
            to: query.endDate
        )
        let (activeEnergy, workouts) = try await (
            activeEnergyTask,
            workoutTask
        )
        return ManualExerciseSupplementEngine.calculate(
            exercise: query.exercise,
            healthSamples: activeEnergy.map(HealthActiveEnergySample.init),
            healthWorkouts: workouts
        )
    }

    private func isFullyCovered(
        _ supplement: ManualExerciseSupplement,
        query: ExerciseCoverageQuery
    ) -> Bool {
        guard supplement.usedHealthWorkoutCoverage else { return false }
        let coveredSeconds = supplement.healthWorkoutCoveredMinutes * 60
        return coveredSeconds >= query.interval.duration - 1
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        errorMessage = nil

        guard let weightKg,
              let entry = ExerciseEntry.estimated(
                startDate: selectedStartDate,
                durationMinutes: durationMinutes,
                intensity: intensity,
                weightKg: weightKg
              ) else {
            errorMessage = "请检查体重、时长和运动强度。"
            return
        }

        guard endDate <= Date() else {
            errorMessage = "结束时间不能晚于现在。"
            return
        }

        let overlaps = ManualExerciseSupplementEngine.overlaps(
            startDate: selectedStartDate,
            durationMinutes: durationMinutes,
            existingExercises: existingExercises.map(\.energyInterval)
        )
        guard !overlaps else {
            errorMessage = "该时间段与另一条 App 手动补记重叠；请调整开始时间或活动时长。"
            return
        }

        guard let query = coverageQuery else {
            errorMessage = "无法核对 Apple 健康记录，未保存。请重试。"
            return
        }

        isSaving = true
        defer { isSaving = false }

        let exactCoverage: ManualExerciseSupplement
        do {
            exactCoverage = try await fetchHealthCoverage(for: query)
        } catch {
            healthPreview = nil
            previewedCoverageQuery = query
            healthCoverageQueryFailed = true
            return
        }

        healthPreview = exactCoverage
        previewedCoverageQuery = query
        healthCoverageQueryFailed = false

        guard !isFullyCovered(exactCoverage, query: query) else {
            return
        }

        do {
            modelContext.insert(entry)
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = interfaceLocalized("保存失败", locale: locale)
        }
    }
}
