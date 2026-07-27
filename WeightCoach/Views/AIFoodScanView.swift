import PhotosUI
import SwiftData
import SwiftUI

/// 默认极速路径：打开相机 → 一次快门 → 自动识别 → 底部确认。
struct AIFoodScanView: View {
    let defaultDate: Date
    private let recognitionProvider: any FoodRecognitionProviding

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler

    @AppStorage(AIFoodScanPrivacyPolicy.cloudPhotoConsentKey)
    private var hasCloudPhotoConsent = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var preparedImage: PreparedFoodImage?
    @State private var activeCaptureID: UUID?
    @State private var showCamera = false
    @State private var isPreparing = false
    @State private var isAnalyzing = false
    @State private var showSlowAnalysisHint = false
    @State private var foods: [RecognizedFood] = []
    @State private var errorMessage: String?
    @State private var mealType: MealType = .snack
    @State private var isSaving = false
    @State private var didStartInitialCapture = false
    @State private var didReceiveRecognitionResult = false
    @State private var didRecognizeReceiptOrMenu = false
    @State private var recognizedInputKind: RecognitionInputKind?
    @State private var manuallyAddedFoodIDs: Set<UUID> = []
    @State private var originalRecognizedFoods: [UUID: RecognizedFood] = [:]
    @State private var selectedOrderShare: RecognitionOrderShare?
    @State private var receiptReviewConfirmation: ReceiptReviewConfirmation = .none
    @State private var quickAdjustmentUndo: QuickAdjustmentUndo?
    @State private var clarificationSession = RecognitionClarificationSession()
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var activePhotoSelectionID: UUID?
    @State private var preparationTask: Task<Void, Never>?
    @State private var analysisTask: Task<Void, Never>?
    @State private var showCloudConsentAlert = false

    init(
        defaultDate: Date,
        recognitionProvider: (any FoodRecognitionProviding)? = nil
    ) {
        self.defaultDate = defaultDate
        self.recognitionProvider = recognitionProvider ?? FoodRecognitionProviderFactory.make()
    }

    private var totalCalories: Double {
        foods.reduce(0) { $0 + $1.calories }
    }

    private var canSave: Bool {
        saveBlockReason == nil
    }

    private var saveBlockReason: AIFoodScanSaveBlockReason? {
        AIFoodScanSavePolicy.blockReason(
            foods: foods,
            inputWasReceiptOrMenu: didRecognizeReceiptOrMenu,
            isPreparing: isPreparing,
            isAnalyzing: isAnalyzing,
            receiptConfirmation: receiptReviewConfirmation
        )
    }

    var body: some View {
        NavigationStack {
            List {
                availabilitySection
                photoSection

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        if let recoveryMessage {
                            Label(recoveryMessage, systemImage: "photo.badge.checkmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            appendManualFood()
                        } label: {
                            Label(uiText("手动添加一项"), systemImage: "plus.circle")
                        }
                    }
                }

                if !foods.isEmpty {
                    clarificationSection
                    resultSection
                }
            }
            .disabled(isSaving)
            .navigationTitle(uiText("拍照识别"))
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
            .task {
                mealType = MealType.suggested(for: defaultDate)
                startInitialCaptureIfNeeded()
            }
            .task(id: isAnalyzing) {
                guard isAnalyzing else {
                    showSlowAnalysisHint = false
                    return
                }
                showSlowAnalysisHint = false
                do {
                    try await Task.sleep(for: .seconds(8))
                } catch {
                    return
                }
                guard !Task.isCancelled, isAnalyzing else { return }
                showSlowAnalysisHint = true
            }
            .onDisappear {
                // 打开全屏相机时本页可能短暂不可见；不要因此取消当前草稿或识别。
                guard !showCamera else { return }
                photoLoadingTask?.cancel()
                preparationTask?.cancel()
                analysisTask?.cancel()
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                photoLoadingTask?.cancel()
                let selectionID = UUID()
                activePhotoSelectionID = selectionID
                beginLoadingPhoto(selectionID: selectionID)
                photoLoadingTask = Task {
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self) else {
                            throw FoodImagePreparationError.emptyImageData
                        }
                        try Task.checkCancellation()
                        guard activePhotoSelectionID == selectionID else { return }
                        acceptImageData(data, captureID: selectionID)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard activePhotoSelectionID == selectionID else { return }
                        isPreparing = false
                        errorMessage = localizedErrorMessage(error)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                FastFoodCameraView { photo in
                    guard showCamera else { return }
                    showCamera = false
                    cancelPendingPhotoSelection()
                    acceptImageData(photo.data, captureID: photo.captureID)
                } onCancel: {
                    showCamera = false
                }
            }
            .alert(uiText("允许云端分析这张照片？"), isPresented: $showCloudConsentAlert) {
                Button(uiText("取消"), role: .cancel) {
                    errorMessage = uiText("照片和当前草稿已保留，尚未发送到云端。")
                }
                Button(uiText("允许并开始识别")) {
                    hasCloudPhotoConsent = true
                    analyzePreparedImage()
                }
            } message: {
                Text(
                    uiText(
                        "识别会通过你的 Mac mini 将照片发送到 ChatGPT/OpenAI 云端处理。桥接使用 --ephemeral 只表示本地 Codex 会话不保留，不代表照片未上传或云端未处理。你可以稍后在本页撤销授权。"
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var availabilitySection: some View {
        switch recognitionProvider.availability {
        case .available:
            if usesCloudRecognition, hasCloudPhotoConsent {
                Section {
                    Label(
                        uiText("已允许通过 Mac mini 发送照片到 ChatGPT/OpenAI 云端分析"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.green)

                    Button(uiText("撤销云端照片识别授权"), role: .destructive) {
                        hasCloudPhotoConsent = false
                        errorMessage = uiText("已撤销授权；以后识别前会再次征求同意。")
                    }
                    .font(.footnote)
                }
            } else if DemoMode.realRecognitionEnabled {
                Section {
                    Label(
                        uiText("真实桥接验收：Mac mini + ChatGPT 订阅"),
                        systemImage: "checkmark.shield.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } else if DemoMode.isActive {
                Section {
                    Label(
                        uiText("演示识别结果，仅用于验证交互"),
                        systemImage: "play.circle.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
            }
        case .unavailable(let message):
            Section {
                Label(uiText(message), systemImage: "desktopcomputer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var photoSection: some View {
        Section(uiText("餐盘、菜单或账单照片")) {
            if let preparedImage {
                if foods.isEmpty {
                    Image(uiImage: preparedImage.displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 230)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .listRowBackground(Color.clear)
                } else {
                    HStack(spacing: 12) {
                        Image(uiImage: preparedImage.displayImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Label(uiText("照片已准备"), systemImage: "checkmark.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                            Text(uiText("识别结果已显示在下方，可直接确认或修改"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if !isPreparing {
                ContentUnavailableView(
                    uiText("拍餐盘或餐厅账单"),
                    systemImage: "camera.viewfinder",
                    description: Text(uiText(initialPhotoDescription))
                )
            }

            if isPreparing || isAnalyzing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(isPreparing ? uiText("正在快速处理照片…") : analysisProgressText)
                            .font(.subheadline)
                    }
                    if isAnalyzing, showSlowAnalysisHint {
                        Text(
                            RecognitionRecoveryPresentation.slowAnalysisMessage(
                                locale: locale
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isAnalyzing {
                        Button {
                            stopAnalyzingAndKeepDraft()
                        } label: {
                            Label(
                                uiText("停止等待，保留本次照片"),
                                systemImage: "pause.circle"
                            )
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }
                }
            }

            HStack {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        cancelPendingPhotoSelection()
                        showCamera = true
                    } label: {
                        Label(
                            uiText(preparedImage == nil ? "拍照" : "重拍"),
                            systemImage: "camera"
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(isPreparing || isAnalyzing || isSaving)
                    Spacer()
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(uiText("从相册选择"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                .disabled(isPreparing || isAnalyzing || isSaving)

                if preparedImage != nil,
                   case .available = recognitionProvider.availability,
                   !isPreparing {
                    Spacer()
                    Button {
                        analyzePreparedImage()
                    } label: {
                        Label(uiText("重试识别"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isAnalyzing)
                }
            }

            if foods.isEmpty, !isPreparing, !isAnalyzing {
                Button {
                    appendManualFood()
                } label: {
                    Label(
                        uiText("不拍照，直接手动填写"),
                        systemImage: "square.and.pencil"
                    )
                }
            }
        }
    }

    private var resultSection: some View {
        Section {
            if isReceiptOrMenu {
                receiptShareControls
            }

            ForEach(foods) { food in
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        uiText("食物名称"),
                        text: manualBinding(
                            for: food.id,
                            keyPath: \.name,
                            fallback: food.name
                        )
                    )
                        .font(.subheadline.bold())
                    HStack(spacing: 10) {
                        TextField(
                            uiText("份量（如：约 180 克）"),
                            text: manualBinding(
                                for: food.id,
                                keyPath: \.portion,
                                fallback: food.portion
                            )
                        )
                            .font(.caption)
                        TextField(
                            uiText("千卡"),
                            value: manualBinding(
                                for: food.id,
                                keyPath: \.calories,
                                fallback: food.calories
                            ),
                            format: .number
                        )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 74)
                        Text(uiText("千卡"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if food.needsConfirmation {
                            Label(
                                uiText("请核对份量"),
                                systemImage: "exclamationmark.circle.fill"
                            )
                                .foregroundStyle(.orange)
                        }
                        if let confidence = food.confidence {
                            Text(confidenceDescription(confidence))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    if let summary = nutritionSummary(food) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let lower = food.calorieLowerBound,
                       let upper = food.calorieUpperBound {
                        Label(
                            "\(uiText("合理范围")) "
                                + "\(lower.kcalText)–\(upper.kcalText) "
                                + uiText("千卡"),
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if let note = food.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !manuallyAddedFoodIDs.contains(food.id), food.calories > 0 {
                        quickAdjustmentControls(for: food)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete(perform: deleteFoods)

            if let quickAdjustmentUndo {
                Button {
                    undoLastQuickAdjustment()
                } label: {
                    Label(
                        "\(uiText("撤销"))：\(quickAdjustmentUndo.actionDescription)",
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .foregroundStyle(.orange)
            }

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

            Picker(uiText("餐次"), selection: $mealType) {
                ForEach(MealType.allCases) { meal in
                    Text(uiText(meal.label)).tag(meal)
                }
            }
        } header: {
            Text(
                uiText(
                    isReceiptOrMenu
                        ? "账单菜品 · 请确认实际吃了多少"
                        : "识别结果 · 请确认份量"
                )
            )
        } footer: {
            Text(
                uiText(
                    isReceiptOrMenu
                        ? "账单只能提供菜名和购买数量，看不到实际大小、烹调油、剩菜或谁吃了哪一份。整单比例和逐项修正都会同比调整已有估算，最终以你确认的内容保存。"
                        : "照片识别只能提供估算。快捷倍数按原识别值同比调整已有营养，未知营养不会补填；油量会单独标为估算，酱汁不会自动估算。最终记录使用你在这里确认后的数值。"
                )
            )
        }
    }

    private var isReceiptOrMenu: Bool {
        didRecognizeReceiptOrMenu
    }

    private var receiptShareControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(uiText("已识别为账单或菜单"), systemImage: "receipt")
                .font(.subheadline.bold())
                .foregroundStyle(.green)

            Text(uiText("下面先按整张账单列出。你大约吃了这份订单的多少？"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecognitionOrderShare.allCases, id: \.factor) { share in
                        Button {
                            applyOrderShare(share)
                        } label: {
                            Label(
                                share.localizedButtonTitle(locale: locale),
                                systemImage: selectedOrderShare == share
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(selectedOrderShare == share ? .green : Color.accentColor)
                        .accessibilityLabel(
                            "\(uiText("整单食用比例")) "
                                + share.localizedAccessibilityTitle(locale: locale)
                                + ", "
                                + uiText(
                                    selectedOrderShare == share
                                        ? "已选择"
                                        : "未选择"
                                )
                        )
                        .accessibilityHint(
                            uiText("选择后会按该比例调整账单中所有识别项目")
                        )
                    }
                }
            }

            Button {
                if receiptReviewConfirmation == .reviewedItems {
                    receiptReviewConfirmation = selectedOrderShare == nil
                        ? .none
                        : .orderShare
                } else {
                    receiptReviewConfirmation = .reviewedItems
                }
                errorMessage = nil
            } label: {
                Label(
                    uiText("我已逐项核对"),
                    systemImage: receiptReviewConfirmation == .reviewedItems
                        ? "checkmark.square.fill"
                        : "square"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(receiptReviewConfirmation == .reviewedItems ? .green : Color.accentColor)
            .accessibilityLabel(
                uiText(
                    receiptReviewConfirmation == .reviewedItems
                        ? "我已逐项核对，已确认"
                        : "我已逐项核对，未确认"
                )
            )

            Text(uiText("选完还可以逐项删除、改热量，或把某一道改回整份。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var clarificationSection: some View {
        if let clarification = activeClarification {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        clarification.prompt(locale: locale),
                        systemImage: "questionmark.circle.fill"
                    )
                        .foregroundStyle(.orange)

                    switch clarification.kind {
                    case .oilOrSauce:
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button(uiText("没有额外油酱")) {
                                    dismissClarification(for: clarification.foodID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(uiText("加 1 茶匙油")) {
                                    add(.teaspoonOfCookingOil, after: clarification.foodID)
                                    dismissClarification(for: clarification.foodID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(uiText("酱汁另算")) {
                                    add(.sauceNeedsConfirmation, after: clarification.foodID)
                                    dismissClarification(for: clarification.foodID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    case .portion:
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button(uiText("原估算差不多")) {
                                    dismissClarification(for: clarification.foodID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(uiText("约 ½ 份")) {
                                    apply(.half, to: clarification.foodID)
                                    dismissClarification(for: clarification.foodID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(uiText("约 1½ 份")) {
                                    apply(.oneAndHalf, to: clarification.foodID)
                                    dismissClarification(for: clarification.foodID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            } header: {
                Text(uiText("只确认这一项"))
            } footer: {
                Text(uiText("无需多角度拍摄；不确定时可直接编辑、重拍或稍后确认。"))
            }
        }
    }

    @ViewBuilder
    private func quickAdjustmentControls(for food: RecognizedFood) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(uiText("快捷修正（均可撤销）"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecognitionPortionMultiplier.allCases, id: \.factor) { multiplier in
                        Button(multiplier.localizedButtonTitle(locale: locale)) {
                            apply(multiplier, to: food.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(
                        [
                            RecognitionQuickAddition.teaspoonOfCookingOil,
                            .tablespoonOfCookingOil,
                            .sauceNeedsConfirmation,
                        ],
                        id: \.buttonTitle
                    ) { addition in
                        Button(addition.localizedButtonTitle(locale: locale)) {
                            add(addition, after: food.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 6) {
            if let saveBlockReason {
                Text(saveBlockReason.localizedMessage(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Button(action: saveAll) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(
                        isSaving
                            ? uiText("正在保存…")
                            : "\(uiText("确认记录")) · "
                                + interfaceCalorieText(
                                    totalCalories.kcalText,
                                    locale: locale
                                )
                    )
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }

    @MainActor
    private func startInitialCaptureIfNeeded() {
        guard !didStartInitialCapture else { return }
        didStartInitialCapture = true

        if DemoMode.demoCaptureEnabled, let data = DemoMode.demoFoodImageData() {
            acceptImageData(data, captureID: UUID())
        } else if case .available = recognitionProvider.availability,
                  UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        }
    }

    @MainActor
    private func acceptImageData(_ data: Data, captureID: UUID) {
        preparationTask?.cancel()
        analysisTask?.cancel()
        activeCaptureID = captureID
        errorMessage = nil
        isPreparing = true
        isAnalyzing = false
        showSlowAnalysisHint = false

        preparationTask = Task {
            do {
                let prepared = try await FoodImagePreparer.prepare(
                    imageData: data,
                    captureID: captureID
                )
                try Task.checkCancellation()
                guard activeCaptureID == prepared.captureID else { return }

                // 新图完成加载和预处理后才一次性替换旧照片与识别草稿。
                // 预处理失败时 catch 会保留此前所有可编辑内容。
                preparedImage = prepared
                foods = []
                didReceiveRecognitionResult = false
                didRecognizeReceiptOrMenu = false
                recognizedInputKind = nil
                manuallyAddedFoodIDs = []
                originalRecognizedFoods = [:]
                selectedOrderShare = nil
                receiptReviewConfirmation = .none
                quickAdjustmentUndo = nil
                clarificationSession.reset()
                isPreparing = false
                analyzePreparedImage()
            } catch is CancellationError {
                return
            } catch {
                guard activeCaptureID == captureID else { return }
                activeCaptureID = preparedImage?.captureID
                isPreparing = false
                errorMessage = localizedErrorMessage(error)
            }
        }
    }

    @MainActor
    private func analyzePreparedImage() {
        guard let preparedImage else { return }
        analysisTask?.cancel()
        errorMessage = nil

        let provider = recognitionProvider
        guard case .available = provider.availability else {
            if case .unavailable(let message) = provider.availability {
                errorMessage = message
            }
            return
        }

        guard !AIFoodScanPrivacyPolicy.needsConsent(
            usesCloudRecognition: usesCloudRecognition,
            hasConsent: hasCloudPhotoConsent
        ) else {
            isAnalyzing = false
            showSlowAnalysisHint = false
            showCloudConsentAlert = true
            return
        }

        let captureID = preparedImage.captureID
        let outputLanguage = AppLanguage.system.resolvedLanguage(
            systemLocale: locale
        )
        isAnalyzing = true
        showSlowAnalysisHint = false
        analysisTask = Task {
            do {
                let result = try await provider.analyze(
                    jpegData: preparedImage.recognitionJPEGData,
                    outputLanguage: outputLanguage
                )
                try Task.checkCancellation()
                guard activeCaptureID == captureID else { return }
                guard !result.isEmpty else {
                    didReceiveRecognitionResult = false
                    isAnalyzing = false
                    showSlowAnalysisHint = false
                    errorMessage = uiText(
                        "没有识别到明确的食物或账单菜品，请重拍、补全账单画面，或直接手动填写。"
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    return
                }
                foods = result
                didReceiveRecognitionResult = true
                recognizedInputKind = result.first?.inputKind
                didRecognizeReceiptOrMenu =
                    recognizedInputKind == .receiptOrMenu
                manuallyAddedFoodIDs = []
                originalRecognizedFoods = Dictionary(
                    uniqueKeysWithValues: result.map { ($0.id, $0) }
                )
                selectedOrderShare = nil
                receiptReviewConfirmation = .none
                quickAdjustmentUndo = nil
                clarificationSession.begin(with: result)
                isAnalyzing = false
                showSlowAnalysisHint = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return
            } catch {
                guard activeCaptureID == captureID else { return }
                errorMessage = localizedErrorMessage(error)
                isAnalyzing = false
                showSlowAnalysisHint = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func appendManualFood() {
        quickAdjustmentUndo = nil
        selectedOrderShare = nil
        let food = RecognizedFood(
            name: "",
            portion: "",
            calories: 0
        )
        foods.append(food)
        manuallyAddedFoodIDs.insert(food.id)
        errorMessage = nil
    }

    private func manualBinding<Value>(
        for foodID: UUID,
        keyPath: WritableKeyPath<RecognizedFood, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                foods.first(where: { $0.id == foodID })?[keyPath: keyPath] ?? fallback
            },
            set: { value in
                guard let index = foods.firstIndex(where: { $0.id == foodID }) else { return }
                foods[index][keyPath: keyPath] = value
                quickAdjustmentUndo = nil
                selectedOrderShare = nil
            }
        )
    }

    private func deleteFoods(at offsets: IndexSet) {
        let removedIDs = Set(offsets.compactMap { index in
            foods.indices.contains(index) ? foods[index].id : nil
        })
        foods.remove(atOffsets: offsets)
        manuallyAddedFoodIDs.subtract(removedIDs)
        for foodID in removedIDs {
            clarificationSession.dismiss(foodID: foodID)
        }
        quickAdjustmentUndo = nil
        selectedOrderShare = nil
    }

    private func stopAnalyzingAndKeepDraft() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        showSlowAnalysisHint = false
        errorMessage = RecognitionRecoveryPresentation.stoppedMessage(locale: locale)
    }

    private var activeClarification: RecognitionClarification? {
        clarificationSession.pending
    }

    private func dismissClarification(for foodID: UUID) {
        clarificationSession.dismiss(foodID: foodID)
    }

    private func apply(_ multiplier: RecognitionPortionMultiplier, to foodID: UUID) {
        guard let index = foods.firstIndex(where: { $0.id == foodID }) else { return }
        let original = originalRecognizedFoods[foodID] ?? foods[index]
        captureQuickAdjustmentUndo(
            "\(foods[index].name) · \(multiplier.localizedButtonTitle(locale: locale))"
        )
        foods[index] = multiplier.applying(to: original, locale: locale)
        selectedOrderShare = nil
    }

    private func applyOrderShare(_ share: RecognitionOrderShare) {
        let recognizedOriginals = foods.compactMap { food -> RecognizedFood? in
            guard !manuallyAddedFoodIDs.contains(food.id) else { return nil }
            return originalRecognizedFoods[food.id] ?? food
        }
        guard !recognizedOriginals.isEmpty else { return }

        captureQuickAdjustmentUndo(
            "\(uiText("整单按")) \(share.localizedButtonTitle(locale: locale))"
        )
        let adjustedByID = Dictionary(
            uniqueKeysWithValues: share
                .applying(to: recognizedOriginals, locale: locale)
                .map { ($0.id, $0) }
        )
        foods = foods.map { adjustedByID[$0.id] ?? $0 }
        selectedOrderShare = share
        receiptReviewConfirmation = .orderShare
        errorMessage = nil
    }

    private func add(_ addition: RecognitionQuickAddition, after foodID: UUID) {
        captureQuickAdjustmentUndo(addition.localizedButtonTitle(locale: locale))
        let food = addition.makeFood(locale: locale)
        if let index = foods.firstIndex(where: { $0.id == foodID }) {
            foods.insert(food, at: index + 1)
        } else {
            foods.append(food)
        }
        manuallyAddedFoodIDs.insert(food.id)
    }

    private func captureQuickAdjustmentUndo(_ actionDescription: String) {
        quickAdjustmentUndo = QuickAdjustmentUndo(
            foods: foods,
            manuallyAddedFoodIDs: manuallyAddedFoodIDs,
            selectedOrderShare: selectedOrderShare,
            receiptReviewConfirmation: receiptReviewConfirmation,
            actionDescription: actionDescription
        )
        errorMessage = nil
    }

    private func undoLastQuickAdjustment() {
        guard let quickAdjustmentUndo else { return }
        foods = quickAdjustmentUndo.foods
        manuallyAddedFoodIDs = quickAdjustmentUndo.manuallyAddedFoodIDs
        selectedOrderShare = quickAdjustmentUndo.selectedOrderShare
        receiptReviewConfirmation = quickAdjustmentUndo.receiptReviewConfirmation
        self.quickAdjustmentUndo = nil
        errorMessage = nil
    }

    private func saveAll() {
        guard canSave, !isSaving else { return }
        photoLoadingTask?.cancel()
        activePhotoSelectionID = nil
        isSaving = true
        let foodsToSave = foods
        let thumbnail = AIFoodScanSavePolicy.thumbnailJPEGData(
            preparedThumbnail: preparedImage?.thumbnailJPEGData,
            recognizedInputKind: recognizedInputKind
        )
        let mealTypeToSave = mealType
        let drafts = foodsToSave.enumerated().map { index, food in
            let retainsCalorieRange = food.calorieLowerBound.map { $0 <= food.calories } == true
                && food.calorieUpperBound.map { food.calories <= $0 } == true
            return FoodEntryDraft(
                name: food.name.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: food.calories,
                protein: food.protein,
                carbs: food.carbs,
                fat: food.fat,
                portionText: food.portion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : food.portion.trimmingCharacters(in: .whitespacesAndNewlines),
                mealType: mealTypeToSave,
                source: didReceiveRecognitionResult
                    && !manuallyAddedFoodIDs.contains(food.id)
                    ? .ai
                    : .manual,
                date: defaultDate,
                caffeineMg: food.caffeineMg,
                calorieLowerBound: retainsCalorieRange ? food.calorieLowerBound : nil,
                calorieUpperBound: retainsCalorieRange ? food.calorieUpperBound : nil,
                imageData: index == 0 ? thumbnail : nil
            )
        }

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

    private var recognitionIsAvailable: Bool {
        if case .available = recognitionProvider.availability {
            return true
        }
        return false
    }

    private var usesCloudRecognition: Bool {
        !(DemoMode.isActive && !DemoMode.realRecognitionEnabled)
    }

    private var initialPhotoDescription: String {
        recognitionIsAvailable
            ? "可拍餐盘、菜单或餐厅账单；真机打开会直接进入相机"
            : "照片会保留在本页供你核对；未明确识别为餐盘时不会随记录保存"
    }

    private var recoveryMessage: String? {
        RecognitionRecoveryPresentation.retainedDraftMessage(
            hasPreparedPhoto: preparedImage != nil,
            hasRecognizedFoods: !foods.isEmpty,
            locale: locale
        )
    }

    private var analysisProgressText: String {
        if DemoMode.isActive && !DemoMode.realRecognitionEnabled {
            return uiText("正在生成演示识别结果…")
        }
        return uiText("正在通过 Mac mini 识别，通常约 20 秒…")
    }

    private func confidenceDescription(_ confidence: Double) -> String {
        switch confidence {
        case 0.8...:
            return uiText("识别把握较高")
        case 0.6...:
            return uiText("识别把握一般")
        default:
            return uiText("识别把握较低")
        }
    }

    private func nutritionSummary(_ food: RecognizedFood) -> String? {
        var parts: [String] = []
        if let protein = food.protein {
            parts.append("\(uiText("蛋白质")) \(gramText(protein)) g")
        }
        if let carbs = food.carbs {
            parts.append("\(uiText("碳水")) \(gramText(carbs)) g")
        }
        if let fat = food.fat {
            parts.append("\(uiText("脂肪")) \(gramText(fat)) g")
        }
        if let caffeine = food.caffeineMg {
            parts.append("\(uiText("咖啡因")) \(gramText(caffeine)) mg")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func gramText(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(value.rounded() == value ? 0 : 1))
                .locale(locale)
        )
    }

    private func uiText(_ key: String) -> String {
        interfaceLocalized(key, locale: locale)
    }

    private func localizedErrorMessage(_ error: Error) -> String {
        if let bridgeError = error as? MacMiniFoodRecognitionError {
            return bridgeError.message(locale: locale)
        }
        return uiText(error.localizedDescription)
    }

    @MainActor
    private func beginLoadingPhoto(selectionID: UUID) {
        preparationTask?.cancel()
        analysisTask?.cancel()
        activePhotoSelectionID = selectionID
        errorMessage = nil
        isPreparing = true
        isAnalyzing = false
        showSlowAnalysisHint = false
    }

    @MainActor
    private func cancelPendingPhotoSelection() {
        photoLoadingTask?.cancel()
        photoLoadingTask = nil
        activePhotoSelectionID = nil
        isPreparing = false
    }

    private struct QuickAdjustmentUndo {
        let foods: [RecognizedFood]
        let manuallyAddedFoodIDs: Set<UUID>
        let selectedOrderShare: RecognitionOrderShare?
        let receiptReviewConfirmation: ReceiptReviewConfirmation
        let actionDescription: String
    }
}
