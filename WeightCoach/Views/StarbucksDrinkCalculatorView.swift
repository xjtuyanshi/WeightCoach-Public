import SwiftData
import SwiftUI

struct StarbucksDrinkCalculatorView: View {
    let defaultDate: Date
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.locale) private var locale

    @State private var standardSyrupPumps = 4
    @State private var finalTotalSyrupPumps = 1
    @State private var includesProteinFoam = true
    @State private var mealType: MealType = .snack
    @State private var recordedCaloriesText = "400"
    @State private var isSaving = false
    @State private var saveError: String?

    private var estimate: StarbucksDrinkEstimate {
        StarbucksCustomizationEngine.estimateVentiIcedShakenEspresso(
            standardSyrupPumps: standardSyrupPumps,
            finalTotalSyrupPumps: finalTotalSyrupPumps,
            includesBlueCoconutProteinColdFoam: includesProteinFoam
        )!
    }

    private var recordedCalories: Double? {
        ManualNutritionInput.nonnegativeNumber(from: recordedCaloriesText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Venti Iced Shaken Espresso")
                            .font(.headline)
                        Text("24 fl oz · 4 份浓缩")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(
                        "Starbucks 标准显示",
                        value: "\(Int(estimate.officialStandardCalories)) \(interfaceLocalized("千卡", locale: locale))"
                    )
                    LabeledContent(
                        "咖啡因",
                        value: "\(interfaceLocalized("约", locale: locale)) \(Int(estimate.caffeineMg)) mg"
                    )
                    HStack(alignment: .firstTextBaseline) {
                        Text("当前建议记录")
                            .bold()
                        Spacer()
                        Text(interfaceCalorieText(
                            estimate.recommendedCalories.kcalText,
                            locale: locale
                        ))
                            .font(.title3.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                    Label(
                        "\(interfaceLocalized("估算区间", locale: locale)) \(estimate.calorieLowerBound.kcalText)–\(interfaceCalorieText(estimate.calorieUpperBound.kcalText, locale: locale))",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } header: {
                    Text("饮品")
                } footer: {
                    Text("标准热量不会随 App 内自定义实时变化；下面按你最终喝到的配方重新估算。")
                }

                Section("糖浆") {
                    Stepper(
                        "\(interfaceLocalized("标准配方原有", locale: locale)): \(standardSyrupPumps) \(interfaceLocalized("泵", locale: locale))",
                        value: $standardSyrupPumps,
                        in: 0...12
                    )
                    Stepper(
                        "\(interfaceLocalized("最终总量", locale: locale)): \(finalTotalSyrupPumps) \(interfaceLocalized("泵", locale: locale))",
                        value: $finalTotalSyrupPumps,
                        in: 0...12
                    )
                    Text("这里填最终总泵数，不是“额外再加几泵”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("加料") {
                    Toggle(
                        "Blue Coconut Protein Cold Foam",
                        isOn: $includesProteinFoam
                    )
                    if includesProteinFoam {
                        Text("此冷泡沫没有单独公开的官方完整营养值；按 Starbucks 官方相邻蛋白冷泡沫饮品推算。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("估算拆分") {
                    breakdownRow(
                        "标准饮品",
                        value: estimate.officialStandardCalories
                    )
                    breakdownRow(
                        "糖浆变化",
                        value: estimate.syrupAdjustmentCalories,
                        signed: true
                    )
                    breakdownRow(
                        includesProteinFoam ? "蛋白冷泡沫（推算）" : "蛋白冷泡沫",
                        value: estimate.addOnCalories
                    )
                    HStack {
                        Text("建议记录")
                            .bold()
                        Spacer()
                        Text(interfaceCalorieText(
                            estimate.recommendedCalories.kcalText,
                            locale: locale
                        ))
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                    Label(
                        "\(interfaceLocalized("合理区间", locale: locale)) \(estimate.calorieLowerBound.kcalText)–\(interfaceCalorieText(estimate.calorieUpperBound.kcalText, locale: locale))",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Section {
                    LabeledContent(
                        "蛋白质（估算）",
                        value: "\(estimate.proteinG.kcalText) g"
                    )
                    LabeledContent(
                        "碳水（估算）",
                        value: "\(estimate.carbohydratesG.kcalText) g"
                    )
                    LabeledContent(
                        "脂肪（估算）",
                        value: "\(estimate.fatG.kcalText) g"
                    )
                } header: {
                    Text("营养素")
                } footer: {
                    Text("咖啡因主要由浓缩份数决定；减少糖浆不会降低咖啡因。")
                }

                Section("记录前确认") {
                    HStack {
                        TextField("热量", text: $recordedCaloriesText)
                            .keyboardType(.decimalPad)
                        Text("千卡")
                            .foregroundStyle(.secondary)
                    }
                    Picker("餐次", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Text(interfaceLocalized(meal.label, locale: locale)).tag(meal)
                        }
                    }
                }
            }
            .navigationTitle("星巴克定制核对")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(
                            "\(interfaceLocalized("确认记录", locale: locale)) · \(interfaceCalorieText((recordedCalories ?? 0).kcalText, locale: locale))"
                        )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(recordedCalories == nil || isSaving)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .onAppear {
                mealType = MealType.suggested(for: defaultDate)
                updateRecordedCalories()
            }
            .onChange(of: standardSyrupPumps) { _, _ in updateRecordedCalories() }
            .onChange(of: finalTotalSyrupPumps) { _, _ in updateRecordedCalories() }
            .onChange(of: includesProteinFoam) { _, _ in updateRecordedCalories() }
            .interactiveDismissDisabled(isSaving)
            .alert(
                "保存失败",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                if let saveError {
                    Text(interfaceLocalized(saveError, locale: locale))
                } else {
                    Text("请稍后重试")
                }
            }
        }
    }

    private func breakdownRow(
        _ title: String,
        value: Double,
        signed: Bool = false
    ) -> some View {
        HStack {
            Text(interfaceLocalized(title, locale: locale))
            Spacer()
            Text(
                (signed && value > 0 ? "+" : "")
                    + interfaceCalorieText(value.kcalText, locale: locale)
            )
            .foregroundStyle(.secondary)
        }
    }

    private func updateRecordedCalories() {
        recordedCaloriesText = String(Int(estimate.recommendedCalories.rounded()))
    }

    private func save() {
        guard let recordedCalories, !isSaving else { return }
        isSaving = true
        let retainsEstimateRange = estimate.calorieLowerBound <= recordedCalories
            && recordedCalories <= estimate.calorieUpperBound

        let syrupDescription =
            "Classic Syrup \(interfaceLocalized("最终总量", locale: locale)) \(finalTotalSyrupPumps) \(interfaceLocalized("泵", locale: locale))"
        let foamDescription = includesProteinFoam
            ? ", Blue Coconut Protein Cold Foam"
            : ""
        let draft = FoodEntryDraft(
            name: "Starbucks Venti Iced Shaken Espresso",
            calories: recordedCalories,
            protein: estimate.proteinG,
            carbs: estimate.carbohydratesG,
            fat: estimate.fatG,
            portionText:
                "\(syrupDescription)\(foamDescription) (\(interfaceLocalized("估算", locale: locale)))",
            mealType: mealType,
            source: .brandCalculator,
            date: defaultDate,
            calculationVersion: 1,
            caffeineMg: estimate.caffeineMg,
            calorieLowerBound: retainsEstimateRange ? estimate.calorieLowerBound : nil,
            calorieUpperBound: retainsEstimateRange ? estimate.calorieUpperBound : nil
        )

        Task { @MainActor in
            do {
                _ = try await FoodEntryWriter.save(
                    drafts: [draft],
                    context: modelContext,
                    health: health,
                    reminders: reminders
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSaved?()
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
