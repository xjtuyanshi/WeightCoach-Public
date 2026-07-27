import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// 条码库未命中时的本地兜底：一次拍摄 → Vision OCR → 核对少量字段 → 按条码缓存。
struct NutritionLabelScanView: View {
    let barcode: String
    private let demoLines: [String]?
    private let recognizer: any NutritionLabelTextRecognizing
    private let onConfirmed: (ScannedProduct) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var activeCaptureID: UUID?
    @State private var showCamera = false
    @State private var isRecognizing = false
    @State private var errorMessage: String?
    @State private var parsedLabel: ParsedNutritionLabel?
    @State private var selectedColumnIndex = 0
    @State private var productName = ""
    @State private var brand = ""
    @State private var selectedBasis: NutritionBasis = .perServing
    @State private var servingSizeText = ""
    @State private var servingGrams = ""
    @State private var servingMilliliters = ""
    @State private var unitsPerServing = ""
    @State private var servingsPerPackage = ""
    @State private var nutrients = EditableNutritionValues()
    @State private var flaggedNutrientKeys = Set<NutritionLabelFieldKey>()
    @State private var basisNeedsReview = false
    @State private var servingNeedsReview = false
    @State private var didConfirmFlaggedValues = false
    @State private var showMoreNutrients = false
    @State private var didStart = false
    @State private var isSavingProduct = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var activePhotoSelectionID: UUID?

    init(
        barcode: String,
        demoLines: [String]? = nil,
        recognizer: (any NutritionLabelTextRecognizing)? = nil,
        onConfirmed: @escaping (ScannedProduct) -> Void
    ) {
        self.barcode = BarcodeNormalizer.trimmedRaw(barcode)
        self.demoLines = demoLines
        self.recognizer = recognizer ?? VisionNutritionLabelTextRecognizer()
        self.onConfirmed = onConfirmed
    }

    private var hasFlaggedValues: Bool {
        basisNeedsReview || servingNeedsReview || !flaggedNutrientKeys.isEmpty
    }

    private var canConfirm: Bool {
        guard parsedLabel != nil,
              !isRecognizing,
              !isSavingProduct,
              !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let calories = decimal(from: nutrients.energyKcal),
              calories > 0,
              nutrients.allEnteredValuesAreValid,
              optionalDecimalIsValid(servingGrams),
              optionalDecimalIsValid(servingMilliliters),
              optionalDecimalIsValid(unitsPerServing),
              optionalDecimalIsValid(servingsPerPackage) else {
            return false
        }
        return !hasFlaggedValues || didConfirmFlaggedValues
    }

    var body: some View {
        NavigationStack {
            Form {
                privacySection

                if parsedLabel == nil {
                    captureSection
                } else {
                    scanSummarySection
                    productSection
                    basisAndServingSection
                    mainNutrientsSection
                    moreNutrientsSection
                    reviewSection
                }
            }
            .navigationTitle("扫描营养表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSavingProduct)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if parsedLabel != nil {
                    confirmationBar
                }
            }
            .task {
                startIfNeeded()
            }
            .onDisappear {
                photoLoadingTask?.cancel()
                recognitionTask?.cancel()
                activeCaptureID = nil
                activePhotoSelectionID = nil
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                loadPhoto(newItem)
            }
            .onChange(of: selectedColumnIndex) { _, newIndex in
                guard let parsedLabel,
                      parsedLabel.columns.indices.contains(newIndex) else {
                    return
                }
                apply(column: parsedLabel.columns[newIndex], metadata: parsedLabel)
            }
            .interactiveDismissDisabled(isSavingProduct)
            .fullScreenCover(isPresented: $showCamera) {
                FastFoodCameraView(
                    onCapture: { photo in
                        guard showCamera else { return }
                        showCamera = false
                        cancelPendingPhotoSelection()
                        recognize(photo.data, captureID: photo.captureID)
                    },
                    onCancel: {
                        showCamera = false
                    },
                    guidanceText: "让营养表占满画面，保持镜头平行",
                    captureAccessibilityLabel: "拍摄包装营养表",
                    captureAccessibilityHint: "拍摄后立即在本机识别文字"
                )
            }
        }
    }

    private var privacySection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机识别，不上传照片")
                        .font(.subheadline.bold())
                    Text("识别值必须由你确认后才会按条码保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var captureSection: some View {
        Section("包装上的 Nutrition Facts") {
            if isRecognizing {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在本机读取营养数字…")
                        .font(.subheadline.bold())
                    Text("通常只需几秒")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ContentUnavailableView(
                    interfaceLocalized(
                        errorMessage == nil ? "拍摄完整营养表" : "需要重新拍摄",
                        locale: locale
                    ),
                    systemImage: errorMessage == nil
                        ? "text.viewfinder"
                        : "exclamationmark.viewfinder",
                    description: Text(interfaceLocalized(
                        errorMessage
                            ?? "靠近包装，让标题、每份大小、热量和三大营养素都进入画面。",
                        locale: locale
                    ))
                )

                captureButtons
            }
        }
    }

    private var scanSummarySection: some View {
        Section {
            HStack(spacing: 12) {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: demoLines == nil ? "doc.text.viewfinder" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.green)
                        .frame(width: 72, height: 72)
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        interfaceLocalized(
                            demoLines == nil ? "本机 OCR 已完成" : "演示 OCR 已完成",
                            locale: locale
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)

                    Text("只需核对标橙字段，然后继续选择食用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            captureButtons
        }
    }

    private var captureButtons: some View {
        HStack {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    cancelPendingPhotoSelection()
                    showCamera = true
                } label: {
                    Label(
                        interfaceLocalized(
                            parsedLabel == nil ? "拍照" : "重拍",
                            locale: locale
                        ),
                        systemImage: "camera"
                    )
                }
                .buttonStyle(.borderless)
                .disabled(isRecognizing || isSavingProduct)

                Spacer()
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderless)
            .disabled(isRecognizing || isSavingProduct)
        }
    }

    private var productSection: some View {
        Section("商品") {
            TextField("商品名称", text: $productName)
            TextField("品牌（可不填）", text: $brand)
            LabeledContent("条码", value: barcode)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var basisAndServingSection: some View {
        Section {
            if let columns = parsedLabel?.columns, columns.count > 1 {
                Picker("使用标签哪一列", selection: $selectedColumnIndex) {
                    ForEach(columns.indices, id: \.self) { index in
                        Text(interfaceLocalized(
                            columns[index].basis.nutritionLabelDisplayName,
                            locale: locale
                        ))
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }

            Picker("这些数值是", selection: $selectedBasis) {
                ForEach(NutritionBasis.allCases, id: \.self) { basis in
                    Text(interfaceLocalized(
                        basis.nutritionLabelDisplayName,
                        locale: locale
                    ))
                        .tag(basis)
                }
            }
            .listRowBackground(basisNeedsReview ? Color.orange.opacity(0.12) : nil)

            TextField("每份说明（如 5 块 / 85g）", text: $servingSizeText)
                .listRowBackground(servingNeedsReview ? Color.orange.opacity(0.12) : nil)

            DisclosureGroup("份量换算信息") {
                editableMetadataRow("每份重量", text: $servingGrams, unit: "g")
                editableMetadataRow("每份体积", text: $servingMilliliters, unit: "mL")
                editableMetadataRow("每份数量", text: $unitsPerServing, unit: "个")
                editableMetadataRow("每包份数", text: $servingsPerPackage, unit: "份")
            }
        } header: {
            Text("营养基准与份量")
        } footer: {
            Text("这里决定之后按克、份、毫升、个或整包换算；程序不会猜缺失数据。")
        }
    }

    private var mainNutrientsSection: some View {
        Section {
            nutrientRow(
                .energyKcal,
                text: $nutrients.energyKcal,
                unit: "千卡",
                required: true
            )
            nutrientRow(.proteinG, text: $nutrients.proteinG, unit: "g")
            nutrientRow(.carbohydratesG, text: $nutrients.carbohydratesG, unit: "g")
            nutrientRow(.fatG, text: $nutrients.fatG, unit: "g")
        } header: {
            Text(
                "\(interfaceLocalized("主要营养", locale: locale)) · \(interfaceLocalized(selectedBasis.nutritionLabelDisplayName, locale: locale))"
            )
        }
    }

    private var moreNutrientsSection: some View {
        Section {
            DisclosureGroup("其他营养素", isExpanded: $showMoreNutrients) {
                nutrientRow(.saturatedFatG, text: $nutrients.saturatedFatG, unit: "g")
                nutrientRow(.transFatG, text: $nutrients.transFatG, unit: "g")
                nutrientRow(.cholesterolMg, text: $nutrients.cholesterolMg, unit: "mg")
                nutrientRow(.fiberG, text: $nutrients.fiberG, unit: "g")
                nutrientRow(.sugarG, text: $nutrients.sugarG, unit: "g")
                nutrientRow(.addedSugarG, text: $nutrients.addedSugarG, unit: "g")
                nutrientRow(.sodiumMg, text: $nutrients.sodiumMg, unit: "mg")
                nutrientRow(.vitaminDMcg, text: $nutrients.vitaminDMcg, unit: "µg")
                nutrientRow(.calciumMg, text: $nutrients.calciumMg, unit: "mg")
                nutrientRow(.ironMg, text: $nutrients.ironMg, unit: "mg")
                nutrientRow(.potassiumMg, text: $nutrients.potassiumMg, unit: "mg")
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let parsedLabel, hasFlaggedValues || !parsedLabel.warnings.isEmpty {
            Section {
                ForEach(parsedLabel.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if hasFlaggedValues {
                    Toggle(isOn: $didConfirmFlaggedValues) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("我已核对标橙字段")
                                .font(.subheadline.bold())
                            Text(flaggedValuesSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                }
            } header: {
                Text("保存前确认")
            }
        }
    }

    private var confirmationBar: some View {
        VStack(spacing: 6) {
            if let validationMessage {
                Text(interfaceLocalized(validationMessage, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button(action: confirmAndCache) {
                HStack {
                    if isSavingProduct {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isSavingProduct ? "正在保存商品…" : "确认并继续记录")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
            .disabled(!canConfirm)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }

    private func nutrientRow(
        _ key: NutritionLabelFieldKey,
        text: Binding<String>,
        unit: String,
        required: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if flaggedNutrientKeys.contains(key) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("需要核对")
            }

            Text(interfaceLocalized(key.label, locale: locale))
            Spacer()
            TextField(required ? "必填" : "—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(interfaceLocalized(unit, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
        }
        .listRowBackground(
            flaggedNutrientKeys.contains(key)
                ? Color.orange.opacity(0.12)
                : nil
        )
    }

    private func editableMetadataRow(
        _ title: String,
        text: Binding<String>,
        unit: String
    ) -> some View {
        HStack {
            Text(interfaceLocalized(title, locale: locale))
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(interfaceLocalized(unit, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        productName = defaultProductName

        if let demoLines {
            let count = max(demoLines.count, 1)
            let lines = demoLines.enumerated().map { index, text in
                RecognizedNutritionTextLine(
                    text: text,
                    confidence: index == 6 ? 0.78 : 0.97,
                    boundingBox: CGRect(
                        x: 0.06,
                        y: 0.94 - CGFloat(index) / CGFloat(count),
                        width: 0.88,
                        height: 0.05
                    )
                )
            }
            apply(parsed: NutritionLabelParser.parse(lines: lines))
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) {
        photoLoadingTask?.cancel()
        recognitionTask?.cancel()
        let selectionID = UUID()
        activePhotoSelectionID = selectionID
        activeCaptureID = selectionID
        parsedLabel = nil
        errorMessage = nil
        isRecognizing = true

        photoLoadingTask = Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw NutritionLabelOCRError.emptyImageData
                }
                try Task.checkCancellation()
                guard activePhotoSelectionID == selectionID else { return }
                recognize(data, captureID: selectionID)
            } catch is CancellationError {
                return
            } catch {
                guard activePhotoSelectionID == selectionID else { return }
                isRecognizing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func recognize(_ data: Data, captureID: UUID) {
        recognitionTask?.cancel()
        activeCaptureID = captureID
        parsedLabel = nil
        previewImage = nil
        errorMessage = nil
        isRecognizing = true
        didConfirmFlaggedValues = false

        let recognizer = recognizer
        recognitionTask = Task {
            do {
                async let preparedPreview = NutritionLabelPreviewPreparer.makePreview(
                    imageData: data
                )
                let lines = try await recognizer.recognize(imageData: data)
                let preview = await preparedPreview
                try Task.checkCancellation()
                guard activeCaptureID == captureID else { return }
                previewImage = preview
                apply(parsed: NutritionLabelParser.parse(lines: lines))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return
            } catch {
                guard activeCaptureID == captureID else { return }
                isRecognizing = false
                errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    @MainActor
    private func apply(parsed: ParsedNutritionLabel) {
        guard let first = parsed.columns.first else {
            parsedLabel = nil
            isRecognizing = false
            errorMessage = "没有读到可用的营养数字，请靠近后重拍。"
            return
        }

        parsedLabel = parsed
        selectedColumnIndex = 0
        servingSizeText = parsed.servingSizeText ?? ""
        servingGrams = display(parsed.servingGrams?.amount)
        servingMilliliters = display(parsed.servingMilliliters?.amount)
        unitsPerServing = display(parsed.unitsPerServing?.amount)
        servingsPerPackage = display(parsed.servingsPerPackage?.amount)
        apply(column: first, metadata: parsed)
        isRecognizing = false
        errorMessage = nil
    }

    @MainActor
    private func apply(
        column: ParsedNutritionColumn,
        metadata: ParsedNutritionLabel
    ) {
        selectedBasis = column.basis
        nutrients = EditableNutritionValues(column.values)
        flaggedNutrientKeys = Set(
            column.fields.compactMap { key, field in
                field.requiresConfirmation ? key : nil
            }
        )
        basisNeedsReview = column.basisRequiresConfirmation
        servingNeedsReview = [
            metadata.servingGrams,
            metadata.servingMilliliters,
            metadata.unitsPerServing,
            metadata.servingsPerPackage
        ]
        .compactMap { $0 }
        .contains(where: \.requiresConfirmation)
        didConfirmFlaggedValues = false
    }

    @MainActor
    private func confirmAndCache() {
        guard canConfirm else { return }
        isSavingProduct = true
        errorMessage = nil

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        var scanned = ScannedProduct(
            barcode: barcode,
            name: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            nutritionBasis: selectedBasis,
            nutritionValues: nutrients.nutritionValues,
            source: .nutritionLabel,
            servingSizeText: nilIfBlank(servingSizeText),
            servingQuantityG: double(from: servingGrams),
            millilitersPerServing: double(from: servingMilliliters),
            unitsPerServing: double(from: unitsPerServing),
            servingsPerPackage: double(from: servingsPerPackage),
            preferredAmount: preferredAmount,
            preferredUnit: preferredUnit
        )

        do {
            if let stored = try FoodProductCatalog.upsert(
                scanned: scanned,
                context: modelContext
            ) {
                stored.verifiedByUser = true
                try modelContext.save()
                scanned.cachedProductID = stored.id
                scanned.isCached = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSavingProduct = false
            onConfirmed(scanned)
        } catch {
            isSavingProduct = false
            errorMessage =
                "\(interfaceLocalized("保存商品失败", locale: locale)): \(error.localizedDescription)"
        }
    }

    private func cancelPendingPhotoSelection() {
        photoLoadingTask?.cancel()
        activePhotoSelectionID = nil
        pickerItem = nil
    }

    private var preferredUnit: FoodQuantityUnit {
        switch selectedBasis {
        case .perServing: return .servings
        case .per100Grams: return .grams
        case .per100Milliliters: return .milliliters
        case .perPackage: return .package
        case .perUnit: return .units
        }
    }

    private var preferredAmount: Double {
        switch selectedBasis {
        case .perServing, .perPackage, .perUnit:
            return 1
        case .per100Grams:
            return double(from: servingGrams) ?? 100
        case .per100Milliliters:
            return double(from: servingMilliliters) ?? 100
        }
    }

    private var flaggedValuesSummary: String {
        var labels = flaggedNutrientKeys
            .map { interfaceLocalized($0.label, locale: locale) }
            .sorted()
        if basisNeedsReview {
            labels.insert(interfaceLocalized("营养基准", locale: locale), at: 0)
        }
        if servingNeedsReview {
            labels.append(interfaceLocalized("份量信息", locale: locale))
        }
        let separator =
            AppLanguage.system.resolvedLanguage(systemLocale: locale)
                == .english
            ? ", "
            : "、"
        return labels.isEmpty
            ? interfaceLocalized("请确认 OCR 结果", locale: locale)
            : labels.joined(separator: separator)
    }

    private var validationMessage: String? {
        if hasFlaggedValues, !didConfirmFlaggedValues {
            return "请先核对并确认标橙字段"
        }
        if productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写商品名称"
        }
        guard let calories = decimal(from: nutrients.energyKcal), calories > 0 else {
            return "请确认热量是大于 0 的数字"
        }
        if !nutrients.allEnteredValuesAreValid {
            return "营养数值只能填写非负数字"
        }
        return errorMessage
    }

    private var defaultProductName: String {
        let suffix = String(barcode.suffix(4))
        let name = interfaceLocalized("包装食品", locale: locale)
        return suffix.isEmpty ? name : "\(name) · \(suffix)"
    }

    private func optionalDecimalIsValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let value = decimal(from: trimmed) else { return false }
        return value > 0
    }

    private func decimal(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func double(from text: String) -> Double? {
        decimal(from: text)?.doubleValue
    }

    private func display(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct EditableNutritionValues {
    var energyKcal = ""
    var proteinG = ""
    var carbohydratesG = ""
    var fatG = ""
    var saturatedFatG = ""
    var transFatG = ""
    var cholesterolMg = ""
    var fiberG = ""
    var sugarG = ""
    var addedSugarG = ""
    var sodiumMg = ""
    var vitaminDMcg = ""
    var calciumMg = ""
    var ironMg = ""
    var potassiumMg = ""

    init() {}

    init(_ values: NutritionValues) {
        energyKcal = Self.display(values.energyKcal)
        proteinG = Self.display(values.proteinG)
        carbohydratesG = Self.display(values.carbohydratesG)
        fatG = Self.display(values.fatG)
        saturatedFatG = Self.display(values.saturatedFatG)
        transFatG = Self.display(values.transFatG)
        cholesterolMg = Self.display(values.cholesterolMg)
        fiberG = Self.display(values.fiberG)
        sugarG = Self.display(values.sugarG)
        addedSugarG = Self.display(values.addedSugarG)
        sodiumMg = Self.display(values.sodiumMg)
        vitaminDMcg = Self.display(values.vitaminDMcg)
        calciumMg = Self.display(values.calciumMg)
        ironMg = Self.display(values.ironMg)
        potassiumMg = Self.display(values.potassiumMg)
    }

    var nutritionValues: NutritionValues {
        NutritionValues(
            energyKcal: Self.decimal(energyKcal),
            proteinG: Self.decimal(proteinG),
            carbohydratesG: Self.decimal(carbohydratesG),
            fatG: Self.decimal(fatG),
            saturatedFatG: Self.decimal(saturatedFatG),
            transFatG: Self.decimal(transFatG),
            cholesterolMg: Self.decimal(cholesterolMg),
            fiberG: Self.decimal(fiberG),
            sugarG: Self.decimal(sugarG),
            addedSugarG: Self.decimal(addedSugarG),
            sodiumMg: Self.decimal(sodiumMg),
            vitaminDMcg: Self.decimal(vitaminDMcg),
            calciumMg: Self.decimal(calciumMg),
            ironMg: Self.decimal(ironMg),
            potassiumMg: Self.decimal(potassiumMg)
        )
    }

    var allEnteredValuesAreValid: Bool {
        [
            energyKcal, proteinG, carbohydratesG, fatG,
            saturatedFatG, transFatG, cholesterolMg, fiberG,
            sugarG, addedSugarG, sodiumMg, vitaminDMcg,
            calciumMg, ironMg, potassiumMg
        ]
        .allSatisfy { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            guard let value = Self.decimal(trimmed) else { return false }
            return value >= 0
        }
    }

    private static func decimal(_ value: String) -> Decimal? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func display(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }
}

private extension NutritionBasis {
    var nutritionLabelDisplayName: String {
        switch self {
        case .perServing: return "每份"
        case .per100Grams: return "每 100 克"
        case .per100Milliliters: return "每 100 毫升"
        case .perPackage: return "整包"
        case .perUnit: return "每个"
        }
    }
}
