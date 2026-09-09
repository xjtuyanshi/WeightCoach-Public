import SwiftData
import SwiftUI
import UIKit

/// 从完整饮食历史选择一条摄入快照，按任意比例换算后记录到今天。
///
/// 这里有意不复用今日页的「常吃与最近」建议：建议卡只覆盖近 30 天且会
/// 直接保存；历史复用需要保留每一条旧记录，并在保存前确认比例与餐次。
struct HistoryFoodRepeatView: View {
    let onSaved: (FoodEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]

    @State private var searchText = ""

    private struct HistoryDay: Identifiable {
        let dayStart: Date
        let foods: [FoodEntry]

        var id: Date { dayStart }
    }

    private var filteredFoods: [FoodEntry] {
        let search = HistoryFoodSearchEngine(query: searchText)
        guard !search.isEmpty else { return foods.filter(isRepeatable) }

        let mealLabels = Dictionary(uniqueKeysWithValues: MealType.allCases.map {
            ($0.rawValue, interfaceLocalized($0.label, locale: locale))
        })
        var sourceLabels: [String: String] = [:]
        for food in foods where sourceLabels[food.source.rawValue] == nil {
            sourceLabels[food.source.rawValue] = interfaceLocalized(
                food.source.label,
                locale: locale
            )
        }

        return foods.filter { food in
            isRepeatable(food) &&
            search.matches(
                name: food.name,
                portionText: food.portionText,
                mealLabel: mealLabels[food.mealType.rawValue, default: ""],
                sourceLabel: sourceLabels[food.source.rawValue, default: ""]
            )
        }
    }

    private var historyDays: [HistoryDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredFoods) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { dayStart in
            HistoryDay(
                dayStart: dayStart,
                foods: grouped[dayStart, default: []].sorted {
                    $0.date > $1.date
                }
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if foods.isEmpty {
                    ContentUnavailableView(
                        "没有历史饮食记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("记录饮食后，就可以从这里再次添加。")
                    )
                } else if filteredFoods.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的历史记录",
                        systemImage: "magnifyingglass",
                        description: Text("试试其他食物名称，或清除搜索。")
                    )
                } else {
                    List {
                        ForEach(historyDays) { day in
                            Section(dayTitle(day.dayStart)) {
                                ForEach(Array(day.foods.enumerated()), id: \.element.id) { index, food in
                                    NavigationLink {
                                        HistoryFoodRepeatEditor(
                                            food: food,
                                            onCancel: { dismiss() },
                                            onSaved: { saved in
                                                onSaved(saved)
                                                dismiss()
                                            }
                                        )
                                    } label: {
                                        historyRow(food)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(
                                        historyAccessibilityLabel(food)
                                    )
                                    .accessibilityHint(
                                        Text("选择后可调整本次食用比例。")
                                    )
                                    .accessibilityIdentifier(
                                        "history_food_row_\(Int(food.date.timeIntervalSince1970))_\(index)"
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("选择历史食物")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索吃过的食物")
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func historyRow(_ food: FoodEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: food.mealType.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(food.name)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(interfaceLocalized(food.mealType.label, locale: locale))
                    if let portion = nonempty(food.portionText) {
                        Text("·")
                        Text(portion)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(timestampText(food.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(interfaceCalorieText(food.calories.kcalText, locale: locale))
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 3)
    }

    private func isRepeatable(_ food: FoodEntry) -> Bool {
        food.calories.isFinite
            && food.calories >= 0
            && food.calories <= 1_000_000
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return interfaceLocalized("今天", locale: locale)
        }
        return dateText(date, dateStyle: .full, timeStyle: .none)
    }

    private func timestampText(_ date: Date) -> String {
        dateText(date, dateStyle: .medium, timeStyle: .short)
    }

    private func dateText(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private func historyAccessibilityLabel(_ food: FoodEntry) -> Text {
        let meal = interfaceLocalized(food.mealType.label, locale: locale)
        let portion = nonempty(food.portionText)
            ?? interfaceLocalized("按上次记录", locale: locale)
        let calories = interfaceCalorieText(food.calories.kcalText, locale: locale)
        return Text("\(food.name)，\(timestampText(food.date))，\(meal)，\(portion)，\(calories)")
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct HistoryFoodRepeatEditor: View {
    let food: FoodEntry
    let onCancel: () -> Void
    let onSaved: (FoodEntry) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler

    @State private var ratioText = "1"
    @State private var mealType = MealType.suggested()
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var ratioFocused: Bool

    private let quickRatios = [0.25, 0.5, 0.75, 1, 1.5, 2]

    private var ratioResult: Result<Double, PortionRatioValidationError> {
        do {
            return .success(try PortionRatioEngine.parse(ratioText))
        } catch let error as PortionRatioValidationError {
            return .failure(error)
        } catch {
            return .failure(.invalidFormat)
        }
    }

    private var ratio: Double? {
        try? ratioResult.get()
    }

    private var adjustedCalories: Double? {
        ratio.flatMap { ratio in
            let value = food.calories * ratio
            guard value.isFinite,
                  value >= 0,
                  value <= Double(Int.max) else {
                return nil
            }
            return value
        }
    }

    var body: some View {
        Form {
            Section("原记录") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(food.name)
                        .font(.headline)
                    LabeledContent(
                        "日期",
                        value: timestampText(food.date)
                    )
                    LabeledContent(
                        "餐次",
                        value: interfaceLocalized(food.mealType.label, locale: locale)
                    )
                    LabeledContent(
                        "份量",
                        value: originalPortionText
                    )
                    LabeledContent(
                        "热量",
                        value: interfaceCalorieText(food.calories.kcalText, locale: locale)
                    )
                }
            }

            Section("添加到今天") {
                LabeledContent(
                    "日期",
                    value: todayText
                )
                Picker("餐次", selection: $mealType) {
                    ForEach(MealType.allCases) { meal in
                        Text(interfaceLocalized(meal.label, locale: locale))
                            .tag(meal)
                    }
                }
            }

            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 3),
                    spacing: 8
                ) {
                    ForEach(quickRatios, id: \.self) { value in
                        ratioButton(value)
                    }
                }
                .padding(.vertical, 2)

                HStack(spacing: 10) {
                    Text("×")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                    TextField("份量倍数", text: $ratioText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($ratioFocused)
                        .accessibilityIdentifier("history_food_ratio_field")
                        .onSubmit { ratioFocused = false }
                }

                if let ratioErrorText {
                    Label(ratioErrorText, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("history_food_ratio_error")
                } else {
                    Text("输入比例，例如 0.75 或 3/4 表示原记录的 3/4。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("这次吃了多少")
            } footer: {
                Text("按原记录等比例换算热量和营养，原记录不会被修改。")
            }

            Section("本次营养预览") {
                if let adjustedCalories {
                    LabeledContent(
                        "热量",
                        value: interfaceCalorieText(
                            adjustedCalories.kcalText,
                            locale: locale
                        )
                    )
                }
                nutritionRow("蛋白质", value: food.protein)
                nutritionRow("碳水", value: food.carbs)
                nutritionRow("脂肪", value: food.fat)
                if food.caffeineMg != nil {
                    nutritionRow("咖啡因", value: food.caffeineMg, unit: "mg")
                }

                if let ratio {
                    LabeledContent(
                        "本次份量",
                        value: adjustedPortionText(ratio: ratio)
                    )
                }
            }
        }
        .navigationTitle("自定义比例")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: onCancel)
                    .disabled(isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { ratioFocused = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
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
            Text(interfaceLocalized(saveError ?? "请稍后重试", locale: locale))
        }
    }

    private func ratioButton(_ value: Double) -> some View {
        let selected = ratio.map { abs($0 - value) < 0.000_001 } ?? false
        let identifier = PortionRatioEngine.formattedForEditing(
            value,
            locale: Locale(identifier: "en_US_POSIX")
        )
        return Button {
            ratioText = PortionRatioEngine.formattedForEditing(
                value,
                locale: locale
            )
            ratioFocused = false
        } label: {
            Text("×\(PortionRatioEngine.formattedForDisplay(value, locale: locale))")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .background(selected ? Color.accentColor : Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(
            "history_food_ratio_\(identifier)"
        )
    }

    @ViewBuilder
    private func nutritionRow(
        _ label: String,
        value: Double?,
        unit: String = "g"
    ) -> some View {
        if let ratio,
           let value,
           value.isFinite,
           value >= 0,
           (value * ratio).isFinite {
            LabeledContent {
                Text("\(numberText(value * ratio)) \(unit)")
            } label: {
                Text(interfaceLocalized(label, locale: locale))
            }
        } else if value == nil {
            LabeledContent {
                Text("—")
            } label: {
                Text(interfaceLocalized(label, locale: locale))
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .tint(.white)
                    Text("正在保存…")
                } else if let adjustedCalories {
                    Text(
                        "\(interfaceLocalized("确认记录", locale: locale)) · \(interfaceCalorieText(adjustedCalories.kcalText, locale: locale))"
                    )
                        .font(.headline)
                } else {
                    Text("确认记录")
                        .font(.headline)
                }
                Spacer()
            }
            .frame(minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .disabled(ratio == nil || adjustedCalories == nil || isSaving)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("history_food_save_button")
    }

    private var ratioErrorText: String? {
        guard case .failure(let error) = ratioResult else { return nil }
        let key: String
        switch error {
        case .empty:
            key = "请输入食用比例。"
        case .negative, .mustBePositive, .divisionByZero:
            key = "请输入大于 0 的有效比例。"
        case .exceedsMaximum:
            key = "份量比例不能超过 10 倍。"
        case .invalidFormat, .notFinite:
            key = "比例格式不正确，请输入 3/4、0.75 或 1.3。"
        }
        return interfaceLocalized(key, locale: locale)
    }

    private var originalPortionText: String {
        nonempty(food.portionText)
            ?? interfaceLocalized("按上次记录", locale: locale)
    }

    private var todayText: String {
        let today = dateText(.now, dateStyle: .medium, timeStyle: .none)
        return "\(interfaceLocalized("今天", locale: locale)) · \(today)"
    }

    private func adjustedPortionText(ratio: Double) -> String {
        guard abs(ratio - 1) >= 0.000_001 else {
            return originalPortionText
        }
        return "\(originalPortionText) × \(PortionRatioEngine.formattedForDisplay(ratio, locale: locale))"
    }

    private func save() {
        let savedPortionText = ratio.flatMap { ratio in
            abs(ratio - 1) < 0.000_001
                ? nonempty(food.portionText)
                : adjustedPortionText(ratio: ratio)
        }
        guard !isSaving,
              let ratio,
              let draft = FoodEntryDraft(
                scaledRepeatOf: food,
                multiplier: ratio,
                portionText: savedPortionText,
                date: .now,
                mealType: mealType
              ) else {
            return
        }

        ratioFocused = false
        isSaving = true
        saveError = nil

        Task { @MainActor in
            do {
                let saved = try await FoodEntryWriter.save(
                    drafts: [draft],
                    context: modelContext,
                    health: health,
                    reminders: reminders
                )
                guard let entry = saved.first else {
                    throw HistoryFoodRepeatSaveError.missingSavedEntry
                }
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
                onSaved(entry)
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func timestampText(_ date: Date) -> String {
        dateText(date, dateStyle: .medium, timeStyle: .short)
    }

    private func dateText(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private func numberText(_ value: Double) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...1))
                .locale(locale)
        )
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum HistoryFoodRepeatSaveError: LocalizedError {
    case missingSavedEntry

    var errorDescription: String? {
        interfaceLocalized(
            "保存失败，请稍后重试。",
            locale: AppLanguage.sharedSelection().locale
        )
    }
}
