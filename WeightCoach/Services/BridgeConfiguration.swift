import Foundation

enum BridgeConfigurationError: LocalizedError, Equatable {
    case invalidURL

    var errorDescription: String? {
        message(locale: AppLanguage.sharedSelection().locale)
    }

    func message(locale: Locale) -> String {
        interfaceLocalized(
            "请输入完整的 HTTPS 地址；地址不能包含用户名、密码、查询参数或片段。",
            locale: locale
        )
    }
}

struct BridgeConfigurationResolution: Equatable {
    enum Source: Equatable {
        case userDefaults
        case bundledLocalFile
    }

    let baseURL: URL
    let source: Source
}

enum BridgeConfiguration {
    static let userDefaultsURLKey = "recognition.bridge.baseURL"
    static let userDefaultsDisabledKey = "recognition.bridge.disabled"
    static let bundledResourceName = "BridgeConfigLocal"
    static let bundledURLKey = "BridgeBaseURL"
    static let restoreBundledConfigurationArgument =
        "-restoreBundledBridgeConfiguration"

    static func validatedBaseURL(_ rawValue: String?) throws -> URL {
        let trimmed = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw BridgeConfigurationError.invalidURL
        }

        components.scheme = "https"
        if components.path == "/" {
            components.path = ""
        }
        guard let url = components.url else {
            throw BridgeConfigurationError.invalidURL
        }
        return url
    }

    static func resolve(
        persistedValue: String?,
        isExplicitlyDisabled: Bool,
        bundledValue: String?
    ) -> BridgeConfigurationResolution? {
        if isExplicitlyDisabled {
            return nil
        }
        if let persistedValue {
            guard let url = try? validatedBaseURL(persistedValue) else {
                // A malformed explicit value must fail closed instead of
                // silently falling back to a bundled machine address.
                return nil
            }
            return BridgeConfigurationResolution(
                baseURL: url,
                source: .userDefaults
            )
        }
        if let bundledValue,
           let url = try? validatedBaseURL(bundledValue) {
            return BridgeConfigurationResolution(
                baseURL: url,
                source: .bundledLocalFile
            )
        }
        return nil
    }

    static func current(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> BridgeConfigurationResolution? {
        resolve(
            persistedValue: defaults.string(forKey: userDefaultsURLKey),
            isExplicitlyDisabled: defaults.bool(forKey: userDefaultsDisabledKey),
            bundledValue: bundledValue(in: bundle)
        )
    }

    @discardableResult
    static func save(
        _ rawValue: String,
        defaults: UserDefaults = .standard
    ) throws -> URL {
        let url = try validatedBaseURL(rawValue)
        defaults.set(url.absoluteString, forKey: userDefaultsURLKey)
        defaults.removeObject(forKey: userDefaultsDisabledKey)
        return url
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsURLKey)
        defaults.set(true, forKey: userDefaultsDisabledKey)
    }

    /// Explicit repair path for a personal development build whose bundled
    /// bridge URL was disabled by a prior UI bug. Normal launches never alter
    /// the user's saved/disabled choice, and public builds have no bundled URL.
    @discardableResult
    static func restoreBundledConfigurationIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> URL? {
        guard arguments.contains(restoreBundledConfigurationArgument) else {
            return nil
        }
        return restoreBundledConfiguration(
            bundledValue: bundledValue(in: bundle),
            defaults: defaults
        )
    }

    @discardableResult
    static func restoreBundledConfiguration(
        bundledValue: String?,
        defaults: UserDefaults
    ) -> URL? {
        guard let url = try? validatedBaseURL(bundledValue) else {
            return nil
        }
        defaults.set(url.absoluteString, forKey: userDefaultsURLKey)
        defaults.removeObject(forKey: userDefaultsDisabledKey)
        return url
    }

    private static func bundledValue(in bundle: Bundle) -> String? {
        guard let url = bundle.url(
            forResource: bundledResourceName,
            withExtension: "plist"
        ),
        let dictionary = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }
        return dictionary[bundledURLKey] as? String
    }
}
