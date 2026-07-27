import XCTest
@testable import WeightCoach

final class AppLanguageTests: XCTestCase {
    func testRawValuesRemainStableForSharedStorage() {
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
        XCTAssertEqual(AppLanguage.simplifiedChinese.rawValue, "zh-Hans")
        XCTAssertEqual(AppLanguage.traditionalChinese.rawValue, "zh-Hant")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
    }

    @MainActor
    func testLanguageStorePersistsSelectionAndReloadsWidgets() {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var reloadCount = 0
        let store = LanguageStore(
            defaults: defaults,
            reloadWidgets: { reloadCount += 1 }
        )

        XCTAssertEqual(store.selection, .system)
        XCTAssertEqual(
            defaults.string(forKey: AppLanguageStorage.storageKey),
            AppLanguage.system.rawValue
        )

        store.selection = .traditionalChinese

        XCTAssertEqual(reloadCount, 1)
        XCTAssertEqual(
            defaults.string(forKey: AppLanguageStorage.storageKey),
            AppLanguage.traditionalChinese.rawValue
        )

        let restored = LanguageStore(defaults: defaults)
        XCTAssertEqual(restored.selection, .traditionalChinese)
    }

    @MainActor
    func testLanguageStoreRepairsUnknownPersistedValue() {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unsupported", forKey: AppLanguageStorage.storageKey)

        let store = LanguageStore(defaults: defaults)

        XCTAssertEqual(store.selection, .system)
        XCTAssertEqual(
            defaults.string(forKey: AppLanguageStorage.storageKey),
            AppLanguage.system.rawValue
        )
    }

    func testExplicitAndSystemLocalesResolveCorrectly() {
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.locale.identifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.traditionalChinese.locale.identifier, "zh-Hant")

        XCTAssertEqual(
            AppLanguage.system.resolvedLanguage(
                systemLocale: Locale(identifier: "zh_TW")
            ),
            .traditionalChinese
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguage(
                systemLocale: Locale(identifier: "zh_CN")
            ),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguage(
                systemLocale: Locale(identifier: "en_US")
            ),
            .english
        )
    }

    func testExplicitLocalizationUsesRequestedCatalog() {
        XCTAssertEqual(
            AppLanguage.english.localizedString("tab.today"),
            "Today"
        )
        XCTAssertEqual(
            AppLanguage.traditionalChinese.localizedString("tab.weight"),
            "體重"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.localizedString("language.system"),
            "跟随系统"
        )
    }

    func testLanguagePickerLabelsUseCurrentInterfaceLanguage() {
        let englishLabels = AppLanguage.allCases.map {
            AppLanguage.english.localizedString($0.displayNameLocalizationKey)
        }
        XCTAssertEqual(
            englishLabels,
            [
                "Follow System",
                "Simplified Chinese",
                "Traditional Chinese",
                "English",
            ]
        )

        XCTAssertEqual(
            AppLanguage.traditionalChinese.localizedString(
                AppLanguage.system.displayNameLocalizationKey
            ),
            "跟隨系統"
        )
    }

    func testCoreFlowCopyUsesEnglishAndTraditionalCatalogs() {
        let examples: [(key: String, english: String, traditional: String)] = [
            ("体重趋势", "Weight Trend", "體重趨勢"),
            ("饮食记录", "Food Log", "飲食記錄"),
            ("运动补记", "Manual Exercise", "補記運動"),
            ("扫描营养表", "Scan Nutrition Label", "掃描營養標示"),
            ("星巴克定制核对", "Starbucks Customization Check", "星巴克客製核對"),
            ("身体成分与校准", "Body Composition & Calibration", "身體組成與校準"),
            ("咖啡因说明", "About Caffeine", "咖啡因說明"),
            ("欢迎使用减重助手", "Welcome to WeightCoach", "歡迎使用減重助手"),
            ("没有相机权限", "No Camera Access", "沒有相機權限"),
        ]

        for example in examples {
            XCTAssertEqual(
                AppLanguage.english.localizedString(example.key),
                example.english,
                example.key
            )
            XCTAssertEqual(
                AppLanguage.traditionalChinese.localizedString(example.key),
                example.traditional,
                example.key
            )
        }
    }

    func testReminderCopyIsPureAndLocalized() {
        XCTAssertEqual(
            ReminderNotificationCopy.make(
                for: .food,
                language: .english
            ),
            ReminderNotificationCopy(
                title: "WeightCoach",
                body: "You haven't logged any food today"
            )
        )
        XCTAssertEqual(
            ReminderNotificationCopy.make(
                for: .weight,
                language: .traditionalChinese
            ),
            ReminderNotificationCopy(
                title: "減重助手",
                body: "早安，記得量體重"
            )
        )
        XCTAssertEqual(
            ReminderNotificationCopy.make(
                for: .food,
                language: .system,
                systemLocale: Locale(identifier: "zh_CN")
            ),
            ReminderNotificationCopy(
                title: "减重助手",
                body: "今天还没记录饮食"
            )
        )
    }

    func testCompiledCriticalRuntimeCatalogKeysExistInAllLanguages() {
        let examples: [
            (
                key: String,
                simplified: String,
                traditional: String,
                english: String
            )
        ] = [
            ("tab.today", "今日", "今日", "Today"),
            ("language.system", "跟随系统", "跟隨系統", "Follow System"),
            ("common_food.broccoli-raw.name", "西兰花", "青花菜", "Broccoli"),
            ("common_food.unit.grams", "克", "公克", "g"),
            (
                "允许云端分析这张照片？",
                "允许云端分析这张照片？",
                "允許雲端分析這張照片？",
                "Allow Cloud Analysis of This Photo?"
            ),
            (
                "体脂率需大于 3% 且小于 70%，或留空。",
                "体脂率需大于 3% 且小于 70%，或留空。",
                "體脂率必須大於 3% 且小於 70%，或留白。",
                "Body fat must be greater than 3% and less than 70%, or leave it blank."
            ),
            (
                "识别仍在继续。本次照片会保留在本页；你可以继续等待，或停止等待后重试。",
                "识别仍在继续。本次照片会保留在本页；你可以继续等待，或停止等待后重试。",
                "辨識仍在繼續。這次的照片會保留在本頁；你可以繼續等待，或停止等待後重試。",
                "Recognition is still running. This photo will stay on this page; you can keep waiting or stop and retry."
            ),
            (
                "请输入完整的 HTTPS 地址；地址不能包含用户名、密码、查询参数或片段。",
                "请输入完整的 HTTPS 地址；地址不能包含用户名、密码、查询参数或片段。",
                "請輸入完整的 HTTPS 位址；位址不得包含使用者名稱、密碼、查詢參數或片段。",
                "Enter a complete HTTPS address. The address must not include a username, password, query parameters, or a fragment."
            ),
        ]

        for example in examples {
            XCTAssertEqual(
                AppLanguage.simplifiedChinese.localizedString(example.key),
                example.simplified
            )
            XCTAssertEqual(
                AppLanguage.traditionalChinese.localizedString(example.key),
                example.traditional
            )
            XCTAssertEqual(
                AppLanguage.english.localizedString(example.key),
                example.english
            )
        }
    }
}
