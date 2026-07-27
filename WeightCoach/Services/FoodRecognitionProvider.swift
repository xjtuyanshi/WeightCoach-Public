import Foundation

enum RecognitionInputKind: String, Codable, Sendable {
    case foodPhoto = "food_photo"
    case receiptOrMenu = "receipt_or_menu"
    case nonFood = "non_food"
}

struct RecognizedFood: Identifiable, Sendable {
    let id: UUID
    var name: String
    var portion: String
    var calories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var calorieLowerBound: Double?
    var calorieUpperBound: Double?
    var caffeineMg: Double?
    var confidence: Double?
    var needsConfirmation: Bool
    var note: String?
    var inputKind: RecognitionInputKind?

    init(
        id: UUID = UUID(),
        name: String,
        portion: String,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        calorieLowerBound: Double? = nil,
        calorieUpperBound: Double? = nil,
        caffeineMg: Double? = nil,
        confidence: Double? = nil,
        needsConfirmation: Bool = false,
        note: String? = nil,
        inputKind: RecognitionInputKind? = nil
    ) {
        self.id = id
        self.name = name
        self.portion = portion
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.calorieLowerBound = calorieLowerBound
        self.calorieUpperBound = calorieUpperBound
        self.caffeineMg = caffeineMg
        self.confidence = confidence
        self.needsConfirmation = needsConfirmation
        self.note = note
        self.inputKind = inputKind
    }
}

enum FoodRecognitionAvailability: Equatable {
    case available
    case unavailable(message: String)
}

protocol FoodRecognitionProviding {
    var availability: FoodRecognitionAvailability { get }
    func analyze(jpegData: Data) async throws -> [RecognizedFood]
    func analyze(
        jpegData: Data,
        outputLanguage: AppLanguage
    ) async throws -> [RecognizedFood]
}

extension FoodRecognitionProviding {
    func analyze(
        jpegData: Data,
        outputLanguage: AppLanguage
    ) async throws -> [RecognizedFood] {
        try await analyze(jpegData: jpegData)
    }
}

enum FoodRecognitionProviderError: LocalizedError {
    case macBridgePending
    case demoRecognitionFailed

    var errorDescription: String? {
        switch self {
        case .macBridgePending:
            return "Mac mini 本地识别尚未接入。照片已保留，你可以先手动补充食物；接入后这里会自动识别，不会跳转到 ChatGPT。"
        case .demoRecognitionFailed:
            return "演示：模拟识别失败，用于验证照片保留和重试流程。"
        }
    }
}

/// 真机默认占位：UI 与图片管线不依赖具体模型，之后只需替换这个 Provider。
struct PendingMacFoodRecognitionProvider: FoodRecognitionProviding {
    let availability: FoodRecognitionAvailability = .unavailable(
        message: "尚未配置私有识别桥接。你仍可手动记录；请在设置中填写自己的 HTTPS 桥接地址，不要填写 API Key。"
    )

    func analyze(jpegData: Data) async throws -> [RecognizedFood] {
        throw FoodRecognitionProviderError.macBridgePending
    }
}

/// 只在 -demoData -demoCapture 下使用，供模拟器验证自动分析和确认流程。
struct DemoFoodRecognitionProvider: FoodRecognitionProviding {
    let availability: FoodRecognitionAvailability = .available

    func analyze(jpegData: Data) async throws -> [RecognizedFood] {
        try await analyze(
            jpegData: jpegData,
            outputLanguage: .simplifiedChinese
        )
    }

    func analyze(
        jpegData: Data,
        outputLanguage: AppLanguage
    ) async throws -> [RecognizedFood] {
        try await Task.sleep(for: .milliseconds(320))
        try Task.checkCancellation()
        let language = outputLanguage.resolvedLanguage()
        return [
            RecognizedFood(
                name: DemoLocalizedText(
                    simplified: "香煎鸡胸肉",
                    traditional: "香煎雞胸肉",
                    english: "Pan-seared chicken breast"
                ).value(for: language),
                portion: DemoLocalizedText(
                    simplified: "约 180 克",
                    traditional: "約 180 公克",
                    english: "About 180 g"
                ).value(for: language),
                calories: 300,
                protein: 54,
                carbs: 2,
                fat: 8,
                confidence: 0.88,
                needsConfirmation: true,
                note: DemoLocalizedText(
                    simplified: "请确认烹调油和实际重量",
                    traditional: "請確認烹調油和實際重量",
                    english: "Confirm cooking oil and actual weight"
                ).value(for: language)
            ),
            RecognizedFood(
                name: DemoLocalizedText(
                    simplified: "糙米饭",
                    traditional: "糙米飯",
                    english: "Brown rice"
                ).value(for: language),
                portion: DemoLocalizedText(
                    simplified: "约 1 碗",
                    traditional: "約 1 碗",
                    english: "About 1 bowl"
                ).value(for: language),
                calories: 220,
                protein: 5,
                carbs: 46,
                fat: 2,
                confidence: 0.82,
                needsConfirmation: true
            ),
            RecognizedFood(
                name: DemoLocalizedText(
                    simplified: "西兰花",
                    traditional: "青花菜",
                    english: "Broccoli"
                ).value(for: language),
                portion: DemoLocalizedText(
                    simplified: "约 120 克",
                    traditional: "約 120 公克",
                    english: "About 120 g"
                ).value(for: language),
                calories: 42,
                protein: 3.5,
                carbs: 8,
                fat: 0.5,
                confidence: 0.9,
                needsConfirmation: true
            ),
        ]
    }
}

/// 只在 -demoData -demoReceipt 下使用：模拟 Mac mini 对餐厅账单的整单识别。
/// 数值代表整张账单里的菜品，食用比例必须由用户在确认页明确选择。
struct DemoReceiptFoodRecognitionProvider: FoodRecognitionProviding {
    let availability: FoodRecognitionAvailability = .available

    func analyze(jpegData: Data) async throws -> [RecognizedFood] {
        try await analyze(
            jpegData: jpegData,
            outputLanguage: .simplifiedChinese
        )
    }

    func analyze(
        jpegData: Data,
        outputLanguage: AppLanguage
    ) async throws -> [RecognizedFood] {
        try await Task.sleep(for: .milliseconds(320))
        try Task.checkCancellation()
        let language = outputLanguage.resolvedLanguage()
        return [
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "蔬菜米线",
                    traditional: "蔬菜米線",
                    english: "Vegetable rice noodles"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：1 份",
                    traditional: "帳單：1 份",
                    english: "Receipt: 1 order",
                    language: language
                ),
                calories: 600,
                calorieLowerBound: 450,
                calorieUpperBound: 750,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "烤鸡肉串",
                    traditional: "烤雞肉串",
                    english: "Grilled chicken skewers"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：2 串",
                    traditional: "帳單：2 串",
                    english: "Receipt: 2 skewers",
                    language: language
                ),
                calories: 240,
                calorieLowerBound: 180,
                calorieUpperBound: 300,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "香菇豆腐串",
                    traditional: "香菇豆腐串",
                    english: "Mushroom tofu skewers"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：两行合计 4 串",
                    traditional: "帳單：兩行合計 4 串",
                    english: "Receipt: 4 skewers across 2 lines",
                    language: language
                ),
                calories: 560,
                calorieLowerBound: 400,
                calorieUpperBound: 720,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "烤玉米",
                    traditional: "烤玉米",
                    english: "Grilled corn"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：2 片",
                    traditional: "帳單：2 片",
                    english: "Receipt: 2 slices",
                    language: language
                ),
                calories: 250,
                calorieLowerBound: 180,
                calorieUpperBound: 320,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "柠檬鱼串",
                    traditional: "檸檬魚串",
                    english: "Lemon fish skewers"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：4 串",
                    traditional: "帳單：4 串",
                    english: "Receipt: 4 skewers",
                    language: language
                ),
                calories: 350,
                calorieLowerBound: 260,
                calorieUpperBound: 440,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "蔬菜蒸饺",
                    traditional: "蔬菜蒸餃",
                    english: "Steamed vegetable dumplings"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：6 个",
                    traditional: "帳單：6 個",
                    english: "Receipt: 6 pieces",
                    language: language
                ),
                calories: 540,
                calorieLowerBound: 420,
                calorieUpperBound: 660,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "烤西兰花",
                    traditional: "烤西蘭花",
                    english: "Grilled broccoli skewers"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：4 串",
                    traditional: "帳單：4 串",
                    english: "Receipt: 4 skewers",
                    language: language
                ),
                calories: 220,
                calorieLowerBound: 160,
                calorieUpperBound: 280,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "凉拌黄瓜",
                    traditional: "涼拌黃瓜",
                    english: "Cucumber salad"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：2 串",
                    traditional: "帳單：2 串",
                    english: "Receipt: 2 skewers",
                    language: language
                ),
                calories: 140,
                calorieLowerBound: 100,
                calorieUpperBound: 180,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "味噌汤",
                    traditional: "味噌湯",
                    english: "Miso soup"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：1 串",
                    traditional: "帳單：1 串",
                    english: "Receipt: 1 skewer",
                    language: language
                ),
                calories: 75,
                calorieLowerBound: 50,
                calorieUpperBound: 100,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "香料牛肉串",
                    traditional: "香料牛肉串",
                    english: "Spiced beef skewers"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：两行合计 4 串",
                    traditional: "帳單：兩行合計 4 串",
                    english: "Receipt: 4 skewers across 2 lines",
                    language: language
                ),
                calories: 580,
                calorieLowerBound: 440,
                calorieUpperBound: 720,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "烤南瓜串",
                    traditional: "烤南瓜串",
                    english: "Grilled squash skewers"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：5 串",
                    traditional: "帳單：5 串",
                    english: "Receipt: 5 skewers",
                    language: language
                ),
                calories: 298,
                calorieLowerBound: 220,
                calorieUpperBound: 375,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "水果杯",
                    traditional: "水果杯",
                    english: "Fruit cups"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：2 串",
                    traditional: "帳單：2 串",
                    english: "Receipt: 2 skewers",
                    language: language
                ),
                calories: 190,
                calorieLowerBound: 140,
                calorieUpperBound: 240,
                language: language
            ),
            receiptFood(
                name: DemoLocalizedText(
                    simplified: "酸奶杯",
                    traditional: "優格杯",
                    english: "Yogurt cups"
                ).value(for: language),
                portion: receiptPortion(
                    simplified: "账单：5 串",
                    traditional: "帳單：5 串",
                    english: "Receipt: 5 skewers",
                    language: language
                ),
                calories: 288,
                calorieLowerBound: 200,
                calorieUpperBound: 375,
                language: language
            ),
        ]
    }

    private func receiptPortion(
        simplified: String,
        traditional: String,
        english: String,
        language: AppLanguage
    ) -> String {
        DemoLocalizedText(
            simplified: simplified,
            traditional: traditional,
            english: english
        ).value(for: language)
    }

    private func receiptFood(
        name: String,
        portion: String,
        calories: Double,
        calorieLowerBound: Double,
        calorieUpperBound: Double,
        language: AppLanguage
    ) -> RecognizedFood {
        RecognizedFood(
            name: name,
            portion: portion,
            calories: calories,
            calorieLowerBound: calorieLowerBound,
            calorieUpperBound: calorieUpperBound,
            confidence: 0.68,
            needsConfirmation: true,
            note: DemoLocalizedText(
                simplified: "按账单菜名和数量估算；看不到实际份量。请核对实际吃到的菜品、份量与烹调方式。",
                traditional: "按帳單菜名和數量估算；看不到實際份量。請核對實際吃到的菜品、份量與烹調方式。",
                english: "Estimated from the receipt item name and quantity; the actual portion is not visible. Confirm what you ate, the portion, and the cooking method."
            ).value(for: language),
            inputKind: .receiptOrMenu
        )
    }
}

private struct DemoLocalizedText {
    let simplified: String
    let traditional: String
    let english: String

    func value(for language: AppLanguage) -> String {
        switch language.resolvedLanguage() {
        case .traditionalChinese:
            traditional
        case .english:
            english
        case .system, .simplifiedChinese:
            simplified
        }
    }
}

/// 只在显式演示参数下使用，绝不代表真实桥接或模型识别结果。
struct DemoFailureFoodRecognitionProvider: FoodRecognitionProviding {
    let availability: FoodRecognitionAvailability = .available

    func analyze(jpegData: Data) async throws -> [RecognizedFood] {
        try await Task.sleep(for: .milliseconds(320))
        try Task.checkCancellation()
        throw FoodRecognitionProviderError.demoRecognitionFailed
    }
}

enum FoodRecognitionProviderFactory {
    static func make(
        bridgeResolution: BridgeConfigurationResolution? = BridgeConfiguration.current()
    ) -> any FoodRecognitionProviding {
        if DemoMode.isActive
            && DemoMode.demoReceiptEnabled
            && !DemoMode.realRecognitionEnabled {
            return DemoReceiptFoodRecognitionProvider()
        }
        if DemoMode.isActive
            && DemoMode.demoCaptureEnabled
            && !DemoMode.realRecognitionEnabled {
            if DemoMode.demoRecognitionFailureEnabled {
                return DemoFailureFoodRecognitionProvider()
            }
            return DemoFoodRecognitionProvider()
        }
        guard let bridgeResolution else {
            return PendingMacFoodRecognitionProvider()
        }
        return MacMiniFoodRecognitionProvider(baseURL: bridgeResolution.baseURL)
    }
}
