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
            ("减脂方式", "Fat-Loss Approach", "減脂方式"),
            (
                "尽快减脂（750 千卡/天）",
                "Fast Fat Loss (750 kcal/day)",
                "盡快減脂（每天 750 大卡）"
            ),
            (
                "按日期达标（动态）",
                "Reach Goal by Date (Dynamic)",
                "按日期達標（動態）"
            ),
            ("参考目标日期", "Reference Goal Date", "參考目標日期"),
            ("尽快减脂", "Fast Fat Loss", "盡快減脂"),
            ("计划缺口", "Planned Deficit", "計畫缺口"),
            (
                "实际缺口（最低摄入量限制）",
                "Actual Deficit (Calorie Floor)",
                "實際缺口（最低攝取量限制）"
            ),
            (
                "选择固定 750 千卡缺口，或按目标日期动态调整。",
                "Choose a fixed 750 kcal deficit or dynamic pacing by goal date.",
                "選擇固定 750 大卡缺口，或依目標日期動態調整。"
            ),
            (
                "固定为每天 750 千卡；达到目标体重后归零。若触及最低摄入量，实际缺口会小于 750 千卡。",
                "Fixed at 750 kcal per day until goal weight is reached. If the calorie floor applies, the actual deficit will be below 750 kcal.",
                "固定為每天 750 大卡；達到目標體重後歸零。若觸及最低攝取量下限，實際缺口會低於 750 大卡。"
            ),
            (
                "按剩余体重和目标日期动态调整为每天 250～1,000 千卡。",
                "Adjusts dynamically between 250 and 1,000 kcal per day based on remaining weight and the goal date.",
                "依剩餘體重和目標日期動態調整為每天 250～1,000 大卡。"
            ),
            (
                "此模式每天保持 750 千卡计划缺口；目标日期仅供进度参考，今日热量目标仍受最低摄入量下限约束。",
                "This mode plans a deficit of 750 kcal per day. The goal date is for progress reference only, and today’s calorie goal still respects the calorie floor.",
                "此模式每天維持 750 大卡計畫缺口；目標日期僅供進度參考，今日熱量目標仍受最低攝取量下限約束。"
            ),
            (
                "每日计划缺口会按剩余体重和目标日期动态调整。",
                "The daily planned deficit adjusts dynamically based on remaining weight and the goal date.",
                "每日計畫缺口會依剩餘體重和目標日期動態調整。"
            ),
            (
                "虚线为参考目标轨迹；日期不参与尽快减脂预算。",
                "The dashed line is a reference goal path; the date doesn’t affect the fast-fat-loss budget.",
                "虛線為參考目標軌跡；日期不會影響盡快減脂預算。"
            ),
            ("参考目标轨迹", "Reference Goal Path", "參考目標軌跡"),
            (
                "这是个人参考，不会替代今日预算，也不会改变 TDEE 替代模型、目标缺口策略或安全下限。",
                "This is a personal reference only. It doesn’t replace today’s budget or change the TDEE replacement model, target-deficit approach, or safety floor.",
                "這是個人參考，不會取代今日預算，也不會改變 TDEE 替代模型、目標缺口方式或安全下限。"
            ),
            (
                "仅用于显示个人参考；不进入 BMR、TDEE、目标缺口策略或今日预算。",
                "Display-only personal reference. It doesn’t affect BMR, TDEE, the target-deficit approach, or today’s budget.",
                "僅用於顯示個人參考；不會進入 BMR、TDEE、目標缺口方式或今日預算。"
            ),
            ("体重趋势", "Weight Trend", "體重趨勢"),
            ("饮食记录", "Food Log", "飲食記錄"),
            ("从历史记录添加", "Add from History", "從歷史記錄新增"),
            (
                "选择历史食物",
                "Choose from Food History",
                "選擇歷史食物"
            ),
            (
                "搜索吃过的食物",
                "Search foods you’ve eaten",
                "搜尋吃過的食物"
            ),
            ("原记录", "Original Entry", "原始記錄"),
            ("添加到今天", "Add to Today", "新增到今天"),
            ("份量倍数", "Portion Multiplier", "份量倍數"),
            ("自定义比例", "Custom Multiplier", "自訂比例"),
            (
                "请输入大于 0 的有效比例。",
                "Enter a valid multiplier greater than 0.",
                "請輸入大於 0 的有效比例。"
            ),
            (
                "请输入食用比例。",
                "Enter a portion multiplier.",
                "請輸入食用比例。"
            ),
            (
                "份量比例不能超过 10 倍。",
                "The portion multiplier can’t exceed 10.",
                "份量比例不能超過 10 倍。"
            ),
            (
                "比例格式不正确，请输入 3/4、0.75 或 1.3。",
                "Enter a ratio such as 3/4, 0.75, or 1.3.",
                "比例格式不正確，請輸入 3/4、0.75 或 1.3。"
            ),
            (
                "保存失败，请稍后重试。",
                "Couldn’t save. Please try again later.",
                "儲存失敗，請稍後再試。"
            ),
            (
                "本次营养预览",
                "Nutrition Preview",
                "本次營養預覽"
            ),
            ("运动补记", "Manual Exercise", "補記運動"),
            ("走路", "Walking", "走路"),
            ("力量训练", "Strength Training", "力量訓練"),
            ("补记运动", "Add Manual Exercise", "補記運動"),
            ("删除", "Delete", "刪除"),
            ("删除运动补记", "Delete Manual Exercise", "刪除運動補記"),
            (
                "删除这条运动补记？",
                "Delete This Manual Exercise?",
                "刪除這筆運動補記？"
            ),
            (
                "删除后会立即从相关日期的运动统计中移除；若已计入热量预算，预算也会同步更新。此操作无法撤销。",
                "It will be removed from the exercise totals for the affected dates immediately. If it was included in the calorie budget, the budget will update too. This can’t be undone.",
                "刪除後會立即從相關日期的運動統計中移除；若已計入熱量預算，預算也會同步更新。此操作無法復原。"
            ),
            (
                "双击展开日期和时间选择器。",
                "Double-tap to expand the date and time picker.",
                "點兩下展開日期與時間選擇器。"
            ),
            (
                "时间选择器已展开，双击可收起并采用当前选择。",
                "The time picker is expanded. Double-tap to collapse it and use the current selection.",
                "時間選擇器已展開。點兩下可收合並採用目前選擇。"
            ),
            ("预计结束时间", "Estimated End Time", "預計結束時間"),
            (
                "该时间段与另一条 App 手动补记重叠；请调整开始时间或活动时长。",
                "This period overlaps another manual entry in the app. Adjust the start time or duration.",
                "此時段與另一筆 App 手動補記重疊；請調整開始時間或活動時長。"
            ),
            ("MET 估算", "MET Estimate", "MET 估算"),
            ("未计入预算", "Not in Budget", "未計入預算"),
            ("补记预览", "Manual Entry Preview", "補記預覽"),
            ("健康覆盖", "Health Coverage", "健康涵蓋"),
            (
                "预计实际补入",
                "Expected Supplement",
                "預計實際補入"
            ),
            (
                "正在核对 Apple 健康记录…",
                "Checking Apple Health records…",
                "正在核對 Apple 健康記錄…"
            ),
            (
                "Apple 健康已完整记录这次运动，无需再次补记。",
                "Apple Health already fully recorded this exercise. No manual entry is needed.",
                "Apple 健康已完整記錄這次運動，無需再次補記。"
            ),
            (
                "无法核对 Apple 健康记录，未保存。请重试。",
                "Apple Health records couldn’t be checked, so nothing was saved. Try again.",
                "無法核對 Apple 健康記錄，因此未儲存。請重試。"
            ),
            (
                "无法核对 Apple 健康运动记录，手动补记暂不计入热量预算。请刷新后重试。",
                "Apple Health workout records couldn’t be checked, so manual entries are temporarily excluded from the calorie budget. Refresh and try again.",
                "無法核對 Apple 健康運動記錄，手動補記暫不計入熱量預算。請重新整理後再試。"
            ),
            ("重试核对", "Retry Check", "重試核對"),
            (
                "采用 2024 Adult Compendium 的 MET 群体估算。Apple 健康已记录同类型运动时，App 会按覆盖分钟只补未记录部分；完整覆盖则不会保存。",
                "Uses population MET estimates from the 2024 Adult Compendium. When Apple Health has the same exercise type, the app supplements only uncovered minutes; a fully covered workout won’t be saved.",
                "採用 2024 Adult Compendium 的 MET 群體估算。Apple 健康已記錄同類型運動時，App 只會補上未涵蓋的分鐘；完整涵蓋時不會儲存。"
            ),
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
                "一句话补记",
                "一句话补记",
                "一句話補記",
                "Describe & Log"
            ),
            (
                "允许云端分析这段饮食描述？",
                "允许云端分析这段饮食描述？",
                "允許雲端分析這段飲食描述？",
                "Allow Cloud Analysis of This Description?"
            ),
            (
                "已核对日期和餐次",
                "已核对日期和餐次",
                "已核對日期和餐次",
                "I reviewed the date and meal"
            ),
            (
                "单项热量需在 1–5000 千卡之间",
                "单项热量需在 1–5000 千卡之间",
                "每項熱量須介於 1–5000 大卡之間",
                "Each item must be between 1 and 5,000 kcal"
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
