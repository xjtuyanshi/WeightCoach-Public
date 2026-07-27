import SwiftUI
import SwiftData
import Vision
import VisionKit
import AVFoundation

struct BarcodeScanView: View {
    let defaultDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var product: ScannedProduct?
    @State private var errorMessage: String?
    @State private var cameraGranted = false
    @State private var isSaving = false
    @State private var didStartDemoLookup = false
    @State private var showNutritionLabelScan = false

    private var scannerUsable: Bool {
        DataScannerViewController.isSupported && cameraGranted
    }

    var body: some View {
        NavigationStack {
            Group {
                if let product {
                    ScannedProductForm(
                        product: product,
                        defaultDate: defaultDate,
                        isSaving: $isSaving
                    ) {
                        dismiss()
                    } onRescan: {
                        self.product = nil
                        self.errorMessage = nil
                    }
                } else {
                    scanArea
                }
            }
            .navigationTitle("扫码记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task {
                if DemoMode.demoNutritionLabelEnabled {
                    manualCode = DemoMode.demoNutritionLabelBarcode
                    showNutritionLabelScan = true
                }
                if !didStartDemoLookup, let demoCode = DemoMode.demoBarcodeCode {
                    didStartDemoLookup = true
                    lookup(demoCode)
                }
                if !DemoMode.isActive {
                    cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .sheet(isPresented: $showNutritionLabelScan) {
                NutritionLabelScanView(
                    barcode: manualCode,
                    demoLines: DemoMode.demoNutritionLabelEnabled
                        ? DemoMode.demoNutritionLabelLines
                        : nil
                ) { scannedProduct in
                    product = scannedProduct
                    errorMessage = nil
                    showNutritionLabelScan = false
                }
            }
        }
    }

    private var scanArea: some View {
        VStack(spacing: 0) {
            if scannerUsable {
                BarcodeScannerRepresentable(isActive: !isLoading) { code in
                    lookup(code)
                }
                .overlay(alignment: .bottom) {
                    Text("对准商品条形码")
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 16)
                }
            } else {
                ContentUnavailableView(
                    "相机扫码不可用",
                    systemImage: "barcode.viewfinder",
                    description: Text("当前设备不支持实时扫码或未授权相机。可以在下方手动输入条形码数字。")
                )
                .frame(maxHeight: .infinity)
            }

            VStack(spacing: 10) {
                if isLoading {
                    ProgressView("正在查询商品信息…")
                } else {
                    if let errorMessage {
                        VStack(spacing: 10) {
                            Text(interfaceLocalized(errorMessage, locale: locale))
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)

                            Button {
                                showNutritionLabelScan = true
                            } label: {
                                Label("扫描包装营养表", systemImage: "text.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualCode.count < 6)

                            Text("只在本机识别；确认后会按这个条码保存，下次直接秒开。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    HStack {
                        TextField("手动输入条形码（UPC/EAN）", text: $manualCode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Button("查询") {
                            lookup(manualCode)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualCode.trimmingCharacters(in: .whitespaces).count < 6)
                    }
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }

    private func lookup(_ code: String) {
        guard !isLoading else { return }
        let code = BarcodeNormalizer.trimmedRaw(code)
        guard !code.isEmpty else { return }

        manualCode = code
        isLoading = true
        errorMessage = nil

        do {
            if let cached = try FoodProductCatalog.cachedProduct(
                barcode: code,
                context: modelContext
            ) {
                manualCode = code
                product = ScannedProduct(cached: cached)
                isLoading = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return
            }
        } catch {
            // 缓存不可读时仍允许联网查询，避免本地索引故障堵住记录入口。
        }

        Task {
            do {
                let result = try await OpenFoodFactsService.fetchProduct(barcode: code)
                await MainActor.run {
                    product = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

/// VisionKit 实时条码扫描
struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    /// 查询进行中时置为 false：暂停扫描，查询失败后重新武装扫描器
    var isActive: Bool
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if isActive {
            context.coordinator.didFire = false
            if !uiViewController.isScanning {
                try? uiViewController.startScanning()
            }
        } else if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerRepresentable
        var didFire = false
        init(_ parent: BarcodeScannerRepresentable) { self.parent = parent }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didFire else { return }
            for case let .barcode(barcode) in addedItems {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    didFire = true
                    dataScanner.stopScanning()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    parent.onScan(payload)
                    break
                }
            }
        }
    }
}

/// 扫码结果 → 选择份量并保存
struct ScannedProductForm: View {
    let product: ScannedProduct
    let defaultDate: Date
    @Binding var isSaving: Bool
    var onSaved: () -> Void
    var onRescan: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitManager.self) private var health
    @EnvironmentObject private var reminders: ReminderScheduler
    @Environment(\.locale) private var locale

    @State private var selectedUnit: FoodQuantityUnit = .servings
    @State private var amount = 1.0
    @State private var mealType: MealType = .snack
    @State private var didConfigureInitialAmount = false
    @State private var saveError: String?

    /// 可选单位完全由确定性换算引擎决定；缺少份重或密度时，不显示对应单位。
    private var availableUnits: [FoodQuantityUnit] {
        FoodQuantityUnit.allCases.filter { unit in
            NutritionEngine.calculate(
                profile: product.nutritionProfile,
                amount: unit.consumptionAmount(value: 1)
            )?.energyKcal != nil
        }
    }

    private var calculatedNutrition: NutritionValues? {
        guard amount.isFinite, amount > 0 else { return nil }
        return NutritionEngine.calculate(
            profile: product.nutritionProfile,
            amount: selectedUnit.consumptionAmount(value: Decimal(amount))
        )
    }

    private var computedKcal: Double {
        calculatedNutrition?.energyKcal?.doubleValue ?? 0
    }

    private var portionDescription: String {
        var description =
            "\(formattedAmount(amount)) \(interfaceLocalized(selectedUnit.label, locale: locale))"
        if selectedUnit == .servings, let servingSizeText = product.servingSizeText {
            description += " (\(interfaceLocalized("每份", locale: locale)) \(servingSizeText))"
        }
        return description
    }

    private var amountStep: Double {
        switch selectedUnit {
        case .grams: return 5
        case .milliliters: return 10
        case .servings: return 0.5
        case .units: return 1
        case .package: return 0.25
        }
    }

    private var amountPresets: [Double] {
        let common: [Double]
        let productSpecific: Double?
        switch selectedUnit {
        case .grams:
            common = [50, 100, 150, 200]
            productSpecific = positive(product.servingQuantityG)
        case .milliliters:
            common = [100, 250, 330, 500]
            productSpecific = positive(product.millilitersPerServing)
        case .servings:
            common = [0.5, 1, 1.5, 2]
            productSpecific = nil
        case .units:
            common = [1, 2, 3, 4]
            productSpecific = positive(product.unitsPerServing)
        case .package:
            common = [0.25, 0.5, 1]
            productSpecific = nil
        }

        var result: [Double] = []
        if let productSpecific {
            result.append(productSpecific)
        }
        for candidate in common where !result.contains(where: { abs($0 - candidate) < 0.001 }) {
            result.append(candidate)
        }
        return Array(result.prefix(5))
    }

    var body: some View {
        Form {
            Section("商品") {
                HStack(spacing: 12) {
                    if let url = product.imageURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                Color(.systemGray6)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name).font(.subheadline.bold())
                        if let brand = product.brand {
                            Text(brand).font(.caption).foregroundStyle(.secondary)
                        }
                        if let per100 = product.kcalPer100g {
                            Text(
                                "\(interfaceCalorieText(String(Int(per100.rounded())), locale: locale)) / 100g"
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let per100 = product.kcalPer100ml {
                            Text(
                                "\(interfaceCalorieText(String(Int(per100.rounded())), locale: locale)) / 100mL"
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if product.isCached {
                            Label("本地秒开", systemImage: "bolt.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.12), in: Capsule())
                        }
                        if product.source == .openFoodFacts {
                            Label("Open Food Facts", systemImage: "globe")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("重新扫描", action: onRescan)
                    .font(.footnote)
            }

            Section("这次吃了多少") {
                if availableUnits.isEmpty {
                    Label(
                        "商品数据不足，无法可靠换算。请重新扫描或改用手动记录。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                } else {
                    if availableUnits.count > 1 {
                        Picker("单位", selection: $selectedUnit) {
                            ForEach(availableUnits, id: \.self) { unit in
                                Text(interfaceLocalized(unit.label, locale: locale)).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 12) {
                        Button {
                            amount = max(amountStep, amount - amountStep)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(
                            "\(interfaceLocalized("减少", locale: locale)) \(interfaceLocalized(selectedUnit.label, locale: locale))"
                        )

                        TextField(
                            "数量",
                            value: $amount,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .font(.title2.bold())
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                        Text(interfaceLocalized(selectedUnit.label, locale: locale))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            amount += amountStep
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(
                            "\(interfaceLocalized("增加", locale: locale)) \(interfaceLocalized(selectedUnit.label, locale: locale))"
                        )
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(amountPresets, id: \.self) { preset in
                                Button {
                                    amount = preset
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Text(
                                        "\(formattedAmount(preset)) \(interfaceLocalized(selectedUnit.label, locale: locale))"
                                    )
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(
                                            abs(amount - preset) < 0.001
                                                ? Color.white
                                                : Color.primary
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            abs(amount - preset) < 0.001
                                                ? Color.accentColor
                                                : Color(.tertiarySystemFill),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let unitHint {
                        Text(unitHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("餐次", selection: $mealType) {
                    ForEach(MealType.allCases) { meal in
                        Text(interfaceLocalized(meal.label, locale: locale)).tag(meal)
                    }
                }
            }

            Section("自动计算") {
                HStack {
                    Text("本次摄入")
                    Spacer()
                    Text(interfaceCalorieText(computedKcal.kcalText, locale: locale))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }

                if let nutrition = calculatedNutrition {
                    HStack(spacing: 18) {
                        compactNutrient("蛋白质", value: nutrition.proteinG, unit: "g")
                        compactNutrient("碳水", value: nutrition.carbohydratesG, unit: "g")
                        compactNutrient("脂肪", value: nutrition.fatG, unit: "g")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if let saveError {
                    Text(interfaceLocalized(saveError, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button(action: save) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(
                            isSaving
                                ? interfaceLocalized("正在保存…", locale: locale)
                                : "\(interfaceLocalized("确认记录", locale: locale)) · \(interfaceCalorieText(computedKcal.kcalText, locale: locale))"
                        )
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(computedKcal <= 0 || isSaving)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(.regularMaterial)
        }
        .onAppear {
            mealType = MealType.suggested(for: defaultDate)
            configureInitialAmountIfNeeded()
        }
        .onChange(of: selectedUnit) { _, newUnit in
            guard didConfigureInitialAmount else { return }
            if product.preferredUnit == newUnit,
               let preferredAmount = positive(product.preferredAmount) {
                amount = preferredAmount
            } else {
                amount = defaultAmount(for: newUnit)
            }
        }
    }

    @ViewBuilder
    private func compactNutrient(
        _ label: String,
        value: Decimal?,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(interfaceLocalized(label, locale: locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { "\(formattedAmount($0.doubleValue))\(unit)" } ?? "—")
                .font(.caption.bold())
        }
    }

    private var unitHint: String? {
        switch selectedUnit {
        case .grams:
            if let servingQuantityG = positive(product.servingQuantityG) {
                return "\(interfaceLocalized("包装每份约", locale: locale)) \(formattedAmount(servingQuantityG)) \(interfaceLocalized("克", locale: locale))"
            }
        case .milliliters:
            if let millilitersPerServing = positive(product.millilitersPerServing) {
                return "\(interfaceLocalized("包装每份约", locale: locale)) \(formattedAmount(millilitersPerServing)) \(interfaceLocalized("毫升", locale: locale))"
            }
        case .servings:
            if let servingSizeText = product.servingSizeText {
                return "\(interfaceLocalized("包装每份", locale: locale)): \(servingSizeText)"
            }
        case .units:
            if let unitsPerServing = positive(product.unitsPerServing) {
                return "\(interfaceLocalized("包装每份约", locale: locale)) \(formattedAmount(unitsPerServing)) \(interfaceLocalized("个", locale: locale))"
            }
        case .package:
            if let servingsPerPackage = positive(product.servingsPerPackage) {
                return "\(interfaceLocalized("每包约", locale: locale)) \(formattedAmount(servingsPerPackage)) \(interfaceLocalized("份", locale: locale))"
            }
        }
        return nil
    }

    private func configureInitialAmountIfNeeded() {
        guard !didConfigureInitialAmount else { return }
        defer { didConfigureInitialAmount = true }
        guard let firstAvailable = availableUnits.first else { return }

        if let preferredUnit = product.preferredUnit,
           availableUnits.contains(preferredUnit),
           let preferredAmount = positive(product.preferredAmount) {
            selectedUnit = preferredUnit
            amount = preferredAmount
        } else if availableUnits.contains(.servings) {
            selectedUnit = .servings
            amount = defaultAmount(for: .servings)
        } else {
            selectedUnit = firstAvailable
            amount = defaultAmount(for: firstAvailable)
        }
    }

    private func defaultAmount(for unit: FoodQuantityUnit) -> Double {
        switch unit {
        case .grams:
            return positive(product.servingQuantityG) ?? 100
        case .milliliters:
            return positive(product.millilitersPerServing) ?? 250
        case .servings:
            return 1
        case .units:
            return positive(product.unitsPerServing) ?? 1
        case .package:
            return 1
        }
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func formattedAmount(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded()))"
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func save() {
        guard !isSaving,
              amount.isFinite,
              amount > 0,
              let nutrition = calculatedNutrition,
              let calories = nutrition.energyKcal?.doubleValue,
              calories > 0 else {
            saveError = "当前份量无法可靠换算，请选择可用单位和数量。"
            return
        }

        isSaving = true
        saveError = nil
        let displayName = product.brand.map { "\($0) \(product.name)" } ?? product.name
        let storedProduct: FoodProduct?

        do {
            storedProduct = try FoodProductCatalog.upsert(
                scanned: product,
                context: modelContext
            )
            if let storedProduct {
                storedProduct.verifiedByUser = true
                FoodProductCatalog.markUsed(
                    storedProduct,
                    amount: amount,
                    unit: selectedUnit,
                    at: defaultDate
                )
            }
        } catch {
            isSaving = false
            saveError =
                "\(interfaceLocalized("保存常用商品失败", locale: locale)): \(error.localizedDescription)"
            return
        }

        let draft = FoodEntryDraft(
            name: displayName,
            calories: calories,
            protein: nutrition.proteinG?.doubleValue,
            carbs: nutrition.carbohydratesG?.doubleValue,
            fat: nutrition.fatG?.doubleValue,
            portionText: portionDescription,
            mealType: mealType,
            source: .barcode,
            date: defaultDate,
            barcode: product.barcode,
            foodProductID: storedProduct?.id ?? product.cachedProductID,
            amountValue: amount,
            amountUnit: selectedUnit,
            calculationVersion: 1,
            fiber: nutrition.fiberG?.doubleValue,
            sugar: nutrition.sugarG?.doubleValue,
            sodiumMg: nutrition.sodiumMg?.doubleValue,
            caffeineMg: nutrition.caffeineMg?.doubleValue
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
                onSaved()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
