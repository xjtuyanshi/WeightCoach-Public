import Foundation

enum ReceiptReviewConfirmation: Equatable {
    case none
    case orderShare
    case reviewedItems

    var isConfirmed: Bool {
        self != .none
    }
}

enum AIFoodScanSaveBlockReason: Equatable {
    case busy
    case invalidFood
    case receiptNeedsConfirmation

    var message: String {
        localizedMessage(locale: AppLanguage.sharedSelection().locale)
    }

    func localizedMessage(locale: Locale) -> String {
        switch self {
        case .busy:
            interfaceLocalized("请等待照片处理或识别完成", locale: locale)
        case .invalidFood:
            interfaceLocalized("请补全食物名称和大于 0 的热量", locale: locale)
        case .receiptNeedsConfirmation:
            interfaceLocalized(
                "账单记录前，请选择整单食用比例（包括“全部”），或确认已逐项核对",
                locale: locale
            )
        }
    }
}

enum AIFoodScanSavePolicy {
    static func blockReason(
        foods: [RecognizedFood],
        inputWasReceiptOrMenu: Bool,
        isPreparing: Bool,
        isAnalyzing: Bool,
        receiptConfirmation: ReceiptReviewConfirmation
    ) -> AIFoodScanSaveBlockReason? {
        if isPreparing || isAnalyzing {
            return .busy
        }

        guard !foods.isEmpty else {
            return .invalidFood
        }

        if inputWasReceiptOrMenu, !receiptConfirmation.isConfirmed {
            return .receiptNeedsConfirmation
        }

        let allFoodsAreValid = foods.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.calories.isFinite
                && $0.calories > 0
        }
        return allFoodsAreValid ? nil : .invalidFood
    }

    static func thumbnailJPEGData(
        preparedThumbnail: Data?,
        recognizedInputKind: RecognitionInputKind?
    ) -> Data? {
        // 只有桥接明确确认是普通餐盘照片时才持久化。账单、菜单、识别为空、
        // 旧桥缺失类型或用户直接手填时一律不保存缩略图。
        recognizedInputKind == .foodPhoto ? preparedThumbnail : nil
    }
}

enum AIFoodScanPrivacyPolicy {
    static let cloudPhotoConsentKey = "privacy.aiPhotoCloudAnalysisConsent.v1"

    static func needsConsent(
        usesCloudRecognition: Bool,
        hasConsent: Bool
    ) -> Bool {
        usesCloudRecognition && !hasConsent
    }
}
