import SwiftUI
import SwiftData
import Charts

struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct WeightView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \WeightEntry.date, order: .reverse) private var localWeights: [WeightEntry]

    @State private var hkWeightPoints: [ChartPoint] = []
    @State private var hkFatPoints: [ChartPoint] = []
    @State private var showAddSheet = false

    /// 体重曲线数据：优先 Apple 健康（本地记录会同步进去），否则用本地记录
    private var weightPoints: [ChartPoint] {
        if !hkWeightPoints.isEmpty { return hkWeightPoints }
        return localWeights
            .map { ChartPoint(date: $0.date, value: $0.weightKg) }
            .sorted { $0.date < $1.date }
    }

    private var fatPoints: [ChartPoint] {
        if !hkFatPoints.isEmpty { return hkFatPoints }
        return localWeights
            .compactMap { entry in
                entry.bodyFatPercent.map { ChartPoint(date: entry.date, value: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    private var currentWeight: Double? {
        weightPoints.last?.value
    }

    private var yDomain: ClosedRange<Double> {
        let values = weightPoints.map(\.value) + [profile.goalWeight, profile.goalStartWeight]
        let minValue = (values.min() ?? profile.goalWeight) - 1.5
        let maxValue = (values.max() ?? profile.goalStartWeight) + 1.5
        return minValue...maxValue
    }

    private var projectedDate: Date? {
        guard let current = currentWeight else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recent = weightPoints
            .filter { $0.date >= cutoff }
            .map { (date: $0.date, weightKg: $0.value) }
        return CalorieEngine.projectedGoalDate(
            currentWeightKg: current,
            goalWeightKg: profile.goalWeight,
            recentPoints: recent
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statsHeader
                    weightChartCard
                    if !fatPoints.isEmpty {
                        fatChartCard
                    }
                    recentEntriesCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("体重")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("记录", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddWeightView(defaultWeight: currentWeight ?? profile.goalStartWeight) {
                    Task { await reload() }
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        await health.refreshAll()
        let since = min(
            profile.goalStartDate,
            Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? profile.goalStartDate
        )
        let weights = await health.fetchWeightHistory(since: since)
        let fats = await health.fetchBodyFatHistory(since: since)
        hkWeightPoints = weights.map { ChartPoint(date: $0.date, value: $0.valueKg) }
        hkFatPoints = fats.map { ChartPoint(date: $0.date, value: $0.valueKg) }
        await reminders.reconcile(
            context: modelContext,
            profile: profile,
            latestHealthWeightDate: health.latestWeightDate
        )
    }

    private var statsHeader: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "当前体重",
                value: currentWeight.map { $0.kgText } ?? "--",
                unit: "kg",
                systemImage: "scalemass",
                color: .accentColor
            )
            StatCard(
                title: "距离目标",
                value: currentWeight.map { String(format: "%.1f", max(0, $0 - profile.goalWeight)) } ?? "--",
                unit: "kg",
                systemImage: "flag.checkered",
                color: .orange
            )
            StatCard(
                title: "体脂率",
                value: fatPoints.last.map { String(format: "%.1f", $0.value) } ?? "--",
                unit: "%",
                systemImage: "percent",
                color: .pink
            )
            StatCard(
                title: "预计达成",
                value: projectedDate.map { $0.formatted(.dateTime.month().day()) } ?? "--",
                unit: "",
                systemImage: "calendar",
                color: .indigo
            )
        }
    }

    private var weightChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("体重趋势").font(.subheadline.bold())
            if weightPoints.isEmpty {
                ContentUnavailableView(
                    "暂无体重数据",
                    systemImage: "chart.line.downtrend.xyaxis",
                    description: Text("点右上角 + 记录一次体重")
                )
                .frame(height: 200)
            } else {
                Chart {
                    ForEach(weightPoints) { point in
                        LineMark(
                            x: .value(interfaceLocalized("日期", locale: locale), point.date),
                            y: .value(interfaceLocalized("体重", locale: locale), point.value),
                            series: .value(
                                interfaceLocalized("系列", locale: locale),
                                interfaceLocalized("实际", locale: locale)
                            )
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbol(.circle)
                        .interpolationMethod(.catmullRom)
                    }

                    LineMark(
                        x: .value(interfaceLocalized("日期", locale: locale), profile.goalStartDate),
                        y: .value(interfaceLocalized("体重", locale: locale), profile.goalStartWeight),
                        series: .value(
                            interfaceLocalized("系列", locale: locale),
                            interfaceLocalized("目标轨迹", locale: locale)
                        )
                    )
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                    LineMark(
                        x: .value(interfaceLocalized("日期", locale: locale), profile.goalEndDate),
                        y: .value(interfaceLocalized("体重", locale: locale), profile.goalWeight),
                        series: .value(
                            interfaceLocalized("系列", locale: locale),
                            interfaceLocalized("目标轨迹", locale: locale)
                        )
                    )
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                    RuleMark(
                        y: .value(
                            interfaceLocalized("目标体重", locale: locale),
                            profile.goalWeight
                        )
                    )
                        .foregroundStyle(.green.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .bottom, alignment: .trailing) {
                            Text(
                                "\(interfaceLocalized("目标", locale: locale)) \(profile.goalWeight.kgText) kg"
                            )
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
                .chartYScale(domain: yDomain)
                .frame(height: 220)
                Text("虚线为按计划的目标轨迹")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fatChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("体脂率趋势").font(.subheadline.bold())
            Chart(fatPoints) { point in
                LineMark(
                    x: .value(interfaceLocalized("日期", locale: locale), point.date),
                    y: .value(interfaceLocalized("体脂率", locale: locale), point.value)
                )
                .foregroundStyle(.pink)
                .symbol(.circle)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 160)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recentEntriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近记录").font(.subheadline.bold())
            if weightPoints.isEmpty {
                Text("暂无").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(weightPoints.suffix(8).reversed()) { point in
                    HStack {
                        Text(point.date.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(point.value.kgText) kg")
                            .font(.subheadline.bold())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum WeightEntryInput {
    static func decimalValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func bodyFatPercent(_ text: String) -> Double? {
        guard let value = decimalValue(text), value > 3, value < 70 else {
            return nil
        }
        return value
    }

    static func isOptionalBodyFatValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || bodyFatPercent(trimmed) != nil
    }
}

/// 记录体重/体脂
struct AddWeightView: View {
    let defaultWeight: Double
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.locale) private var locale

    @State private var weightText = ""
    @State private var fatText = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showHealthSyncWarning = false

    private var weight: Double? {
        WeightEntryInput.decimalValue(weightText)
    }
    private var bodyFatPercent: Double? {
        WeightEntryInput.bodyFatPercent(fatText)
    }
    private var isBodyFatInputValid: Bool {
        WeightEntryInput.isOptionalBodyFatValid(fatText)
    }
    private var canSave: Bool {
        guard let w = weight else { return false }
        return w > 20 && w < 400 && isBodyFatInputValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("测量数据") {
                    HStack {
                        Text("体重")
                        Spacer()
                        TextField("kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("体脂率（可选）")
                        Spacer()
                        TextField("%", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("%").foregroundStyle(.secondary)
                    }
                    if !isBodyFatInputValid {
                        Text("体脂率需大于 3% 且小于 70%，或留空。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    DatePicker("时间", selection: $date, in: ...Date())
                }
                if let errorMessage {
                    Section {
                        Text(interfaceLocalized(errorMessage, locale: locale))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("记录体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("已保存到 App", isPresented: $showHealthSyncWarning) {
                Button("完成") {
                    onSaved()
                    dismiss()
                }
            } message: {
                Text("这次未能写入 Apple 健康，本地体重记录仍然保留。")
            }
            .onAppear {
                weightText = String(format: "%.1f", defaultWeight)
            }
        }
    }

    private func save() {
        guard let kg = weight else { return }
        isSaving = true
        errorMessage = nil
        let fat = bodyFatPercent
        let entry = WeightEntry(date: date, weightKg: kg, bodyFatPercent: fat)
        modelContext.insert(entry)
        Task { @MainActor in
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(entry)
                isSaving = false
                errorMessage = "本地保存失败，请重试。"
                return
            }

            reminders.cancel(.weight, on: date)
            do {
                try await health.saveWeight(kg: kg, bodyFatPercent: fat, date: date)
                entry.syncedToHealthKit = true
                do {
                    try modelContext.save()
                } catch {
                    // 健康样本已经写入成功；本地同步标记可在下次读取健康数据时恢复。
                }
                isSaving = false
                onSaved()
                dismiss()
            } catch {
                isSaving = false
                showHealthSyncWarning = true
            }
        }
    }
}
