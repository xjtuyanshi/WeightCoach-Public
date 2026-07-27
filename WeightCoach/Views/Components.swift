import SwiftUI

func interfaceCalorieText(_ value: String, locale: Locale) -> String {
    "\(value) \(interfaceLocalized("千卡", locale: locale))"
}

/// 小型数据卡片
struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    var color: Color = .accentColor

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(interfaceLocalized(title, locale: locale), systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 今日热量预算环
struct BudgetRingView: View {
    /// 今日预算（千卡）
    let budget: Double
    /// 已摄入（千卡）
    let consumed: Double

    private var remaining: Double { budget - consumed }
    private var fraction: Double {
        guard budget > 0 else { return 0 }
        return min(max(consumed / budget, 0), 1)
    }
    private var isOver: Bool { remaining < 0 }

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 18)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isOver ? Color.red : Color.accentColor,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)

            VStack(spacing: 4) {
                Text(interfaceLocalized(isOver ? "已超出" : "还能吃", locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(Int(abs(remaining).rounded()))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(isOver ? .red : .primary)
                    .contentTransition(.numericText())
                Text("千卡")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 三大营养素的已记录值、推荐目标与数据完整度。
struct MacroSummaryView: View {
    let metrics: TodayNutritionMetrics
    let targets: DailyMacroTargets
    let consumedKcal: Double
    let allowsTrainingAdjustment: Bool
    let onDayStyleChange: (MacroDayStyle) -> Void

    @State private var showTargetExplanation = false
    @Environment(\.locale) private var locale

    private var remainingKcal: Double {
        targets.budgetKcal - consumedKcal
    }

    private var calorieProgress: Double {
        guard targets.budgetKcal > 0 else { return 0 }
        return min(max(consumedKcal / targets.budgetKcal, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("营养摄入", systemImage: "fork.knife.circle.fill")
                    .font(.headline)
                Spacer()
                if allowsTrainingAdjustment {
                    Menu {
                        ForEach(MacroDayStyle.allCases, id: \.self) { style in
                            Button {
                                onDayStyleChange(style)
                            } label: {
                                if targets.dayStyle == style {
                                    Label(
                                        interfaceLocalized(style.label, locale: locale),
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(interfaceLocalized(style.label, locale: locale))
                                }
                            }
                        }
                    } label: {
                        Text(
                            "\(interfaceLocalized("今天", locale: locale))：\(interfaceLocalized(targets.dayStyle.label, locale: locale))"
                        )
                            .font(.caption.bold())
                    }
                }
                Button {
                    showTargetExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("营养目标如何计算")
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已摄入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(consumedKcal.kcalText)
                            .font(.system(.title, design: .rounded).bold())
                        Text("千卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(interfaceLocalized(
                        remainingKcal < 0 ? "已超出" : "还能吃",
                        locale: locale
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(abs(remainingKcal).kcalText)
                            .font(.system(.title, design: .rounded).bold())
                            .foregroundStyle(remainingKcal < 0 ? .red : .green)
                        Text("千卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: calorieProgress)
                .tint(remainingKcal < 0 ? .red : .green)
            Text(
                "\(interfaceLocalized("今日热量目标", locale: locale)) \(interfaceCalorieText(targets.budgetKcal.kcalText, locale: locale))"
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            if targets.dayStyle == .training {
                Text("训练日 · 碳水稍高，总热量不变")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            macroRow(
                name: "蛋白质",
                actual: metrics.proteinG,
                target: targets.proteinG,
                color: .blue,
                treatsTargetAsMinimum: true
            )
            macroRow(
                name: "脂肪",
                actual: metrics.fatG,
                target: targets.fatG,
                color: .pink,
                treatsTargetAsMinimum: false
            )
            macroRow(
                name: "碳水",
                actual: metrics.carbsG,
                target: targets.carbsG,
                color: .orange,
                treatsTargetAsMinimum: false
            )

            coverageSummary
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showTargetExplanation) {
            targetExplanationSheet
        }
    }

    private func macroRow(
        name: String,
        actual: Double?,
        target: Double,
        color: Color,
        treatsTargetAsMinimum: Bool
    ) -> some View {
        let fraction = actual.map { min(max($0 / max(target, 1), 0), 1) } ?? 0

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(interfaceLocalized(name, locale: locale))
                        .font(.subheadline.bold())
                }
                Spacer()
                if let actual {
                    Text("\(Int(actual.rounded())) / \(Int(target.rounded())) g")
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text(
                        "\(interfaceLocalized("暂无数据", locale: locale)) / \(Int(target.rounded())) g"
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(
                    statusText(
                        actual: actual,
                        target: target,
                        treatsTargetAsMinimum: treatsTargetAsMinimum
                    )
                )
                .font(.caption.bold())
                .foregroundStyle(
                    statusColor(
                        actual: actual,
                        target: target,
                        treatsTargetAsMinimum: treatsTargetAsMinimum
                    )
                )
            }
            ProgressView(value: fraction)
                .tint(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityText(
                name: name,
                actual: actual,
                target: target,
                treatsTargetAsMinimum: treatsTargetAsMinimum
            )
        )
    }

    @ViewBuilder
    private var coverageSummary: some View {
        if metrics.entryCount == 0 {
            Text("记录饮食后，这里会显示营养完成情况")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let coverage = metrics.completeMacroCoverage {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    "\(interfaceLocalized("宏量数据覆盖", locale: locale)) \(Int((coverage * 100).rounded()))% (\(interfaceLocalized("按已记录热量", locale: locale)))"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if metrics.hasIncompleteMacroData {
                    Label(
                        "部分记录缺少营养数据，宏量总计可能偏低",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var targetExplanationSheet: some View {
        NavigationStack {
            List {
                Section("推荐方式") {
                    Text(macroMethodText)
                    Text("宏量目标只是在现有热量预算内做分配，不会改变你的每日预算。")
                }
                Section("训练日燃料调整") {
                    Text("默认关闭。开启后，训练日只会在相同总热量内适当提高碳水、降低脂肪；蛋白质不变，也不代表减脂会更快。")
                }
                if targets.isBudgetConstrained {
                    Section("当前提示") {
                        Text("当前热量预算不足以同时满足常规蛋白质和脂肪比例，目标已在预算内收紧。若长期出现，请核对减重目标并咨询注册营养师。")
                    }
                }
                Section {
                    Text("慢性肾病、医生限制蛋白质、妊娠哺乳或需要药物配合饮食时，请使用医生或注册营养师给出的目标。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("营养目标如何计算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showTargetExplanation = false }
                }
            }
        }
    }

    private var macroMethodText: String {
        let fatPercentage = targets.dayStyle == .training ? "20%" : "25%"
        switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
        case .english:
            return "Protein is estimated from your current weight and muscle-retention goal. Fat uses about \(fatPercentage) of today’s calorie budget, and remaining calories go to carbs."
        case .traditionalChinese:
            return "蛋白質依目前體重與保肌目標估算；脂肪約占今日熱量預算的 \(fatPercentage)；剩餘熱量分配給碳水。"
        case .simplifiedChinese, .system:
            return "蛋白质按当前体重和保肌目标估算；脂肪约占今日热量预算的 \(fatPercentage)；剩余热量分配给碳水。"
        }
    }

    private func statusText(
        actual: Double?,
        target: Double,
        treatsTargetAsMinimum: Bool
    ) -> String {
        guard let actual else { return "" }
        let difference = actual - target
        if difference < -0.5 {
            let prefix = metrics.hasIncompleteMacroData ? "按已记录还差" : "还差"
            return "\(interfaceLocalized(prefix, locale: locale)) \(Int(abs(difference).rounded()))g"
        }
        if treatsTargetAsMinimum {
            return interfaceLocalized("已达标", locale: locale)
        }
        if difference > 0.5 {
            return "\(interfaceLocalized("高于目标", locale: locale)) \(Int(difference.rounded()))g"
        }
        return interfaceLocalized("已达标", locale: locale)
    }

    private func statusColor(
        actual: Double?,
        target: Double,
        treatsTargetAsMinimum: Bool
    ) -> Color {
        guard let actual else { return .secondary }
        if treatsTargetAsMinimum, actual >= target - 0.5 {
            return .green
        }
        return .secondary
    }

    private func accessibilityText(
        name: String,
        actual: Double?,
        target: Double,
        treatsTargetAsMinimum: Bool
    ) -> String {
        guard let actual else {
            return "\(interfaceLocalized(name, locale: locale)), \(interfaceLocalized("暂无已记录数据", locale: locale)), \(interfaceLocalized("目标", locale: locale)) \(Int(target.rounded())) g"
        }
        return "\(interfaceLocalized(name, locale: locale)), \(interfaceLocalized("已记录", locale: locale)) \(Int(actual.rounded())) g, \(interfaceLocalized("目标", locale: locale)) \(Int(target.rounded())) g, \(statusText(actual: actual, target: target, treatsTargetAsMinimum: treatsTargetAsMinimum))"
    }
}

/// 将消耗估算与饮食摄入明确分开，避免把活动能量重复抵扣。
struct EnergyExpenditureCard: View {
    let bmrKcal: Double
    let healthActiveEnergyKcal: Double
    let manualExerciseEstimatedKcal: Double
    let manualExerciseHealthOverlapKcal: Double
    let manualExerciseSupplementKcal: Double
    let tdeeKcal: Double
    let deficitKcal: Double
    let budgetKcal: Double
    let activityFactor: Double
    let includeActiveEnergy: Bool

    @State private var showExplanation = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("热量消耗", systemImage: "flame.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showExplanation = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("热量消耗如何计算")
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日总消耗估算")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(tdeeKcal.kcalText)
                            .font(.system(.title2, design: .rounded).bold())
                        Text("千卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(interfaceLocalized(
                    includeActiveEnergy ? "手表活动模式" : "活动系数模式",
                    locale: locale
                ))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                expenditureValue("基础代谢", value: bmrKcal)
                expenditureValue(
                    includeActiveEnergy ? "Apple 健康活动" : "健康活动（未计入）",
                    value: healthActiveEnergyKcal
                )
                expenditureValue(
                    includeActiveEnergy ? "手动运动补差" : "手动运动（未计入）",
                    value: manualExerciseSupplementKcal
                )
                expenditureValue("目标缺口", value: deficitKcal)
            }

            Text(interfaceLocalized(
                includeActiveEnergy
                    ? "总消耗 = 基础代谢 × 1.1 + Apple 健康活动 + 未被健康记录的手动运动补差"
                    : "总消耗 = 基础代谢 × 活动系数；Apple 健康与手动运动不重复叠加",
                locale: locale
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showExplanation) {
            explanationSheet
        }
    }

    private func expenditureValue(_ title: String, value: Double) -> some View {
        HStack {
            Text(interfaceLocalized(title, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text(interfaceCalorieText(value.kcalText, locale: locale))
                .font(.caption.bold().monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var explanationSheet: some View {
        NavigationStack {
            List {
                Section("总消耗估算") {
                    if includeActiveEnergy {
                        LabeledContent("基础代谢 × 1.1", value: interfaceCalorieText((bmrKcal * 1.1).kcalText, locale: locale))
                        LabeledContent("Apple 健康活动", value: interfaceCalorieText(healthActiveEnergyKcal.kcalText, locale: locale))
                        LabeledContent("手动运动估算", value: interfaceCalorieText(manualExerciseEstimatedKcal.kcalText, locale: locale))
                        LabeledContent(
                            "其中健康已记录",
                            value: interfaceCalorieText(manualExerciseHealthOverlapKcal.kcalText, locale: locale)
                        )
                        LabeledContent("实际补入", value: interfaceCalorieText(manualExerciseSupplementKcal.kcalText, locale: locale))
                    } else {
                        LabeledContent("基础代谢", value: interfaceCalorieText(bmrKcal.kcalText, locale: locale))
                        LabeledContent("活动系数", value: String(format: "%.2f", activityFactor))
                        LabeledContent("手动运动估算", value: interfaceCalorieText(manualExerciseEstimatedKcal.kcalText, locale: locale))
                        Text("当前使用活动系数模式，手动补记只展示，不额外计入预算。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("合计", value: interfaceCalorieText(tdeeKcal.kcalText, locale: locale))
                    Text("这里继续使用既有的消耗模型；按运动时间扣除 Apple 健康已经记录的活动能量，只补缺失部分。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("今日饮食目标") {
                    LabeledContent("动态目标缺口", value: interfaceCalorieText(deficitKcal.kcalText, locale: locale))
                    LabeledContent("今日热量目标", value: interfaceCalorieText(budgetKcal.kcalText, locale: locale))
                    Text("“还能吃”只用今日热量目标减去饮食摄入，不会再减一次运动消耗。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("热量消耗说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showExplanation = false }
                }
            }
        }
    }
}

extension Double {
    var kcalText: String { "\(Int(self.rounded()))" }
    var kgText: String { String(format: "%.1f", self) }
}
