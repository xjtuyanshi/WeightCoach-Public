import Foundation
import SwiftUI
import WidgetKit

enum AppLanguageStorage {
    static let appGroupIdentifier = "group.com.lukegogogo.WeightCoach"
    static let storageKey = "app.language.selection"
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    var id: String { rawValue }

    var displayNameLocalizationKey: String {
        switch self {
        case .system: return "language.system"
        case .simplifiedChinese: return "language.zh-Hans"
        case .traditionalChinese: return "language.zh-Hant"
        case .english: return "language.en"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .simplifiedChinese, .traditionalChinese, .english:
            return Locale(identifier: rawValue)
        }
    }

    static func sharedSelection(
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppLanguageStorage.appGroupIdentifier
        )
    ) -> AppLanguage {
        guard
            let rawValue = defaults?.string(forKey: AppLanguageStorage.storageKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }

    func resolvedLanguage(systemLocale: Locale = .autoupdatingCurrent) -> AppLanguage {
        guard self == .system else { return self }

        let identifier = systemLocale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if identifier.hasPrefix("zh") {
            let usesTraditionalChinese =
                identifier.contains("hant")
                || identifier.contains("-tw")
                || identifier.contains("-hk")
                || identifier.contains("-mo")
            return usesTraditionalChinese ? .traditionalChinese : .simplifiedChinese
        }
        if identifier.hasPrefix("en") {
            return .english
        }
        return .simplifiedChinese
    }

    func localizedString(
        _ key: String,
        bundle: Bundle = .main,
        systemLocale: Locale = .autoupdatingCurrent
    ) -> String {
        let localization = resolvedLanguage(systemLocale: systemLocale).rawValue
        guard
            let path = bundle.path(forResource: localization, ofType: "lproj"),
            let localizedBundle = Bundle(path: path)
        else {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Resolves a runtime localization key against the locale selected inside the
/// app instead of relying on the process-wide preferred language.
///
/// SwiftUI localizes string literals automatically. Runtime keys stored in
/// models and services need an explicit `.lproj` lookup so unit tests, widgets,
/// and an in-app language override all agree.
func interfaceLocalized(
    _ key: String,
    locale: Locale,
    bundle: Bundle = .main
) -> String {
    let language = AppLanguage.system.resolvedLanguage(systemLocale: locale)
    return language.localizedString(
        key,
        bundle: bundle,
        systemLocale: locale
    )
}

@MainActor
final class LanguageStore: ObservableObject {
    static let appGroupIdentifier = AppLanguageStorage.appGroupIdentifier
    static let storageKey = AppLanguageStorage.storageKey

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: Self.storageKey)
            reloadWidgets()
        }
    }

    var locale: Locale { selection.locale }

    private let defaults: UserDefaults
    private let reloadWidgets: () -> Void

    convenience init() {
        let defaults =
            UserDefaults(suiteName: Self.appGroupIdentifier)
            ?? .standard
        self.init(
            defaults: defaults,
            reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    init(
        defaults: UserDefaults,
        reloadWidgets: @escaping () -> Void = {}
    ) {
        self.defaults = defaults
        self.reloadWidgets = reloadWidgets

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if
            arguments.contains("-demoData"),
            let index = arguments.firstIndex(of: "-demoLanguage"),
            index + 1 < arguments.count,
            let demoLanguage = AppLanguage(rawValue: arguments[index + 1])
        {
            selection = demoLanguage
            defaults.set(demoLanguage.rawValue, forKey: Self.storageKey)
            return
        }
        #endif

        if
            let storedValue = defaults.string(forKey: Self.storageKey),
            let storedLanguage = AppLanguage(rawValue: storedValue)
        {
            selection = storedLanguage
        } else {
            selection = .system
            defaults.set(AppLanguage.system.rawValue, forKey: Self.storageKey)
        }
    }

    func localizedString(_ key: String, bundle: Bundle = .main) -> String {
        selection.localizedString(key, bundle: bundle)
    }
}
