import Foundation
import XCTest
@testable import WeightCoach

final class MacMiniFoodRecognitionProviderTests: XCTestCase {
    override func tearDown() {
        BridgeURLProtocol.handler = nil
        super.tearDown()
    }

    func testAnalyzeSendsVersionedJPEGAndMapsValidatedResult() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01])
        BridgeURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/recognize")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )
            let body = try Self.bodyData(for: request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["schema_version"] as? Int, 1)
            XCTAssertEqual(json["output_language"] as? String, "zh-Hans")
            XCTAssertEqual(
                Data(base64Encoded: try XCTUnwrap(json["image_base64"] as? String)),
                jpeg
            )
            return Self.response(
                status: 200,
                json: [
                    "schema_version": 1,
                    "input_kind": "food_photo",
                    "analysis_id": "test",
                    "model": "gpt-5.6-terra",
                    "elapsed_ms": 1_250,
                    "foods": [
                        [
                            "name": "鸡胸肉",
                            "portion": "约 170 克",
                            "calories": 281,
                            "protein": 52.7,
                            "carbs": 0,
                            "fat": 6.1,
                            "confidence": 0.84,
                            "needs_confirmation": true,
                            "note": "烹调油不可见",
                        ]
                    ],
                    "warnings": ["请确认烹调油用量"],
                ]
            )
        }

        let foods = try await makeProvider().analyze(jpegData: jpeg)

        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods[0].name, "鸡胸肉")
        XCTAssertEqual(foods[0].calories, 281, accuracy: 0.001)
        XCTAssertEqual(foods[0].protein, 52.7)
        XCTAssertEqual(foods[0].confidence, 0.84)
        XCTAssertEqual(foods[0].inputKind, .foodPhoto)
        XCTAssertTrue(foods[0].needsConfirmation)
        XCTAssertEqual(
            foods[0].note,
            "烹调油不可见；请确认烹调油用量"
        )
    }

    func testAnalyzeSendsTheRequestedRestrictedOutputLanguage() async throws {
        BridgeURLProtocol.handler = { request in
            let body = try Self.bodyData(for: request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(json["output_language"] as? String, "zh-Hant")
            XCTAssertNil(json["prompt"], "App 不得向桥接传任意提示词")
            return Self.response(status: 200, json: Self.validResponse())
        }

        _ = try await makeProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF]),
            outputLanguage: .traditionalChinese
        )
    }

    func testDemoReceiptProviderReturnsConfirmableWholeOrderItems() async throws {
        let foods = try await DemoReceiptFoodRecognitionProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF])
        )

        XCTAssertEqual(foods.count, 13)
        XCTAssertTrue(foods.allSatisfy { $0.inputKind == .receiptOrMenu })
        XCTAssertTrue(foods.allSatisfy(\.needsConfirmation))
        XCTAssertTrue(foods.allSatisfy { $0.calories > 0 })
        XCTAssertTrue(foods.allSatisfy { food in
            guard let lower = food.calorieLowerBound,
                  let upper = food.calorieUpperBound else {
                return false
            }
            return lower <= food.calories && food.calories <= upper
        })
        XCTAssertTrue(
            foods.allSatisfy {
                $0.protein == nil && $0.carbs == nil && $0.fat == nil
            }
        )
        XCTAssertTrue(foods.allSatisfy { $0.note?.contains("实际吃到") == true })
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
    }

    func testDemoRecognitionContentFollowsRequestedLanguage() async throws {
        let englishMeal = try await DemoFoodRecognitionProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF]),
            outputLanguage: .english
        )
        XCTAssertEqual(englishMeal[0].name, "Pan-seared chicken breast")
        XCTAssertEqual(englishMeal[2].portion, "About 120 g")

        let traditionalReceipt = try await DemoReceiptFoodRecognitionProvider()
            .analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF]),
                outputLanguage: .traditionalChinese
            )
        XCTAssertEqual(traditionalReceipt[0].name, "蔬菜米線")
        XCTAssertEqual(traditionalReceipt[0].portion, "帳單：1 份")
        XCTAssertTrue(
            traditionalReceipt[0].note?.contains("按帳單菜名和數量估算")
                == true
        )
    }

    func testAnalyzeMapsEverySupportedInputKindToEachFood() async throws {
        let cases: [(wireValue: String, expected: RecognitionInputKind)] = [
            ("food_photo", .foodPhoto),
            ("receipt_or_menu", .receiptOrMenu),
        ]

        for testCase in cases {
            BridgeURLProtocol.handler = { _ in
                var response = Self.validResponse()
                response["input_kind"] = testCase.wireValue
                var foods = try XCTUnwrap(response["foods"] as? [[String: Any]])
                foods.append(foods[0].merging(["name": "第二项"]) { _, new in new })
                response["foods"] = foods
                return Self.response(status: 200, json: response)
            }

            let foods = try await makeProvider().analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF])
            )

            XCTAssertEqual(foods.count, 2)
            XCTAssertTrue(
                foods.allSatisfy { $0.inputKind == testCase.expected },
                "\(testCase.wireValue) 应赋给每一个识别项"
            )
        }
    }

    func testAnalyzeRejectsMissingInputKindToProtectReceiptRules() async throws {
        BridgeURLProtocol.handler = { _ in
            var response = Self.validResponse()
            response.removeValue(forKey: "input_kind")
            return Self.response(status: 200, json: response)
        }

        do {
            _ = try await makeProvider().analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF])
            )
            XCTFail("缺少 input_kind 时必须失败关闭，不能默认当作餐盘")
        } catch let error as MacMiniFoodRecognitionError {
            guard case .invalidResponse = error else {
                return XCTFail("应返回 invalidResponse，实际为 \(error)")
            }
        }
    }

    func testAnalyzeRejectsUnknownInputKind() async throws {
        BridgeURLProtocol.handler = { _ in
            var response = Self.validResponse()
            response["input_kind"] = "restaurant_receipt"
            return Self.response(status: 200, json: response)
        }

        do {
            _ = try await makeProvider().analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF])
            )
            XCTFail("未知 input_kind 必须被拒绝")
        } catch let error as MacMiniFoodRecognitionError {
            guard case .invalidResponse = error else {
                return XCTFail("应返回 invalidResponse，实际为 \(error)")
            }
        }
    }

    func testAnalyzeRejectsNonFoodKindWithFoodItems() async throws {
        BridgeURLProtocol.handler = { _ in
            var response = Self.validResponse()
            response["input_kind"] = "non_food"
            return Self.response(status: 200, json: response)
        }

        do {
            _ = try await makeProvider().analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF])
            )
            XCTFail("non_food 不能同时包含食物项目")
        } catch let error as MacMiniFoodRecognitionError {
            guard case .invalidResponse = error else {
                return XCTFail("应返回 invalidResponse，实际为 \(error)")
            }
        }
    }

    func testReceiptResultDoesNotGuessOrderShare() async throws {
        BridgeURLProtocol.handler = { _ in
            var response = Self.validResponse()
            response["input_kind"] = "receipt_or_menu"
            return Self.response(status: 200, json: response)
        }

        let foods = try await makeProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF])
        )

        XCTAssertEqual(foods[0].inputKind, .receiptOrMenu)
        XCTAssertEqual(foods[0].calories, 281)
        XCTAssertEqual(foods[0].protein, 52.7)
        XCTAssertEqual(foods[0].portion, "约 170 克")
        XCTAssertFalse(foods[0].note?.contains("整单食用比例") == true)
    }

    func testAnalyzeAcceptsNullMacros() async throws {
        BridgeURLProtocol.handler = { _ in
            Self.response(
                status: 200,
                json: Self.validResponse(
                    protein: NSNull(),
                    carbs: NSNull(),
                    fat: NSNull()
                )
            )
        }

        let foods = try await makeProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF])
        )

        XCTAssertNil(foods[0].protein)
        XCTAssertNil(foods[0].carbs)
        XCTAssertNil(foods[0].fat)
    }

    func testAnalyzeMapsCalorieRangeAndCaffeine() async throws {
        BridgeURLProtocol.handler = { _ in
            var response = Self.validResponse()
            var foods = try XCTUnwrap(response["foods"] as? [[String: Any]])
            foods[0]["calories"] = 400
            foods[0]["calories_min"] = 370
            foods[0]["calories_max"] = 430
            foods[0]["caffeine_mg"] = 300
            response["foods"] = foods
            return Self.response(status: 200, json: response)
        }

        let foods = try await makeProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF])
        )

        XCTAssertEqual(foods[0].calorieLowerBound, 370)
        XCTAssertEqual(foods[0].calorieUpperBound, 430)
        XCTAssertEqual(foods[0].caffeineMg, 300)
    }

    func testAnalyzeRejectsPartialOrInconsistentCalorieRange() async throws {
        for mutation in ["missing_upper", "estimate_outside_range", "excess_caffeine"] {
            BridgeURLProtocol.handler = { _ in
                var response = Self.validResponse()
                var foods = try XCTUnwrap(response["foods"] as? [[String: Any]])
                switch mutation {
                case "missing_upper":
                    foods[0]["calories_min"] = 250
                case "estimate_outside_range":
                    foods[0]["calories_min"] = 300
                    foods[0]["calories_max"] = 350
                default:
                    foods[0]["caffeine_mg"] = 2_001
                }
                response["foods"] = foods
                return Self.response(status: 200, json: response)
            }

            do {
                _ = try await makeProvider().analyze(
                    jpegData: Data([0xFF, 0xD8, 0xFF])
                )
                XCTFail("\(mutation) 应被拒绝")
            } catch let error as MacMiniFoodRecognitionError {
                guard case .invalidResponse = error else {
                    return XCTFail("应返回 invalidResponse，实际为 \(error)")
                }
            }
        }
    }

    func testAnalyzeReturnsEmptyResultForNonFoodImage() async throws {
        BridgeURLProtocol.handler = { _ in
            Self.response(
                status: 200,
                json: [
                    "schema_version": 1,
                    "input_kind": "non_food",
                    "foods": [],
                    "warnings": ["画面中没有可识别的食物"],
                ]
            )
        }

        let foods = try await makeProvider().analyze(
            jpegData: Data([0xFF, 0xD8, 0xFF])
        )

        XCTAssertTrue(foods.isEmpty)
    }

    func testAnalyzeRejectsOutOfRangeNutrition() async throws {
        BridgeURLProtocol.handler = { _ in
            var response = Self.validResponse()
            var foods = try XCTUnwrap(response["foods"] as? [[String: Any]])
            foods[0]["calories"] = -1
            response["foods"] = foods
            return Self.response(status: 200, json: response)
        }

        do {
            _ = try await makeProvider().analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF])
            )
            XCTFail("负热量必须被拒绝")
        } catch let error as MacMiniFoodRecognitionError {
            guard case .invalidResponse = error else {
                return XCTFail("应返回 invalidResponse，实际为 \(error)")
            }
        }
    }

    func testAnalyzeMapsBusyAndSubscriptionErrors() async throws {
        for (code, expectedSubscriptionError) in [
            ("busy", false),
            ("subscription_unavailable", true),
        ] {
            BridgeURLProtocol.handler = { _ in
                Self.response(
                    status: 429,
                    json: [
                        "error": [
                            "code": code,
                            "message": "暂时不可用",
                        ]
                    ]
                )
            }

            do {
                _ = try await makeProvider().analyze(
                    jpegData: Data([0xFF, 0xD8, 0xFF])
                )
                XCTFail("非 2xx 不应返回识别结果")
            } catch let error as MacMiniFoodRecognitionError {
                switch error {
                case .busy:
                    XCTAssertFalse(expectedSubscriptionError)
                case .subscriptionUnavailable:
                    XCTAssertTrue(expectedSubscriptionError)
                default:
                    XCTFail("错误映射不正确：\(error)")
                }
            }
        }
    }

    func testAnalyzeMapsUnauthorizedAndTimeoutErrors() async throws {
        for (status, expectedDescription) in [
            (401, "Tailscale"),
            (504, "超时"),
        ] {
            BridgeURLProtocol.handler = { _ in
                Self.response(
                    status: status,
                    json: [
                        "error": [
                            "code": status == 401
                                ? "unauthorized"
                                : "recognition_timeout",
                            "message": "请求失败",
                        ]
                    ]
                )
            }

            do {
                _ = try await makeProvider().analyze(
                    jpegData: Data([0xFF, 0xD8, 0xFF])
                )
                XCTFail("错误 HTTP 状态不应返回结果")
            } catch {
                let description: String
                if let bridgeError = error as? MacMiniFoodRecognitionError {
                    description = bridgeError.message(
                        locale: Locale(identifier: "zh-Hans")
                    )
                } else {
                    description = error.localizedDescription
                }
                XCTAssertTrue(
                    description.contains(expectedDescription),
                    "错误提示应包含 \(expectedDescription)：\(error)"
                )
            }
        }
    }

    func testAnalyzeMapsURLSessionTimeout() async throws {
        BridgeURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        do {
            _ = try await makeProvider().analyze(
                jpegData: Data([0xFF, 0xD8, 0xFF])
            )
            XCTFail("URLSession 超时不应返回结果")
        } catch let error as MacMiniFoodRecognitionError {
            guard case .timedOut = error else {
                return XCTFail("应映射为 timedOut，实际为 \(error)")
            }
        }
    }

    func testHealthRequiresReadyChatGPTSubscription() async throws {
        BridgeURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/health")
            return Self.response(
                status: 200,
                json: [
                    "status": "ready",
                    "schema_version": 1,
                    "service": "WeightCoach Mac mini Bridge",
                    "codex_authenticated": true,
                    "codex_version": "codex-cli 0.146.0-alpha.3.1",
                    "model": "gpt-5.6-terra",
                ]
            )
        }

        let health = try await makeProvider().checkHealth()

        XCTAssertEqual(health.model, "gpt-5.6-terra")
        XCTAssertEqual(
            health.codexVersion,
            "codex-cli 0.146.0-alpha.3.1"
        )
    }

    func testBridgeErrorsUseRequestedInterfaceLanguage() {
        XCTAssertEqual(
            MacMiniFoodRecognitionError.timedOut.message(
                locale: Locale(identifier: "en")
            ),
            "Recognition timed out. Keep your Mac mini online and try again."
        )
        XCTAssertEqual(
            MacMiniFoodRecognitionError.invalidResponse.message(
                locale: Locale(identifier: "zh-Hant")
            ),
            "Mac mini 回傳的辨識結果不完整，請重試或手動填寫。"
        )
        XCTAssertEqual(
            MacMiniFoodRecognitionError.remoteFailure("内部错误").message(
                locale: Locale(identifier: "en")
            ),
            "Mac mini recognition failed. Try again or enter the food manually."
        )
    }

    private func makeProvider() -> MacMiniFoodRecognitionProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BridgeURLProtocol.self]
        return MacMiniFoodRecognitionProvider(
            baseURL: URL(string: "https://bridge.test")!,
            session: URLSession(configuration: configuration),
            requestTimeout: 1
        )
    }

    private static func validResponse(
        protein: Any = 52.7,
        carbs: Any = 0,
        fat: Any = 6.1
    ) -> [String: Any] {
        [
            "schema_version": 1,
            "input_kind": "food_photo",
            "foods": [
                [
                    "name": "鸡胸肉",
                    "portion": "约 170 克",
                    "calories": 281,
                    "protein": protein,
                    "carbs": carbs,
                    "fat": fat,
                    "confidence": 0.84,
                    "needs_confirmation": true,
                    "note": "请核对",
                ]
            ],
            "warnings": [],
        ]
    }

    private static func response(
        status: Int,
        json: [String: Any]
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://bridge.test")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (response, data)
    }

    private static func bodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class BridgeURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
