import SwiftUI
import SwiftData

/// 不戴 Apple Watch 时补记运动。
///
/// 手动记录只保存在 App 内；仪表盘会按时间扣除 Apple 健康已经记录的活动能量，
/// 因此健康样本稍后同步到手机时，补差会自动减少。
struct ExerciseLogView: View {
    @EnvironmentObject private var profile: ProfileStore
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseEntry.startDate, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var localWeights: [WeightEntry]

    @State private var showAddExercise = false
    @State private var deletionError: String?
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
        ManualExerciseSupplementEngine.calculateTotal(
            exercises: todayExercises.map(\.energyInterval),
            healthSamples: health.todayActiveEnergyIntervals.map(HealthActiveEnergySample.init),
            within: todayInterval
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

                Section {
                    Label {
                        Text("只补记 Apple 健康没有完整记录的运动。稍后同步到的健康数据会自动从补差中扣除。")
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }

                    Label {
                        Text("篮球时长请填真正活动的分钟数，不包含坐场边、长时间休息或聊天。")
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
                            description: Text("不戴手表打球或跑步后，点右上角 + 记录")
                        )
                    }
                } else {
                    Section("最近补记") {
                        ForEach(exercises.prefix(20)) { exercise in
                            exerciseRow(exercise)
                        }
                        .onDelete(perform: deleteExercises)
                    }
                }
            }
            .navigationTitle("运动补记")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddExercise = true
                    } label: {
                        Label("记录运动", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseView(
                    defaultWeightKg: currentWeight,
                    existingExercises: exercises
                )
            }
            .task {
                if !DemoMode.isActive {
                    await health.refreshAll()
                }
                if DemoMode.demoExerciseEnabled {
                    showAddExercise = true
                }
            }
            .refreshable {
                if !DemoMode.isActive {
                    await health.refreshAll()
                }
            }
            .alert(
                "删除失败",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                if let deletionError {
                    Text(deletionError)
                } else {
                    Text("请稍后重试")
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
                summaryValue(
                    "健康已记",
                    value: todaySummary.overlappingHealthEnergyKcal,
                    color: .blue
                )
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

    private func exerciseRow(_ exercise: ExerciseEntry) -> some View {
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
                Text(exercise.estimatedActiveEnergyKcal.kcalText)
                    .font(.headline.monospacedDigit())
                Text("活动千卡")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func deleteExercises(at offsets: IndexSet) {
        let visible = Array(exercises.prefix(20))
        let selected = offsets.compactMap { index in
            visible.indices.contains(index) ? visible[index] : nil
        }

        do {
            selected.forEach(modelContext.delete)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deletionError = interfaceLocalized("请稍后重试", locale: locale)
        }
    }
}

struct AddExerciseView: View {
    let defaultWeightKg: Double
    let existingExercises: [ExerciseEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var activityType: ExerciseActivityType = .basketball
    @State private var intensity: ExerciseIntensity = .basketballGeneral
    @State private var startDate = Date().addingTimeInterval(-3_600)
    @State private var durationMinutes = 60.0
    @State private var weightText = ""
    @State private var errorMessage: String?
    @Environment(\.locale) private var locale

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

    private var endDate: Date {
        startDate.addingTimeInterval(durationMinutes * 60)
    }

    private var canSave: Bool {
        estimatedActiveEnergy != nil && endDate <= Date()
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
                    .pickerStyle(.segmented)

                    Picker("强度", selection: $intensity) {
                        ForEach(ExerciseIntensity.presets(for: activityType)) { preset in
                            Text(interfaceLocalized(preset.label, locale: locale)).tag(preset)
                        }
                    }

                    Text(interfaceLocalized(intensity.detail, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("时间与体重") {
                    DatePicker(
                        "开始时间",
                        selection: $startDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Stepper(
                        "\(interfaceLocalized("活动时长", locale: locale)): \(Int(durationMinutes)) \(interfaceLocalized("分钟", locale: locale))",
                        value: $durationMinutes,
                        in: 10...600,
                        step: 5
                    )

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

                    if endDate > Date() {
                        Text("结束时间不能晚于现在，请调整开始时间或活动时长。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("预计净活动热量")
                                .font(.subheadline.bold())
                            Text("已减去同一时段原本会消耗的静息热量")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let estimatedActiveEnergy {
                            Text(interfaceCalorieText(
                                estimatedActiveEnergy.kcalText,
                                locale: locale
                            ))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.orange)
                        } else {
                            Text("--")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("采用 2024 Adult Compendium 的 MET 群体估算。篮球请只填真正活动时间；App 会再扣除同一时段 Apple 健康已经记录的活动能量。")
                }

                if let errorMessage {
                    Section {
                        Text(interfaceLocalized(errorMessage, locale: locale))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("补记运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                weightText = String(format: "%.1f", defaultWeightKg)
            }
            .onChange(of: activityType) { _, newValue in
                intensity = ExerciseIntensity.defaultIntensity(for: newValue)
            }
        }
    }

    private func save() {
        errorMessage = nil

        guard let weightKg,
              let entry = ExerciseEntry.estimated(
                startDate: startDate,
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
            startDate: startDate,
            durationMinutes: durationMinutes,
            existingExercises: existingExercises.map(\.energyInterval)
        )
        guard !overlaps else {
            errorMessage = "这段时间已有手动运动记录，请调整时间，避免重复计算。"
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
