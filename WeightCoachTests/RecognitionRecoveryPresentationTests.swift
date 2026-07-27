import XCTest
@testable import WeightCoach

final class RecognitionRecoveryPresentationTests: XCTestCase {
    func testDoesNotOfferRecoveryWithoutAnInMemoryPhoto() {
        XCTAssertNil(
            RecognitionRecoveryPresentation.retainedDraftMessage(
                hasPreparedPhoto: false,
                hasRecognizedFoods: false,
                locale: Locale(identifier: "zh-Hans")
            )
        )
    }

    func testPhotoOnlyRecoveryStatesPhotoIsStillAvailableInCurrentPage() {
        let message = RecognitionRecoveryPresentation.retainedDraftMessage(
            hasPreparedPhoto: true,
            hasRecognizedFoods: false,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertTrue(message?.contains("当前照片") == true)
        XCTAssertTrue(message?.contains("重试") == true)
    }

    func testRecognizedResultRecoveryKeepsEditingPathAvailable() {
        let message = RecognitionRecoveryPresentation.retainedDraftMessage(
            hasPreparedPhoto: true,
            hasRecognizedFoods: true,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertTrue(message?.contains("已识别结果") == true)
        XCTAssertTrue(message?.contains("保存") == true)
    }

    func testDemoFailureProviderIsExplicitlyNotARecognitionResult() async {
        let provider = DemoFailureFoodRecognitionProvider()

        do {
            _ = try await provider.analyze(jpegData: Data([0xFF, 0xD8, 0xFF]))
            XCTFail("演示失败 Provider 不应返回模拟食物")
        } catch let error as FoodRecognitionProviderError {
            XCTAssertEqual(error.localizedDescription, "演示：模拟识别失败，用于验证照片保留和重试流程。")
        } catch {
            XCTFail("应返回明确的演示失败错误，实际为 \(error)")
        }
    }

    func testRecoveryAndProgressCopyLocalizeToEnglishAndTraditionalChinese() {
        XCTAssertEqual(
            RecognitionRecoveryPresentation.retainedDraftMessage(
                hasPreparedPhoto: true,
                hasRecognizedFoods: false,
                locale: Locale(identifier: "en")
            ),
            "The current photo is still on this page. Try recognition again, retake it, or enter the food manually."
        )
        XCTAssertEqual(
            RecognitionRecoveryPresentation.slowAnalysisMessage(
                locale: Locale(identifier: "zh-Hant")
            ),
            "辨識仍在繼續。這次的照片會保留在本頁；你可以繼續等待，或停止等待後重試。"
        )
        XCTAssertEqual(
            RecognitionRecoveryPresentation.stoppedMessage(
                locale: Locale(identifier: "en")
            ),
            "Stopped waiting. The current photo is still on this page, so you can retry, retake it, or enter the food manually at any time."
        )
    }
}
