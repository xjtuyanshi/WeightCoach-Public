import SwiftUI
import SwiftData

/// 找不到可靠参考值时，录入用户自己确认的热量与营养。
struct AddFoodManualView: View {
    let defaultDate: Date
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.locale) private var locale

    @State private var name: String
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var caffeineText = ""
    @State private var portionText = ""
    @State private var mealType: MealType = .snack
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case calories
        case portion
        case protein
        case carbs
        case fat
        case caffeine
    }

    init(
        defaultDate: Date,
        initialName: String = "",
        onSaved: (() -> Void)? = nil
    ) {
        self.defaultDate = defaultDate
        self.onSaved = onSaved
        _name = State(initialValue: initialName)
    }

    private var calories: Double? {
        ManualNutritionInput.nonnegativeNumber(from: caloriesText)
    }

    private var optionalNutritionFieldsAreValid: Bool {
        [proteinText, carbsText, fatText, caffeineText].allSatisfy(
            ManualNutritionInput.isValidOptionalNumber
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (calories ?? -1) >= 0
            && optionalNutritionFieldsAreValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("食物信息") {
                    TextField("名称（如：牛肉面）", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .calories }
                    TextField("热量（千卡）", text: $caloriesText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .calories)
                    TextField("份量描述（可选，如：一大碗）", text: $portionText)
                        .focused($focusedField, equals: .portion)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .protein }
                    Picker("餐次", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Text(interfaceLocalized(meal.label, locale: locale)).tag(meal)
                        }
                    }
                }

                Section("营养素（可选，克）") {
                    TextField("蛋白质", text: $proteinText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .protein)
                    TextField("碳水化合物", text: $carbsText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .carbs)
                    TextField("脂肪", text: $fatText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .fat)
                    if !optionalNutritionFieldsAreValid {
                        Label("营养素请填写大于或等于 0 的数字；留空表示不知道", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("咖啡因（毫克）", text: $caffeineText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .caffeine)
                } header: {
                    Text("咖啡因（可选）")
                } footer: {
                    Text("留空表示不知道；明确不含咖啡因可填写 0。")
                }
            }
            .navigationTitle("自行填写")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                    }
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
                            "\(interfaceLocalized("确认记录", locale: locale)) · \(interfaceCalorieText((calories ?? 0).kcalText, locale: locale))"
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
            .onAppear {
                mealType = MealType.suggested(for: defaultDate)
                focusedField = name.isEmpty ? .name : .calories
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
                if let saveError {
                    Text(interfaceLocalized(saveError, locale: locale))
                } else {
                    Text("请稍后重试")
                }
            }
        }
    }

    private func save() {
        guard let kcal = calories, !isSaving else { return }
        let draft = FoodEntryDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: kcal,
            protein: ManualNutritionInput.optionalNonnegativeNumber(from: proteinText),
            carbs: ManualNutritionInput.optionalNonnegativeNumber(from: carbsText),
            fat: ManualNutritionInput.optionalNonnegativeNumber(from: fatText),
            portionText: portionText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            mealType: mealType,
            source: .manual,
            date: defaultDate,
            caffeineMg: ManualNutritionInput.optionalNonnegativeNumber(from: caffeineText)
        )
        persist(draft)
    }

    private func persist(_ draft: FoodEntryDraft) {
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
                onSaved?()
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
