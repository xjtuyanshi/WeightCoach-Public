import Foundation

struct MacMiniBridgeHealth: Sendable, Equatable {
    let model: String
    let codexVersion: String?
}

enum MacMiniFoodRecognitionError: LocalizedError {
    case invalidImage
    case bridgeUnavailable
    case bridgeNeedsUpgrade
    case unauthorized
    case busy
    case subscriptionUnavailable
    case timedOut
    case invalidResponse
    case remoteFailure(String)

    var errorDescription: String? {
        message(locale: AppLanguage.sharedSelection().locale)
    }

    func message(locale: Locale) -> String {
        switch self {
        case .invalidImage:
            return interfaceLocalized(
                "这张照片无法发送，请重拍或换一张照片。",
                locale: locale
            )
        case .bridgeUnavailable:
            return interfaceLocalized(
                "暂时连不上 Mac mini。请确认 Mac mini 已开机、已登录 ChatGPT，并且手机已连接 Tailscale。",
                locale: locale
            )
        case .bridgeNeedsUpgrade:
            switch AppLanguage.system.resolvedLanguage(systemLocale: locale) {
            case .english:
                return "The Mac mini bridge is an older version and does not support text food logging yet. Update and restart the WeightCoach bridge on the Mac mini."
            case .traditionalChinese:
                return "Mac mini 辨識橋接版本較舊，尚未支援一句話補記。請先更新並重新啟動 Mac mini 上的 WeightCoach 橋接服務。"
            case .simplifiedChinese, .system:
                return "Mac mini 识别桥接版本较旧，暂不支持一句话补记。请先更新并重启 Mac mini 上的 WeightCoach 桥接服务。"
            }
        case .unauthorized:
            return interfaceLocalized(
                "当前设备不在允许的 Tailscale 账户中，Mac mini 已拒绝识别请求。",
                locale: locale
            )
        case .busy:
            return interfaceLocalized(
                "Mac mini 正在识别上一张照片，请稍等十几秒后重试。",
                locale: locale
            )
        case .subscriptionUnavailable:
            return interfaceLocalized(
                "Mac mini 上的 ChatGPT 登录或订阅额度暂时不可用，请在 Mac mini 的 ChatGPT 中检查登录状态。",
                locale: locale
            )
        case .timedOut:
            return interfaceLocalized(
                "这次识别等待超时，请保持 Mac mini 在线后重试。",
                locale: locale
            )
        case .invalidResponse:
            return interfaceLocalized(
                "Mac mini 返回的识别结果不完整，请重试或手动填写。",
                locale: locale
            )
        case .remoteFailure:
            // 远端自由文本可能使用任意语言，也不应直接暴露内部细节。
            return interfaceLocalized(
                "Mac mini 识别失败，请重试或手动填写。",
                locale: locale
            )
        }
    }
}

struct MacMiniFoodRecognitionProvider:
    FoodRecognitionProviding,
    FoodTextRecognitionProviding
{
    let availability: FoodRecognitionAvailability = .available

    private let baseURL: URL
    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(
        baseURL: URL,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 115
    ) {
        self.baseURL = baseURL
        self.session = session
        self.requestTimeout = requestTimeout
    }

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
        guard !jpegData.isEmpty, jpegData.count <= 5_000_000 else {
            throw MacMiniFoodRecognitionError.invalidImage
        }

        let resolvedLanguage = outputLanguage.resolvedLanguage()
        let payload = RecognitionRequest(
            schemaVersion: 1,
            imageBase64: jpegData.base64EncodedString(),
            outputLanguage: resolvedLanguage.rawValue
        )
        var request = URLRequest(url: endpoint("v1/recognize"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WeightCoach-iOS/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await perform(request)
        let response = try decodedRecognitionResponse(from: data)
        guard let inputKind = response.inputKind else {
            // 缺少图片类型时无法安全区分餐盘与账单。旧桥必须升级，
            // 不能把未知类型默认为餐盘而绕过账单确认与缩略图隐私规则。
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        switch inputKind {
        case .foodPhoto, .receiptOrMenu:
            break
        case .nonFood:
            guard response.foods.isEmpty else {
                throw MacMiniFoodRecognitionError.invalidResponse
            }
        case .textDescription:
            // 图片端点绝不能接受文本结果类型，否则会绕过输入类型边界。
            throw MacMiniFoodRecognitionError.invalidResponse
        }

        return try recognizedFoods(
            from: response,
            inputKind: inputKind,
            outputLanguage: resolvedLanguage
        )
    }

    func analyze(text: String) async throws -> [RecognizedFood] {
        try await analyze(
            text: text,
            outputLanguage: .simplifiedChinese
        )
    }

    func analyze(
        text: String,
        outputLanguage: AppLanguage
    ) async throws -> [RecognizedFood] {
        try await analyze(
            text: text,
            outputLanguage: outputLanguage,
            requestID: UUID()
        )
    }

    func analyze(
        text: String,
        outputLanguage: AppLanguage,
        requestID: UUID
    ) async throws -> [RecognizedFood] {
        let validatedText = try FoodTextRecognitionInput.validated(text)
        let resolvedLanguage = outputLanguage.resolvedLanguage()
        let payload = TextRecognitionRequest(
            schemaVersion: 1,
            requestID: requestID.uuidString.lowercased(),
            text: validatedText,
            outputLanguage: resolvedLanguage.rawValue
        )
        var request = URLRequest(url: endpoint("v1/recognize-text"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WeightCoach-iOS/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await perform(
            request,
            mapsNotFoundToBridgeUpgrade: true
        )
        let response = try decodedRecognitionResponse(from: data)
        guard response.inputKind == .textDescription else {
            // 文本端点只能返回 text_description；旧图片类型和未知类型一律失败关闭。
            throw MacMiniFoodRecognitionError.invalidResponse
        }

        var foods = try recognizedFoods(
            from: response,
            inputKind: .textDescription,
            outputLanguage: resolvedLanguage
        )
        guard !foods.isEmpty else {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        for index in foods.indices {
            // 自然语言无法证明份量、品牌或烹调方式；即使远端漏标也必须人工确认。
            foods[index].needsConfirmation = true
        }
        return foods
    }

    func cancelTextAnalysis(requestID: UUID) async -> Bool {
        let payload = TextRecognitionCancellationRequest(
            schemaVersion: 1,
            requestID: requestID.uuidString.lowercased()
        )
        guard let body = try? JSONEncoder().encode(payload) else { return false }

        var request = URLRequest(url: endpoint("v1/cancel-text"))
        request.httpMethod = "POST"
        request.timeoutInterval = min(requestTimeout, 10)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WeightCoach-iOS/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return false
            }
            let acknowledgement = try JSONDecoder().decode(
                TextRecognitionCancellationResponse.self,
                from: data
            )
            return acknowledgement.schemaVersion == 1
                && acknowledgement.requestID == requestID.uuidString.lowercased()
                && acknowledgement.status == "cancelled"
        } catch {
            // 关闭页面时仍是尽力而为；重试流程会读取 false 并停止发出新请求。
            return false
        }
    }

    private func decodedRecognitionResponse(
        from data: Data
    ) throws -> RecognitionResponse {
        let response: RecognitionResponse
        do {
            response = try JSONDecoder().decode(RecognitionResponse.self, from: data)
        } catch {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        guard response.schemaVersion == 1 else {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        return response
    }

    private func recognizedFoods(
        from response: RecognitionResponse,
        inputKind: RecognitionInputKind,
        outputLanguage: AppLanguage
    ) throws -> [RecognizedFood] {
        var foods = try response.foods.map {
            try validatedFood($0, inputKind: inputKind)
        }
        let warnings = response.warnings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !warnings.isEmpty, !foods.isEmpty {
            let separator = outputLanguage == .english ? "; " : "；"
            let warningText = warnings.joined(separator: separator)
            foods[0].note = [foods[0].note, warningText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: separator)
            foods[0].needsConfirmation = true
        }
        return foods
    }

    func checkHealth() async throws -> MacMiniBridgeHealth {
        var request = URLRequest(url: endpoint("health"))
        request.timeoutInterval = 20
        request.setValue("WeightCoach-iOS/1", forHTTPHeaderField: "User-Agent")
        let data = try await perform(request)
        let response: HealthResponse
        do {
            response = try JSONDecoder().decode(HealthResponse.self, from: data)
        } catch {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        guard response.status == "ready",
              response.schemaVersion == 1,
              response.codexAuthenticated else {
            throw MacMiniFoodRecognitionError.subscriptionUnavailable
        }
        return MacMiniBridgeHealth(
            model: response.model,
            codexVersion: response.codexVersion
        )
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private func perform(
        _ request: URLRequest,
        mapsNotFoundToBridgeUpgrade: Bool = false
    ) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MacMiniFoodRecognitionError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw error(
                    for: httpResponse.statusCode,
                    data: data,
                    mapsNotFoundToBridgeUpgrade: mapsNotFoundToBridgeUpgrade
                )
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MacMiniFoodRecognitionError {
            throw error
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled {
                throw CancellationError()
            }
            switch error.code {
            case .timedOut:
                throw MacMiniFoodRecognitionError.timedOut
            case .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .notConnectedToInternet:
                throw MacMiniFoodRecognitionError.bridgeUnavailable
            default:
                throw MacMiniFoodRecognitionError.bridgeUnavailable
            }
        } catch {
            throw MacMiniFoodRecognitionError.bridgeUnavailable
        }
    }

    private func error(
        for statusCode: Int,
        data: Data,
        mapsNotFoundToBridgeUpgrade: Bool
    ) -> MacMiniFoodRecognitionError {
        let errorResponse = try? JSONDecoder().decode(BridgeErrorResponse.self, from: data)
        switch statusCode {
        case 404 where mapsNotFoundToBridgeUpgrade:
            return .bridgeNeedsUpgrade
        case 401, 403:
            return .unauthorized
        case 408, 504:
            return .timedOut
        case 409, 429:
            return errorResponse?.error.code == "subscription_unavailable"
                ? .subscriptionUnavailable
                : .busy
        case 503:
            if errorResponse?.error.code == "subscription_unavailable" {
                return .subscriptionUnavailable
            }
            return .bridgeUnavailable
        default:
            let message = errorResponse?.error.message
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                return .remoteFailure(message)
            }
            return .invalidResponse
        }
    }

    private func validatedFood(
        _ food: RecognitionFoodResponse,
        inputKind: RecognitionInputKind
    ) throws -> RecognizedFood {
        let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let portion = food.portion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= 80,
              !portion.isEmpty,
              portion.count <= 120,
              food.calories.isFinite,
              (1...5_000).contains(food.calories),
              food.confidence.isFinite,
              (0...1).contains(food.confidence) else {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        let bounds = try validatedCalorieBounds(
            lower: food.caloriesMin,
            estimate: food.calories,
            upper: food.caloriesMax
        )

        return RecognizedFood(
            name: name,
            portion: portion,
            calories: food.calories,
            protein: try validatedNutrient(food.protein),
            carbs: try validatedNutrient(food.carbs),
            fat: try validatedNutrient(food.fat),
            calorieLowerBound: bounds?.lower,
            calorieUpperBound: bounds?.upper,
            caffeineMg: try validatedCaffeine(food.caffeineMg),
            confidence: food.confidence,
            needsConfirmation: food.needsConfirmation,
            note: food.note?.trimmingCharacters(in: .whitespacesAndNewlines),
            inputKind: inputKind
        )
    }

    private func validatedNutrient(_ value: Double?) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, (0...1_000).contains(value) else {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        return value
    }

    private func validatedCaffeine(_ value: Double?) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, (0...2_000).contains(value) else {
            throw MacMiniFoodRecognitionError.invalidResponse
        }
        return value
    }

    private func validatedCalorieBounds(
        lower: Double?,
        estimate: Double,
        upper: Double?
    ) throws -> (lower: Double, upper: Double)? {
        switch (lower, upper) {
        case (nil, nil):
            return nil
        case let (lower?, upper?)
            where lower.isFinite
                && upper.isFinite
                && (0...5_000).contains(lower)
                && (0...5_000).contains(upper)
                && lower <= estimate
                && estimate <= upper:
            return (lower, upper)
        default:
            throw MacMiniFoodRecognitionError.invalidResponse
        }
    }
}

private struct RecognitionRequest: Encodable {
    let schemaVersion: Int
    let imageBase64: String
    let outputLanguage: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case imageBase64 = "image_base64"
        case outputLanguage = "output_language"
    }
}

private struct TextRecognitionRequest: Encodable {
    let schemaVersion: Int
    let requestID: String
    let text: String
    let outputLanguage: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case text
        case outputLanguage = "output_language"
    }
}

private struct TextRecognitionCancellationRequest: Encodable {
    let schemaVersion: Int
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
    }
}

private struct TextRecognitionCancellationResponse: Decodable {
    let schemaVersion: Int
    let requestID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case status
    }
}

private struct RecognitionResponse: Decodable {
    let schemaVersion: Int
    let inputKind: RecognitionInputKind?
    let foods: [RecognitionFoodResponse]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case inputKind = "input_kind"
        case foods
        case warnings
    }
}

private struct RecognitionFoodResponse: Decodable {
    let name: String
    let portion: String
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let caloriesMin: Double?
    let caloriesMax: Double?
    let caffeineMg: Double?
    let confidence: Double
    let needsConfirmation: Bool
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name
        case portion
        case calories
        case protein
        case carbs
        case fat
        case caloriesMin = "calories_min"
        case caloriesMax = "calories_max"
        case caffeineMg = "caffeine_mg"
        case confidence
        case needsConfirmation = "needs_confirmation"
        case note
    }
}

private struct HealthResponse: Decodable {
    let status: String
    let schemaVersion: Int
    let codexAuthenticated: Bool
    let codexVersion: String?
    let model: String

    enum CodingKeys: String, CodingKey {
        case status
        case schemaVersion = "schema_version"
        case codexAuthenticated = "codex_authenticated"
        case codexVersion = "codex_version"
        case model
    }
}

private struct BridgeErrorResponse: Decodable {
    let error: BridgeErrorBody
}

private struct BridgeErrorBody: Decodable {
    let code: String
    let message: String
}
