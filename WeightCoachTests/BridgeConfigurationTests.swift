import Foundation
import XCTest
@testable import WeightCoach

final class BridgeConfigurationTests: XCTestCase {
    func testFreshInstallWithoutPersistedOrBundledURLIsUnavailable() {
        let resolution = BridgeConfiguration.resolve(
            persistedValue: nil,
            isExplicitlyDisabled: false,
            bundledValue: nil
        )

        XCTAssertNil(resolution)
        let provider = FoodRecognitionProviderFactory.make(
            bridgeResolution: resolution
        )
        guard case .unavailable = provider.availability else {
            return XCTFail("无配置时必须明确不可用，不能构造默认个人地址")
        }
    }

    func testAcceptsAndNormalizesHTTPSURL() throws {
        let url = try BridgeConfiguration.validatedBaseURL(
            "  HTTPS://bridge.example.com/  "
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "bridge.example.com")
        XCTAssertEqual(url.absoluteString, "https://bridge.example.com")

        let provider = FoodRecognitionProviderFactory.make(
            bridgeResolution: BridgeConfigurationResolution(
                baseURL: url,
                source: .userDefaults
            )
        )
        XCTAssertEqual(provider.availability, .available)
    }

    func testRejectsHTTPAndUserInfoURLs() {
        let invalidValues = [
            "http://bridge.example.com",
            "https://user@bridge.example.com",
            "https://user:password@bridge.example.com",
            "https://bridge.example.com?token=secret",
            "https://bridge.example.com#private",
        ]

        for value in invalidValues {
            XCTAssertThrowsError(
                try BridgeConfiguration.validatedBaseURL(value),
                "\(value) 必须被拒绝"
            )
        }
    }

    func testInvalidURLMessageUsesRequestedInterfaceLanguage() {
        XCTAssertEqual(
            BridgeConfigurationError.invalidURL.message(
                locale: Locale(identifier: "en-US")
            ),
            "Enter a complete HTTPS address. The address must not include a username, password, query parameters, or a fragment."
        )
        XCTAssertEqual(
            BridgeConfigurationError.invalidURL.message(
                locale: Locale(identifier: "zh-TW")
            ),
            "請輸入完整的 HTTPS 位址；位址不得包含使用者名稱、密碼、查詢參數或片段。"
        )
    }

    func testBundledFallbackCanBeInjectedWithoutPersonalDefault() throws {
        let resolution = try XCTUnwrap(
            BridgeConfiguration.resolve(
                persistedValue: nil,
                isExplicitlyDisabled: false,
                bundledValue: "https://private-device.example.com"
            )
        )

        XCTAssertEqual(
            resolution,
            BridgeConfigurationResolution(
                baseURL: URL(string: "https://private-device.example.com")!,
                source: .bundledLocalFile
            )
        )
    }

    func testPersistedURLOverridesBundleAndExplicitClearDisablesBoth() throws {
        let resolution = try XCTUnwrap(
            BridgeConfiguration.resolve(
                persistedValue: "https://saved.example.com",
                isExplicitlyDisabled: false,
                bundledValue: "https://bundled.example.com"
            )
        )
        XCTAssertEqual(resolution.source, .userDefaults)
        XCTAssertEqual(
            resolution.baseURL,
            URL(string: "https://saved.example.com")
        )

        XCTAssertNil(
            BridgeConfiguration.resolve(
                persistedValue: "https://saved.example.com",
                isExplicitlyDisabled: true,
                bundledValue: "https://bundled.example.com"
            )
        )
    }

    func testMalformedPersistedValueFailsClosedInsteadOfUsingBundle() {
        XCTAssertNil(
            BridgeConfiguration.resolve(
                persistedValue: "http://unsafe.example.com",
                isExplicitlyDisabled: false,
                bundledValue: "https://bundled.example.com"
            )
        )
    }
}
