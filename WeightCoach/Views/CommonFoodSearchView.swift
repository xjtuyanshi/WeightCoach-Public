import SwiftData
import SwiftUI

/// 离线搜索常见食物，按实际克重自动换算热量和营养。
struct CommonFoodSearchView: View {
    let defaultDate: Date
    var demoFoodID: String? = nil
    var demoQuery: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.locale) private var locale

    @State private var query = ""
    @State private var selectedFood: CommonFoodReference?
    @State private var gramsText = "100"
    @State private var mealType: MealType = .snack
    @State private var showManualAdd = false
    @State private var manualEntrySaved = false
    @State private var showStarbucksCalculator = false
    @State private var starbucksEntrySaved = false
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var gramsFocused: Bool
    @FocusState private var searchFocused: Bool

    private var searchResults: [CommonFoodReference] {
        CommonFoodCatalog.search(query)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowStarbucksCalculator: Bool {
        let normalized = trimmedQuery
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
        return normalized.isEmpty
            || [
                "星巴克",
                "starbucks",
                "咖啡",
                "coffee",
                "冰摇",
                "冰搖",
                "shaken",
                "浓缩",
                "濃縮",
                "espresso",
            ]
                .contains { normalized.contains($0) }
    }

    private var grams: Double? {
        let normalized = gramsText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized),
              value.isFinite,
              value > 0,
              value <= 10_000 else {
            return nil
        }
        return value
    }

    private var calculatedNutrition: NutritionValues? {
        guard let selectedFood, let grams else { return nil }
        return selectedFood.nutrition(forGrams: grams)
    }

    private var matchedStandardPortion: CommonFoodStandardPortion? {
        guard let selectedFood, let grams else { return nil }
        return selectedFood.standardPortions.first {
            abs($0.grams - grams) < 0.01
        }
    }

    private var canSave: Bool {
        selectedFood != nil && calculatedNutrition?.energyKcal != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedFood {
                    List {
                        selectedFoodSections(selectedFood)
                    }
                } else {
                    List {
                        searchField
                        searchResultSections
                    }
                }
            }
            .navigationTitle(interfaceLocalized(
                selectedFood == nil ? "添加食物" : "确认食物",
                locale: locale
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        searchFocused = false
                        gramsFocused = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectedFood != nil {
                    saveButton
                }
            }
            .onAppear {
                mealType = MealType.suggested(for: defaultDate)
                if let demoQuery {
                    query = demoQuery
                    return
                }
                if DemoMode.demoStarbucksEnabled {
                    showStarbucksCalculator = true
                    return
                }
                if let demoFoodID,
                   let demoFood = CommonFoodCatalog.food(id: demoFoodID) {
                    query = demoFood.name
                    selectFood(demoFood, focusesWeight: false)
                } else {
                    Task { @MainActor in
                        await Task.yield()
                        searchFocused = true
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .sheet(
                isPresented: $showManualAdd,
                onDismiss: {
                    guard manualEntrySaved else { return }
                    dismiss()
                }
            ) {
                AddFoodManualView(
                    defaultDate: defaultDate,
                    initialName: trimmedQuery
                ) {
                    manualEntrySaved = true
                }
            }
            .sheet(
                isPresented: $showStarbucksCalculator,
                onDismiss: {
                    guard starbucksEntrySaved else { return }
                    dismiss()
                }
            ) {
                StarbucksDrinkCalculatorView(defaultDate: defaultDate) {
                    starbucksEntrySaved = true
                }
            }
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

    private var searchField: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "输入一个字，如：西、虾、rice",
                    text: $query
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($searchFocused)
                .onSubmit {
                    searchFocused = false
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
        } footer: {
            Text("输入一个字就会立即出现匹配项；点选后按实际克重自动换算。")
        }
    }

    @ViewBuilder
    private func selectedFoodSections(_ food: CommonFoodReference) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 5) {
                Text(food.localizedDisplayName(locale: locale))
                    .font(.headline)
                Text("所有数值按可食部分重量估算，不包含额外用油或酱汁。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("换一种食物") {
                gramsFocused = false
                selectedFood = nil
                Task { @MainActor in
                    await Task.yield()
                    searchFocused = true
                }
            }
        }

        Section("实际吃了多少") {
            if !food.standardPortions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("常用份量")
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        ForEach(food.standardPortions) { portion in
                            standardPortionButton(portion)
                        }
                    }
                    Text("按去壳、去皮后的可食部分估算；大小不同，可以继续修改克重。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            HStack {
                TextField("可食部分重量", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .focused($gramsFocused)
                Text(interfaceLocalized("common_food.unit.grams", locale: locale))
                    .foregroundStyle(.secondary)
            }
            if food.standardPortions.isEmpty {
                HStack(spacing: 8) {
                    ForEach([50, 100, 150, 200], id: \.self) { amount in
                        Button("\(amount)g") {
                            gramsText = String(amount)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Picker("餐次", selection: $mealType) {
                ForEach(MealType.allCases) { meal in
                    Text(interfaceLocalized(meal.label, locale: locale)).tag(meal)
                }
            }
        }

        Section("自动换算") {
            if let nutrition = calculatedNutrition {
                nutritionPreview(nutrition)
                Text(food.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("通用食物参考值；品牌、品种和烹调方式会造成差异", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("请输入 0–10,000 克之间的有效重量", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var searchResultSections: some View {
        if shouldShowStarbucksCalculator {
            Section("品牌饮品核对") {
                Button {
                    searchFocused = false
                    starbucksEntrySaved = false
                    showStarbucksCalculator = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("星巴克定制饮品")
                                .font(.body.bold())
                                .foregroundStyle(.primary)
                            Text("按杯型、最终糖浆泵数和蛋白冷泡沫核对")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        Section(
            trimmedQuery.isEmpty
                ? interfaceLocalized("常见食物", locale: locale)
                : suggestionSectionTitle
        ) {
            if searchResults.isEmpty {
                ContentUnavailableView(
                    "没有匹配的常见食物",
                    systemImage: "magnifyingglass",
                    description: Text("仍然可以保留这个名称，自行填写热量与营养。")
                )
            } else {
                ForEach(searchResults) { food in
                    Button {
                        searchFocused = false
                        gramsFocused = false
                        selectFood(
                            food,
                            focusesWeight: food.standardPortions.isEmpty
                        )
                    } label: {
                        resultRow(food)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Section {
            Button {
                manualEntrySaved = false
                showManualAdd = true
            } label: {
                Label(
                    interfaceLocalized(manualFallbackTitle, locale: locale),
                    systemImage: "square.and.pencil"
                )
            }
        } footer: {
            Text("参考库完全离线，无需账号或 API Key；包装食品仍建议扫描条形码或营养标签。")
        }
    }

    private func resultRow(_ food: CommonFoodReference) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(food.localizedName(locale: locale))
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                Text(food.localizedPreparation(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let portion = food.defaultStandardPortion {
                    Label(
                        portion.searchSummary(locale: locale),
                        systemImage: "scalemass"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
                Text(per100GramEnergySummary(food.nutritionPer100Grams))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(per100GramMacroSummary(food.nutritionPer100Grams))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("选择后输入重量")
    }

    private func nutritionPreview(_ nutrition: NutritionValues) -> some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 5) {
            GridRow {
                previewValue(
                    title: "热量",
                    value: nutrition.energyKcal,
                    unit: "千卡",
                    color: .green
                )
                previewValue(
                    title: "蛋白质",
                    value: nutrition.proteinG,
                    unit: "g",
                    color: .blue
                )
            }
            Divider()
                .gridCellColumns(2)
            GridRow {
                previewValue(
                    title: "碳水",
                    value: nutrition.carbohydratesG,
                    unit: "g",
                    color: .orange
                )
                previewValue(
                    title: "脂肪",
                    value: nutrition.fatG,
                    unit: "g",
                    color: .pink
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func previewValue(
        title: String,
        value: Decimal?,
        unit: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(interfaceLocalized(title, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(Self.numberText) ?? "—")
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(interfaceLocalized(unit, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button(action: save) {
            if isSaving {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                let kcal = calculatedNutrition?.energyKcal.map(Self.numberText) ?? "0"
                let amount = matchedStandardPortion?
                    .compactDescription(locale: locale)
                    ?? "\(gramsText) \(interfaceLocalized("common_food.unit.grams", locale: locale))"
                Text(
                    "\(interfaceLocalized("记录", locale: locale)) \(amount) · \(interfaceCalorieText(kcal, locale: locale))"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSave || isSaving)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func save() {
        guard let selectedFood,
              let grams,
              let draft = selectedFood.draft(
                grams: grams,
                mealType: mealType,
                date: defaultDate,
                locale: locale,
                portionText: matchedStandardPortion?
                    .savedDescription(locale: locale)
              ),
              !isSaving else {
            return
        }

        gramsFocused = false
        isSaving = true
        Task { @MainActor in
            do {
                _ = try await FoodEntryWriter.save(
                    drafts: [draft],
                    context: modelContext,
                    health: health,
                    reminders: reminders
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func selectFood(
        _ food: CommonFoodReference,
        focusesWeight: Bool
    ) {
        selectedFood = food
        gramsText = Self.gramsText(
            food.defaultStandardPortion?.grams ?? 100
        )
        guard focusesWeight else { return }
        Task { @MainActor in
            await Task.yield()
            gramsFocused = true
        }
    }

    private func standardPortionButton(
        _ portion: CommonFoodStandardPortion
    ) -> some View {
        let isSelected = matchedStandardPortion?.id == portion.id
        return Button {
            gramsFocused = false
            gramsText = Self.gramsText(portion.grams)
        } label: {
            VStack(spacing: 3) {
                Text(portion.localizedLabel(locale: locale))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(portion.approximateWeightDescription(locale: locale))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Color.accentColor : .secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var manualFallbackTitle: String {
        guard !trimmedQuery.isEmpty else {
            return "自行填写热量与营养"
        }
        return AppLanguage.system.resolvedLanguage(systemLocale: locale) == .english
            ? "No suitable result? Enter “\(trimmedQuery)” manually"
            : interfaceLocalized("没有合适结果？自行填写", locale: locale)
                + "“\(trimmedQuery)”"
    }

    private var suggestionSectionTitle: String {
        AppLanguage.system.resolvedLanguage(systemLocale: locale) == .english
            ? "Suggestions for “\(trimmedQuery)”"
            : "“\(trimmedQuery)”\(interfaceLocalized("的联想", locale: locale))"
    }

    private func per100GramEnergySummary(_ values: NutritionValues) -> String {
        let kcal = values.energyKcal.map(Self.numberText) ?? "—"
        return "\(interfaceLocalized("common_food.per_100_grams", locale: locale)) · \(kcal) \(interfaceLocalized("千卡", locale: locale))"
    }

    private func per100GramMacroSummary(_ values: NutritionValues) -> String {
        let protein = values.proteinG.map(Self.numberText) ?? "—"
        let carbohydrates = values.carbohydratesG.map(Self.numberText) ?? "—"
        let fat = values.fatG.map(Self.numberText) ?? "—"
        return "\(interfaceLocalized("蛋白质", locale: locale)) \(protein)g · \(interfaceLocalized("碳水", locale: locale)) \(carbohydrates)g · \(interfaceLocalized("脂肪", locale: locale)) \(fat)g"
    }

    private static func numberText(_ value: Decimal) -> String {
        let number = value.doubleValue
        if abs(number.rounded() - number) < 0.05 {
            return String(Int(number.rounded()))
        }
        return String(format: "%.1f", number)
    }

    private static func gramsText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
