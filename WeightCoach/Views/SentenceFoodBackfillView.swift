import SwiftData
import SwiftUI
import UIKit

enum SentenceFoodBackfillPrivacyPolicy {
    static let cloudTextConsentKey = "recognition.cloudTextConsent.v1"
}

/// 用一句自然语言补记多项饮食；AI 只负责估算，日期、餐次和最终写入始终由用户确认。
struct SentenceFoodBackfillView: View {
    let defaultDate: Date
    private let recognitionProvider: any FoodTextRecognitionProviding

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler

    @AppStorage(SentenceFoodBackfillPrivacyPolicy.cloudTextConsentKey)
    private var hasCloudTextConsent = false
    @State private var descriptionText = ""
    @State private var analyzedText: String?
    @State private var selectedDate: Date
    @State private var mealType: MealType
    @State private var foods: [RecognizedFood] = []
    @State private var confirmedFoodIDs: Set<UUID> = []
    @State private var manualFoodIDs: Set<UUID> = []
    @State private var timingConfirmed = false
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var showCloudConsentAlert = false
    @State private var didStartDemo = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var activeAnalysisRequestID: UUID?
    @State private var outstandingRemoteRequestIDs: Set<UUID> = []
    @FocusState private var inputIsFocused: Bool

    init(
        defaultDate: Date,
        recognitionProvider: (any FoodTextRecognitionProviding)? = nil
    ) {
        let boundedDate = min(defaultDate, Date.now)
        self.defaultDate = boundedDate
        self.recognitionProvider = recognitionProvider
            ?? FoodTextRecognitionProviderFactory.make()
        _selectedDate = State(initialValue: boundedDate)
        _mealType = State(initialValue: MealType.suggested(for: boundedDate))
    }

    private var totalCalories: Double {
        foods.reduce(0) { $0 + $1.calories }
    }

    private var allFoodsConfirmed: Bool {
        !foods.isEmpty && foods.allSatisfy { confirmedFoodIDs.contains($0.id) }
    }

    private var analysisMatchesCurrentText: Bool {
        guard let analyzedText,
              let currentText = try? FoodTextRecognitionInput.validated(descriptionText)
        else {
            return false
        }
        return analyzedText == currentText
    }

    private var canSave: Bool {
        guard timingConfirmed,
              allFoodsConfirmed,
              analysisMatchesCurrentText,
              !isAnalyzing,
              !isSaving else {
            return false
        }

        let now = Date.now
        return (try? SentenceFoodDraftBuilder.makeDrafts(
            from: foods,
            confirmedFoodIDs: confirmedFoodIDs,
            authoritativeDate: authoritativeDate(now: now),
            authoritativeMealType: mealType,
            manualFoodIDs: manualFoodIDs,
            now: now
        )) != nil
    }

    private func authoritativeDate(now: Date) -> Date {
        if Calendar.current.isDateInToday(selectedDate) {
            return now
        }
        return Calendar.current.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: selectedDate
        ) ?? selectedDate
    }

    private var providerAvailabilityMessage: String? {
        guard case .unavailable(let message) = recognitionProvider.availability else {
            return nil
        }
        return message
    }

    var body: some View {
        NavigationStack {
            List {
                inputSection

                if let providerAvailabilityMessage {
                    Section {
                        Label(
                            interfaceLocalized(providerAvailabilityMessage, locale: locale),
                            systemImage: "desktopcomputer.trianglebadge.exclamationmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                if usesCloudRecognition && hasCloudTextConsent {
                    Section {
                        Label(
                            uiText("已允许通过 Mac mini 发送饮食文字到 ChatGPT/OpenAI 云端分析"),
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.green)

                        Button(uiText("撤销云端文字估算授权"), role: .destructive) {
                            hasCloudTextConsent = false
                            errorMessage = uiText("已撤销授权；以后识别前会再次征求同意。")
                        }
                        .font(.footnote)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !foods.isEmpty {
                    timingSection
                    resultsSection
                }
            }
            .listSectionSpacing(14)
            .disabled(isSaving)
            .navigationTitle(uiText("一句话补记"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(uiText("取消")) { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !foods.isEmpty {
                    saveBar
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task {
                guard DemoMode.demoSentenceBackfillEnabled, !didStartDemo else {
                    return
                }
                didStartDemo = true
                descriptionText = uiText("我今天吃了一根烤肠、两个鸡翅")
                startAnalysis()
            }
            .onDisappear {
                cancelAnalysis()
            }
            .alert(uiText("允许云端分析这段饮食描述？"), isPresented: $showCloudConsentAlert) {
                Button(uiText("取消"), role: .cancel) {
                    errorMessage = uiText("内容仍保留在本页，尚未发送。")
                }
                Button(uiText("允许并开始估算")) {
                    hasCloudTextConsent = true
                    startAnalysis()
                }
            } message: {
                Text(
                    uiText(
                        "文字会发送到你配置的 Mac mini，再由 Mac mini 使用已登录的 ChatGPT 云端估算。App 不保存 API Key，也不会跳转到 ChatGPT。"
                    )
                )
            }
        }
    }

    private var inputSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if descriptionText.isEmpty {
                    Text(uiText("例如：我今天吃了一根烤肠、两个鸡翅"))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $descriptionText)
                    .focused($inputIsFocused)
                    .frame(minHeight: 88)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(uiText("饮食描述"))
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    descriptionCharacterCount
                    estimateButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack {
                    descriptionCharacterCount
                    Spacer()
                    estimateButton
                }
            }

            if !foods.isEmpty && !analysisMatchesCurrentText {
                Label(
                    uiText("描述已修改，请重新估算后再记录。"),
                    systemImage: "arrow.clockwise.circle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        } header: {
            Text(uiText("说说你吃了什么"))
        } footer: {
            Text(uiText("可以一次写多种食物和数量。AI 只提供估算，保存前请逐项核对。"))
        }
    }

    private var descriptionCharacterCount: some View {
        Text("\(descriptionText.count)/\(FoodTextRecognitionInput.maximumCharacterCount)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(
                descriptionText.count > FoodTextRecognitionInput.maximumCharacterCount
                    ? .red
                    : .secondary
            )
    }

    private var estimateButton: some View {
        Button {
            beginAnalysis()
        } label: {
            Group {
                if isAnalyzing {
                    Label(uiText("正在估算…"), systemImage: "hourglass")
                } else {
                    Label(
                        uiText(foods.isEmpty ? "使用 AI 估算" : "重新估算"),
                        systemImage: "sparkles"
                    )
                }
            }
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isAnalyzing || isSaving)
    }

    private var timingSection: some View {
        Section(uiText("记录到")) {
            DatePicker(
                uiText("日期"),
                selection: $selectedDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .onChange(of: selectedDate) { _, _ in
                timingConfirmed = false
            }
            Picker(uiText("餐次"), selection: $mealType) {
                ForEach(MealType.allCases) { meal in
                    Label(uiText(meal.label), systemImage: meal.systemImage)
                        .tag(meal)
                }
            }
            .onChange(of: mealType) { _, _ in
                timingConfirmed = false
            }
            Toggle(uiText("已核对日期和餐次"), isOn: $timingConfirmed)
                .font(.subheadline.bold())
                .tint(.green)
        }
    }

    private var resultsSection: some View {
        Section {
            ForEach($foods) { $food in
                resultEditor(food: $food)
            }
            .onDelete(perform: deleteFoods)

            Button {
                appendManualFood()
            } label: {
                Label(uiText("添加遗漏食物"), systemImage: "plus.circle")
            }

            HStack {
                Text(uiText("合计"))
                Spacer()
                Text(interfaceCalorieText(totalCalories.kcalText, locale: locale))
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            Text(uiText("估算结果 · 请逐项核对"))
        } footer: {
            Text(
                uiText(
                    "文字描述看不到实际大小、品牌、烹调油或酱汁。修改名称、份量或热量后，勾选每一项的“已核对”再记录。"
                )
            )
        }
    }

    private func resultEditor(food: Binding<RecognizedFood>) -> some View {
        let value = food.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            TextField(uiText("食物名称"), text: nameBinding(for: food))
                .font(.headline)

            TextField(uiText("份量，例如 1 根"), text: portionBinding(for: food))
                .textInputAutocapitalization(.never)

            HStack {
                Text(uiText("热量"))
                Spacer()
                TextField(
                    uiText("千卡"),
                    value: caloriesBinding(for: food),
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                Text(uiText("千卡"))
                    .foregroundStyle(.secondary)
            }

            if !value.calories.isFinite
                || value.calories <= 0
                || value.calories > SentenceFoodDraftBuilder.maximumCalories {
                Label(
                    uiText("单项热量需在 1–5000 千卡之间"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if value.protein != nil || value.carbs != nil || value.fat != nil {
                Text(macroSummary(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lower = value.calorieLowerBound,
               let upper = value.calorieUpperBound {
                Label(
                    "\(uiText("估算范围")) \(lower.kcalText)–\(upper.kcalText)",
                    systemImage: "arrow.left.and.right"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let note = value.note,
               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle(
                uiText("已核对名称、份量和热量"),
                isOn: confirmationBinding(for: value.id)
            )
            .font(.subheadline.bold())
            .tint(.green)
        }
        .padding(.vertical, 4)
    }

    private var saveBar: some View {
        VStack(spacing: 6) {
            Button {
                saveAll()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("\(uiText("确认并记录"))（\(foods.count)）")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)

            if !timingConfirmed {
                Text(uiText("请先核对日期和餐次"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !allFoodsConfirmed {
                Text(uiText("请先核对并勾选每一项"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func confirmationBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { confirmedFoodIDs.contains(id) },
            set: { isConfirmed in
                if isConfirmed {
                    confirmedFoodIDs.insert(id)
                } else {
                    confirmedFoodIDs.remove(id)
                }
            }
        )
    }

    private func nameBinding(for food: Binding<RecognizedFood>) -> Binding<String> {
        Binding(
            get: { food.wrappedValue.name },
            set: { newValue in
                let bounded = String(
                    newValue.prefix(SentenceFoodDraftBuilder.maximumNameLength)
                )
                guard bounded != food.wrappedValue.name else { return }
                var updated = food.wrappedValue
                updated.name = bounded
                SentenceFoodReviewMutation.invalidateDerivedEstimate(&updated)
                food.wrappedValue = updated
                confirmedFoodIDs.remove(updated.id)
            }
        )
    }

    private func portionBinding(for food: Binding<RecognizedFood>) -> Binding<String> {
        Binding(
            get: { food.wrappedValue.portion },
            set: { newValue in
                let bounded = String(
                    newValue.prefix(SentenceFoodDraftBuilder.maximumPortionLength)
                )
                guard bounded != food.wrappedValue.portion else { return }
                var updated = food.wrappedValue
                updated.portion = bounded
                SentenceFoodReviewMutation.invalidateDerivedEstimate(&updated)
                food.wrappedValue = updated
                confirmedFoodIDs.remove(updated.id)
            }
        )
    }

    private func caloriesBinding(for food: Binding<RecognizedFood>) -> Binding<Double> {
        Binding(
            get: { food.wrappedValue.calories },
            set: { newValue in
                guard newValue != food.wrappedValue.calories else { return }
                var updated = food.wrappedValue
                updated.calories = newValue
                SentenceFoodReviewMutation.invalidateDerivedEstimate(&updated)
                food.wrappedValue = updated
                confirmedFoodIDs.remove(updated.id)
            }
        )
    }

    private func beginAnalysis() {
        inputIsFocused = false
        errorMessage = nil
        do {
            _ = try FoodTextRecognitionInput.validated(descriptionText)
        } catch {
            errorMessage = localizedErrorMessage(error)
            return
        }

        guard providerAvailabilityMessage == nil else {
            errorMessage = providerAvailabilityMessage.map {
                interfaceLocalized($0, locale: locale)
            }
            return
        }

        if usesCloudRecognition && !hasCloudTextConsent {
            showCloudConsentAlert = true
            return
        }

        startAnalysis()
    }

    @MainActor
    private func analyzeCurrentText(requestID: UUID) async {
        guard activeAnalysisRequestID == requestID else { return }
        isAnalyzing = true
        defer {
            if activeAnalysisRequestID == requestID {
                isAnalyzing = false
                activeAnalysisRequestID = nil
                analysisTask = nil
            }
        }

        let validatedText: String
        do {
            validatedText = try FoodTextRecognitionInput.validated(descriptionText)
        } catch {
            if activeAnalysisRequestID == requestID {
                errorMessage = localizedErrorMessage(error)
            }
            return
        }
        errorMessage = nil
        // 保留上一版可编辑结果用于失败恢复，但在新结果返回前禁止把旧估算保存。
        analyzedText = nil
        confirmedFoodIDs = []
        do {
            let recognized = try await recognitionProvider.analyze(
                text: validatedText,
                outputLanguage: AppLanguage.system.resolvedLanguage(systemLocale: locale),
                requestID: requestID
            )
            try Task.checkCancellation()
            guard activeAnalysisRequestID == requestID else { return }
            outstandingRemoteRequestIDs.remove(requestID)
            guard !recognized.isEmpty else {
                throw MacMiniFoodRecognitionError.invalidResponse
            }
            foods = recognized
            confirmedFoodIDs = []
            manualFoodIDs = []
            timingConfirmed = false
            analyzedText = validatedText
        } catch is CancellationError {
            // 本地 Task 取消不等于远端进程已停止；ID 会保留给重试或关闭页清理。
        } catch {
            let cancellationConfirmed = await recognitionProvider
                .cancelTextAnalysis(requestID: requestID)
            if cancellationConfirmed {
                outstandingRemoteRequestIDs.remove(requestID)
            }
            if activeAnalysisRequestID == requestID {
                errorMessage = localizedErrorMessage(error)
            }
        }
    }

    private func startAnalysis() {
        let previousRequestIDs = outstandingRemoteRequestIDs
        analysisTask?.cancel()
        analysisTask = nil
        let requestID = UUID()
        activeAnalysisRequestID = requestID
        outstandingRemoteRequestIDs.insert(requestID)
        isAnalyzing = true
        analysisTask = Task {
            var cancellationFailed = false
            for previousRequestID in previousRequestIDs {
                // 串行等待桥接确认旧任务已退出且共享识别槽已释放。
                let confirmed = await recognitionProvider.cancelTextAnalysis(
                    requestID: previousRequestID
                )
                guard !Task.isCancelled else { return }
                if confirmed {
                    outstandingRemoteRequestIDs.remove(previousRequestID)
                } else {
                    cancellationFailed = true
                }
            }
            guard activeAnalysisRequestID == requestID else { return }
            guard !cancellationFailed else {
                // 新 ID 尚未发出；只保留未被确认停止的旧 ID，供下次重试继续清理。
                outstandingRemoteRequestIDs.remove(requestID)
                activeAnalysisRequestID = nil
                analysisTask = nil
                isAnalyzing = false
                errorMessage = uiText(
                    "上一次估算尚未确认停止，请检查 Mac mini 连接后再试。"
                )
                return
            }
            await analyzeCurrentText(requestID: requestID)
        }
    }

    private func cancelAnalysis() {
        let requestIDs = outstandingRemoteRequestIDs
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRequestID = nil
        isAnalyzing = false
        guard !requestIDs.isEmpty else { return }
        // 这是独立的清理 Task，不会随上面的分析 Task 一起被取消。
        Task {
            for requestID in requestIDs {
                _ = await recognitionProvider.cancelTextAnalysis(
                    requestID: requestID
                )
            }
        }
    }

    private func appendManualFood() {
        let food = RecognizedFood(
            name: uiText("遗漏食物"),
            portion: uiText("1 份"),
            calories: 100,
            needsConfirmation: true,
            note: uiText("手动补充，请修改为实际内容并核对。"),
            inputKind: .textDescription
        )
        foods.append(food)
        manualFoodIDs.insert(food.id)
        confirmedFoodIDs.remove(food.id)
    }

    private func deleteFoods(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { index in
            foods.indices.contains(index) ? foods[index].id : nil
        }
        foods.remove(atOffsets: offsets)
        confirmedFoodIDs.subtract(removedIDs)
        manualFoodIDs.subtract(removedIDs)
    }

    private func saveAll() {
        guard canSave, !isSaving else { return }
        let drafts: [FoodEntryDraft]
        do {
            let now = Date.now
            drafts = try SentenceFoodDraftBuilder.makeDrafts(
                from: foods,
                confirmedFoodIDs: confirmedFoodIDs,
                authoritativeDate: authoritativeDate(now: now),
                authoritativeMealType: mealType,
                manualFoodIDs: manualFoodIDs,
                now: now
            )
        } catch {
            errorMessage = uiText("请检查每一项的名称、份量和热量。")
            return
        }

        isSaving = true
        Task { @MainActor in
            do {
                _ = try await FoodEntryWriter.save(
                    drafts: drafts,
                    context: modelContext,
                    health: health,
                    reminders: reminders
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = localizedErrorMessage(error)
                isSaving = false
            }
        }
    }

    private var usesCloudRecognition: Bool {
        !(DemoMode.isActive && !DemoMode.realRecognitionEnabled)
    }

    private func macroSummary(_ food: RecognizedFood) -> String {
        [
            food.protein.map { "\(uiText("蛋白质")) \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
            food.carbs.map { "\(uiText("碳水")) \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
            food.fat.map { "\(uiText("脂肪")) \($0.formatted(.number.precision(.fractionLength(0...1)))) g" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        if let inputError = error as? FoodTextRecognitionInputError {
            return inputError.message(locale: locale)
        }
        if let bridgeError = error as? MacMiniFoodRecognitionError {
            return bridgeError.message(locale: locale)
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return interfaceLocalized(description, locale: locale)
        }
        return uiText("估算失败，请稍后重试或手动记录。")
    }

    private func uiText(_ key: String) -> String {
        interfaceLocalized(key, locale: locale)
    }
}
