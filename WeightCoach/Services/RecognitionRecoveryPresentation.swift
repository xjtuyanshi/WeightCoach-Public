import Foundation

/// 未确认照片只存在于当前识别页面的内存状态中。
/// 这里集中定义失败后的文案，避免暗示它已被长期保存。
enum RecognitionRecoveryPresentation {
    static func retainedDraftMessage(
        hasPreparedPhoto: Bool,
        hasRecognizedFoods: Bool,
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> String? {
        guard hasPreparedPhoto else { return nil }
        if hasRecognizedFoods {
            return interfaceLocalized(
                "当前照片和已识别结果仍在本页，可停止等待后直接修改或保存。",
                locale: locale
            )
        }
        return interfaceLocalized(
            "当前照片仍保留在本页，可重试识别、重拍或直接手动填写。",
            locale: locale
        )
    }

    static func slowAnalysisMessage(
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> String {
        interfaceLocalized(
            "识别仍在继续。本次照片会保留在本页；你可以继续等待，或停止等待后重试。",
            locale: locale
        )
    }

    static func stoppedMessage(
        locale: Locale = AppLanguage.sharedSelection().locale
    ) -> String {
        interfaceLocalized(
            "已停止等待。当前照片仍在本页，随时可以重试、重拍或手动填写。",
            locale: locale
        )
    }
}
