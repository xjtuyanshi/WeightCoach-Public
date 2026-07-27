import Foundation
import ImageIO
import UIKit
import Vision

/// Vision 返回的一行营养表文字。保留坐标，规则解析器可据此识别双列标签。
struct RecognizedNutritionTextLine: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        boundingBox: CGRect
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

enum NutritionLabelOCRError: LocalizedError {
    case emptyImageData
    case unreadableImage
    case recognitionFailed(String)
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .emptyImageData:
            return "照片数据为空，请重新拍摄"
        case .unreadableImage:
            return "无法读取这张营养表照片"
        case .recognitionFailed:
            return "本机文字识别失败"
        case .noTextFound:
            return "没有识别到营养表文字，请靠近并保持镜头平行后重拍"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .recognitionFailed(let message):
            return message
        case .emptyImageData, .unreadableImage, .noTextFound:
            return nil
        }
    }
}

protocol NutritionLabelTextRecognizing {
    func recognize(imageData: Data) async throws -> [RecognizedNutritionTextLine]
}

/// 为核对页生成轻量预览，避免在主线程解码相机的 48MP 原图。
enum NutritionLabelPreviewPreparer {
    static let previewMaxPixelSize = 720

    static func makePreview(imageData: Data) async -> UIImage? {
        let worker = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(
                      imageData as CFData,
                      [kCGImageSourceShouldCache: false] as CFDictionary
                  ) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: previewMaxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]

            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ),
            !Task.isCancelled else {
                return nil
            }
            return UIImage(cgImage: image, scale: 1, orientation: .up)
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

/// 完全在设备上运行的 Vision OCR；照片不会上传，也不会持久化原图。
struct VisionNutritionLabelTextRecognizer: NutritionLabelTextRecognizing {
    static let recognitionMaxPixelSize = 2_400

    func recognize(imageData: Data) async throws -> [RecognizedNutritionTextLine] {
        guard !imageData.isEmpty else {
            throw NutritionLabelOCRError.emptyImageData
        }

        let worker = Task.detached(priority: .userInitiated) {
            try Self.recognizeSynchronously(imageData: imageData)
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func recognizeSynchronously(
        imageData: Data
    ) throws -> [RecognizedNutritionTextLine] {
        try Task.checkCancellation()

        guard let source = CGImageSourceCreateWithData(
            imageData as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
        CGImageSourceGetCount(source) > 0 else {
            throw NutritionLabelOCRError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: recognitionMaxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw NutritionLabelOCRError.unreadableImage
        }

        try Task.checkCancellation()

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]
        request.minimumTextHeight = 0.008
        request.customWords = [
            "Calories", "Nutrition Facts", "Serving size",
            "Total Fat", "Saturated Fat", "Trans Fat", "Cholesterol",
            "Sodium", "Total Carbohydrate", "Dietary Fiber",
            "Total Sugars", "Added Sugars", "Protein",
            "营养成分表", "每份", "每100克", "每100毫升",
            "能量", "蛋白质", "脂肪", "碳水化合物", "膳食纤维", "钠"
        ]

        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            throw NutritionLabelOCRError.recognitionFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        let lines = (request.results ?? []).compactMap { observation -> RecognizedNutritionTextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedNutritionTextLine(
                text: text,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
        .sorted { lhs, rhs in
            let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if verticalDistance > 0.018 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        guard !lines.isEmpty else {
            throw NutritionLabelOCRError.noTextFound
        }
        return lines
    }
}
