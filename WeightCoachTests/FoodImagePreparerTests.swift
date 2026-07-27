import ImageIO
import UIKit
import XCTest
@testable import WeightCoach

final class FoodImagePreparerTests: XCTestCase {
    func testPreparesBoundedImagesAndPreservesCaptureIdentity() async throws {
        let sourceData = makeJPEG(width: 2_400, height: 1_200)
        let captureID = UUID()

        let prepared = try await FoodImagePreparer.prepare(
            imageData: sourceData,
            captureID: captureID
        )

        XCTAssertEqual(prepared.captureID, captureID)
        XCTAssertLessThanOrEqual(
            max(
                prepared.displayImage.cgImage?.width ?? .max,
                prepared.displayImage.cgImage?.height ?? .max
            ),
            FoodImagePreparer.recognitionMaxPixelSize
        )

        let recognitionDimensions = try imageDimensions(prepared.recognitionJPEGData)
        XCTAssertLessThanOrEqual(
            max(recognitionDimensions.width, recognitionDimensions.height),
            FoodImagePreparer.recognitionMaxPixelSize
        )

        let thumbnailDimensions = try imageDimensions(prepared.thumbnailJPEGData)
        XCTAssertLessThanOrEqual(
            max(thumbnailDimensions.width, thumbnailDimensions.height),
            FoodImagePreparer.thumbnailMaxPixelSize
        )
    }

    func testReencodedImagesDoNotCarryGPSMetadata() async throws {
        let prepared = try await FoodImagePreparer.prepare(
            imageData: makeJPEG(width: 800, height: 600)
        )
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(prepared.recognitionJPEGData as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    @MainActor
    func testRecognitionProvidersExposeHonestAvailability() async throws {
        let pending = PendingMacFoodRecognitionProvider()
        guard case .unavailable = pending.availability else {
            return XCTFail("未接入 Mac mini 时必须明确显示不可用")
        }

        do {
            _ = try await pending.analyze(jpegData: Data([0x01]))
            XCTFail("待接入 Provider 不应返回伪识别结果")
        } catch {
            XCTAssertTrue(error is FoodRecognitionProviderError)
        }

        let demo = DemoFoodRecognitionProvider()
        let foods = try await demo.analyze(jpegData: Data([0x01]))
        XCTAssertEqual(foods.count, 3)
        XCTAssertEqual(foods.reduce(0) { $0 + $1.calories }, 562, accuracy: 0.001)
    }

    private func makeJPEG(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.cgContext.fill(
                CGRect(x: 0, y: 0, width: width, height: height)
            )
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func imageDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }
}
