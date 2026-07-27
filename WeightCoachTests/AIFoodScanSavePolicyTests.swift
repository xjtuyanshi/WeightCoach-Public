import XCTest
@testable import WeightCoach

final class AIFoodScanSavePolicyTests: XCTestCase {
    func testReceiptCannotSaveWithoutAnExplicitConfirmation() {
        let receiptFood = recognizedFood(kind: .receiptOrMenu)

        XCTAssertEqual(
            AIFoodScanSavePolicy.blockReason(
                foods: [receiptFood],
                inputWasReceiptOrMenu: true,
                isPreparing: false,
                isAnalyzing: false,
                receiptConfirmation: .none
            ),
            .receiptNeedsConfirmation
        )
    }

    func testEveryExplicitReceiptConfirmationAllowsSaving() {
        let receiptFood = recognizedFood(kind: .receiptOrMenu)

        for confirmation in [
            ReceiptReviewConfirmation.orderShare,
            .reviewedItems,
        ] {
            XCTAssertNil(
                AIFoodScanSavePolicy.blockReason(
                    foods: [receiptFood],
                    inputWasReceiptOrMenu: true,
                    isPreparing: false,
                    isAnalyzing: false,
                    receiptConfirmation: confirmation
                )
            )
        }
    }

    func testConfirmationRemainsValidWhenAReceiptItemIsEdited() {
        var receiptFood = recognizedFood(kind: .receiptOrMenu)
        let confirmation = ReceiptReviewConfirmation.orderShare
        receiptFood.calories = 325
        receiptFood.portion = "实际吃了 2 串"

        XCTAssertNil(
            AIFoodScanSavePolicy.blockReason(
                foods: [receiptFood],
                inputWasReceiptOrMenu: true,
                isPreparing: false,
                isAnalyzing: false,
                receiptConfirmation: confirmation
            )
        )
    }

    func testReceiptThumbnailIsNeverPersisted() {
        let thumbnail = Data([0xFF, 0xD8, 0xFF])

        XCTAssertNil(
            AIFoodScanSavePolicy.thumbnailJPEGData(
                preparedThumbnail: thumbnail,
                recognizedInputKind: .receiptOrMenu
            )
        )
    }

    func testReceiptThumbnailStaysSuppressedAfterRecognizedItemsAreEditedOrRemoved() {
        let thumbnail = Data([0xFF, 0xD8, 0xFF])

        XCTAssertNil(
            AIFoodScanSavePolicy.thumbnailJPEGData(
                preparedThumbnail: thumbnail,
                recognizedInputKind: .receiptOrMenu
            )
        )
    }

    func testOrdinaryFoodPhotoMayPersistThumbnail() {
        let thumbnail = Data([0xFF, 0xD8, 0xFF])

        XCTAssertEqual(
            AIFoodScanSavePolicy.thumbnailJPEGData(
                preparedThumbnail: thumbnail,
                recognizedInputKind: .foodPhoto
            ),
            thumbnail
        )
    }

    func testUnknownOrUnrecognizedPhotoNeverPersistsThumbnail() {
        let thumbnail = Data([0xFF, 0xD8, 0xFF])

        XCTAssertNil(
            AIFoodScanSavePolicy.thumbnailJPEGData(
                preparedThumbnail: thumbnail,
                recognizedInputKind: nil
            )
        )
        XCTAssertNil(
            AIFoodScanSavePolicy.thumbnailJPEGData(
                preparedThumbnail: thumbnail,
                recognizedInputKind: .nonFood
            )
        )
    }

    func testBusyAndInvalidDraftsRemainBlocked() {
        let validFood = recognizedFood(kind: .foodPhoto)
        XCTAssertEqual(
            AIFoodScanSavePolicy.blockReason(
                foods: [validFood],
                inputWasReceiptOrMenu: false,
                isPreparing: true,
                isAnalyzing: false,
                receiptConfirmation: .none
            ),
            .busy
        )

        var invalidFood = validFood
        invalidFood.calories = 0
        XCTAssertEqual(
            AIFoodScanSavePolicy.blockReason(
                foods: [invalidFood],
                inputWasReceiptOrMenu: false,
                isPreparing: false,
                isAnalyzing: false,
                receiptConfirmation: .none
            ),
            .invalidFood
        )
    }

    func testCloudRecognitionRequiresConsentButLocalDemoDoesNot() {
        XCTAssertTrue(
            AIFoodScanPrivacyPolicy.needsConsent(
                usesCloudRecognition: true,
                hasConsent: false
            )
        )
        XCTAssertFalse(
            AIFoodScanPrivacyPolicy.needsConsent(
                usesCloudRecognition: true,
                hasConsent: true
            )
        )
        XCTAssertFalse(
            AIFoodScanPrivacyPolicy.needsConsent(
                usesCloudRecognition: false,
                hasConsent: false
            )
        )
    }

    func testSaveBlockMessagesLocalizeForEnglishAndTraditionalChinese() {
        XCTAssertEqual(
            AIFoodScanSaveBlockReason.busy.localizedMessage(
                locale: Locale(identifier: "en")
            ),
            "Wait for photo processing or recognition to finish"
        )
        XCTAssertEqual(
            AIFoodScanSaveBlockReason.receiptNeedsConfirmation.localizedMessage(
                locale: Locale(identifier: "zh-Hant")
            ),
            "記錄帳單前，請選擇整張訂單的食用比例（包括「全部」），或確認你已逐項核對"
        )
    }

    private func recognizedFood(kind: RecognitionInputKind) -> RecognizedFood {
        RecognizedFood(
            name: "合成测试食物",
            portion: "1 份",
            calories: 300,
            inputKind: kind
        )
    }
}
