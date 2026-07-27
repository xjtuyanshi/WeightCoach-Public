import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// 拍照/相册图片进入识别流程前的统一产物。
///
/// `captureID` 由拍摄入口生成，调用方可用它防止较早的异步结果覆盖用户后拍的照片。
/// 两份 JPEG 都由已经按 EXIF 方向旋正的像素重新编码，不会带入原图的 EXIF/GPS 元数据。
struct PreparedFoodImage: Identifiable, @unchecked Sendable {
    let captureID: UUID
    let displayImage: UIImage
    let recognitionJPEGData: Data
    let thumbnailJPEGData: Data

    var id: UUID { captureID }
}

enum FoodImagePreparationError: LocalizedError {
    case emptyImageData
    case unreadableImage
    case resizeFailed
    case jpegEncodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyImageData:
            return "照片数据为空，请重新拍摄"
        case .unreadableImage:
            return "无法读取这张照片，请换一张重试"
        case .resizeFailed:
            return "照片缩放失败，请重新拍摄"
        case .jpegEncodingFailed:
            return "照片处理失败，请重新拍摄"
        }
    }
}

/// 使用 ImageIO 在后台完成一次解码，并派生识别图与本地缩略图。
enum FoodImagePreparer {
    static let recognitionMaxPixelSize = 1_600
    static let thumbnailMaxPixelSize = 512

    /// 准备照片；取消调用此方法的 `Task` 即可中止尚未完成的流水线。
    static func prepare(
        imageData: Data,
        captureID: UUID = UUID()
    ) async throws -> PreparedFoodImage {
        guard !imageData.isEmpty else {
            throw FoodImagePreparationError.emptyImageData
        }

        let worker = Task.detached(priority: .userInitiated) {
            try prepareSynchronously(imageData: imageData, captureID: captureID)
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func prepareSynchronously(
        imageData: Data,
        captureID: UUID
    ) throws -> PreparedFoodImage {
        try Task.checkCancellation()

        guard let source = CGImageSourceCreateWithData(
            imageData as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
        CGImageSourceGetCount(source) > 0 else {
            throw FoodImagePreparationError.unreadableImage
        }

        let recognitionOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: recognitionMaxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let recognitionImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            recognitionOptions as CFDictionary
        ) else {
            throw FoodImagePreparationError.unreadableImage
        }

        try Task.checkCancellation()

        // 直接从旋正后的 CGImage 编码，不复制源图片的属性字典，因而不会保留 EXIF/GPS。
        let recognitionJPEGData = try encodeJPEG(recognitionImage, quality: 0.82)

        try Task.checkCancellation()

        guard let thumbnailImage = scaledImage(
            recognitionImage,
            maxPixelSize: thumbnailMaxPixelSize
        ) else {
            throw FoodImagePreparationError.resizeFailed
        }

        try Task.checkCancellation()

        let thumbnailJPEGData = try encodeJPEG(thumbnailImage, quality: 0.68)

        try Task.checkCancellation()

        return PreparedFoodImage(
            captureID: captureID,
            displayImage: UIImage(cgImage: recognitionImage, scale: 1, orientation: .up),
            recognitionJPEGData: recognitionJPEGData,
            thumbnailJPEGData: thumbnailJPEGData
        )
    }

    private static func scaledImage(
        _ image: CGImage,
        maxPixelSize: Int
    ) -> CGImage? {
        let longestSide = max(image.width, image.height)
        guard longestSide > maxPixelSize else { return image }

        let scale = CGFloat(maxPixelSize) / CGFloat(longestSide)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encodeJPEG(
        _ image: CGImage,
        quality: CGFloat
    ) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw FoodImagePreparationError.jpegEncodingFailed
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw FoodImagePreparationError.jpegEncodingFailed
        }
        return output as Data
    }
}
