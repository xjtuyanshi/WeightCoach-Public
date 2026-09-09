import Foundation
import SwiftData
import UIKit

/// 演示模式：通过启动参数注入示例数据，便于在没有健康数据的模拟器里预览界面。
/// 用法：simctl launch <udid> com.lukegogogo.WeightCoach -demoData -uitab 2
enum DemoMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoData")
    }

    /// 启动时定位到的 Tab（0 今日 / 1 饮食 / 2 运动 / 3 体重 / 4 设置）
    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uitab"),
              index + 1 < args.count,
              let tab = Int(args[index + 1]) else {
            return (
                demoExerciseEnabled
                    || demoThirdPartyExerciseEnabled
                    || demoExerciseHealthQueryFailureEnabled
            ) ? 2 : 0
        }
        return min(max(tab, 0), 4)
    }

    /// 演示模式下直接打开已缓存条码结果，供模拟器视觉验收。
    static var demoBarcodeCode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demoBarcode") else { return nil }
        return "096619365475"
    }

    /// 直接打开演示餐盘，并走完整的图片准备 → 自动识别 → 确认流程。
    static var demoCaptureEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoCapture")
            || demoReceiptEnabled
    }

    /// 直接打开一张演示餐厅账单，验证账单菜品识别与整单食用比例。
    static var demoReceiptEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoReceipt")
    }

    /// 仅用于模拟器验证“保留本次照片后重试”的失败恢复界面。
    static var demoRecognitionFailureEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoRecognitionFailure")
    }

    /// 让演示餐盘改走 Mac mini 的真实 ChatGPT 订阅桥接，用于端到端验收。
    static var realRecognitionEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoRealRecognition")
    }

    /// 直接打开本地营养表 OCR 的确认页，供模拟器视觉验收。
    static var demoNutritionLabelEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoNutritionLabel")
    }

    /// 直接打开身体成分设置页，供模拟器视觉验收。
    static var demoBodyCompositionEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoBodyComposition")
            || demoBodyCompositionBottomEnabled
    }

    /// 打开身体成分设置页并滚到历史/参考区，供第二张截图验收。
    static var demoBodyCompositionBottomEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoBodyCompositionBottom")
    }

    /// 直接打开常见食物参考库，并预选一个大号水煮蛋的标准份量。
    static var demoCommonFoodEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoCommonFood")
    }

    /// 打开统一食物录入，并展示输入单字“西”后的即时联想。
    static var demoFoodAutocompleteEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoFoodAutocomplete")
    }

    /// 把「常吃 + 最近」移到今日页顶部，便于稳定截图验收排序、标签和一键再记。
    static var demoRepeatFoodsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoRepeatFoods")
            || demoFrequentOverflowEnabled
    }

    /// 六种跨日常吃，验证前四种以外的常吃仍会填满剩余卡片。
    static var demoFrequentOverflowEnabled: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("-demoFrequentOverflow")
    }

    /// 打开完整历史复用页，并注入一条 45 天前的唯一记录验证不限近 30 天。
    static var demoHistoryFoodRepeatEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoHistoryFoodRepeat")
    }

    /// 打开一句话补记，并自动演示“1 根烤肠、2 个鸡翅”的估算与确认流程。
    static var demoSentenceBackfillEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoSentenceBackfill")
    }

    /// 打开星巴克定制饮品核对页，显示当前用户订单的估算拆分。
    static var demoStarbucksEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoStarbucks")
    }

    /// 打开运动补记页，并注入一条不戴手表的篮球示例。
    static var demoExerciseEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoExercise")
    }

    /// 模拟同一次跑步同时被第三方 App 与 Apple 健康记录，用于验证日总不会
    /// 重复、且手动补记会识别完整 workout 覆盖。
    static var demoThirdPartyExerciseEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoThirdPartyExercise")
    }

    /// 首次手动运动核对失败，点击重试后恢复。仅用于模拟器
    /// 验收 fail-closed 与重试交互，不改变任何真实 HealthKit 请求。
    static var demoExerciseHealthQueryFailureEnabled: Bool {
        isActive
            && ProcessInfo.processInfo.arguments.contains(
                "-demoExerciseHealthQueryFailure"
            )
    }

    /// 模拟手机已记录 9,500 步、但没有活动能量样本的手表断电场景。
    static var demoMissingActivityEnergyEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoMissingActivityEnergy")
    }

    /// 打开 7/30 天饮食与能量趋势，注入周末盈余、缺失日和宏量覆盖示例。
    static var demoTrendsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoTrends")
    }

    /// 演示趋势固定以最近一个周日为“今天”，确保截图能稳定展示周一至周六的累计。
    static func trendReferenceDate(calendar: Calendar = .current) -> Date {
        guard demoTrendsEnabled else { return .now }
        let todayStart = calendar.startOfDay(for: .now)
        let daysSinceSunday = max(
            0,
            calendar.component(.weekday, from: todayStart) - 1
        )
        let sunday = calendar.date(
            byAdding: .day,
            value: -daysSinceSunday,
            to: todayStart
        ) ?? todayStart
        return calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: sunday
        ) ?? sunday
    }

    static let demoNutritionLabelBarcode = "0123456789012"

    static let demoNutritionLabelLines = [
        "Nutrition Facts",
        "About 4 servings per container",
        "Serving size 5 pieces (85g)",
        "Calories 210",
        "Total Fat 9g 12%",
        "Saturated Fat 2g 10%",
        "Sodium 520mg 23%",
        "Total Carbohydrate 18g 7%",
        "Dietary Fiber 3g 11%",
        "Total Sugars 2g",
        "Protein 14g"
    ]

    static func demoFoodImageData() -> Data? {
        if demoReceiptEnabled {
            return demoReceiptImageData()
        }

        let size = CGSize(width: 1_200, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor(red: 0.91, green: 0.88, blue: 0.80, alpha: 1).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 170, y: 30, width: 860, height: 840))
            UIColor(white: 0.92, alpha: 1).setStroke()
            context.cgContext.setLineWidth(18)
            context.cgContext.strokeEllipse(in: CGRect(x: 190, y: 50, width: 820, height: 800))

            UIColor(red: 0.70, green: 0.42, blue: 0.22, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 315, y: 255, width: 340, height: 245))
            UIColor(red: 0.61, green: 0.29, blue: 0.16, alpha: 1).setStroke()
            context.cgContext.setLineWidth(14)
            for offset in stride(from: 0, through: 230, by: 48) {
                context.cgContext.move(to: CGPoint(x: 360 + offset, y: 290))
                context.cgContext.addLine(to: CGPoint(x: 335 + offset, y: 445))
            }
            context.cgContext.strokePath()

            UIColor(red: 0.69, green: 0.45, blue: 0.23, alpha: 1).setFill()
            for row in 0..<4 {
                for column in 0..<5 {
                    let x = 650 + CGFloat(column * 48) + CGFloat(row % 2) * 14
                    let y = 250 + CGFloat(row * 52)
                    context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 62, height: 42))
                }
            }

            UIColor(red: 0.18, green: 0.55, blue: 0.23, alpha: 1).setFill()
            for index in 0..<11 {
                let angle = CGFloat(index) * .pi * 2 / 11
                let x = 650 + cos(angle) * 130
                let y = 610 + sin(angle) * 105
                context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 105, height: 90))
            }
        }
        return image.jpegData(compressionQuality: 0.82)
    }

    static func historicalTrendHealthData(
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar
    ) -> HistoricalTrendHealthData {
        let todayStart = calendar.startOfDay(for: .now)
        var readings: [DailyActiveEnergyReading] = []
        var dayStart = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        while dayStart < end {
            let daysAgo = calendar.dateComponents(
                [.day],
                from: dayStart,
                to: todayStart
            ).day ?? 0
            // 故意保留一个活动数据缺失日，验证覆盖率和“未知不按 0”。
            if daysAgo != 4 {
                let weekday = calendar.component(.weekday, from: dayStart)
                let isWeekend = weekday == 1 || weekday == 7
                readings.append(
                    DailyActiveEnergyReading(
                        dayStart: dayStart,
                        kcal: isWeekend ? 360 : 520
                    )
                )
            }
            guard let next = calendar.date(
                byAdding: .day,
                value: 1,
                to: dayStart
            ) else {
                break
            }
            dayStart = next
        }

        let exerciseStart = demoTrendExerciseStart(calendar: calendar)
        let overlapSample = HealthActiveEnergyInterval(
            startDate: exerciseStart,
            endDate: exerciseStart.addingTimeInterval(30 * 60),
            kcal: 90
        )
        return HistoricalTrendHealthData(
            dailyActiveEnergy: readings,
            activeEnergyIntervals: overlapSample.map { [$0] } ?? [],
            weightPoints: [],
            bodyFatPoints: [],
            manualOverlapDataAvailable: true
        )
    }

    private static func demoTrendExerciseStart(
        referenceDate: Date = .now,
        calendar: Calendar
    ) -> Date {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let exerciseDay = calendar.date(
            byAdding: .day,
            value: -2,
            to: todayStart
        ) ?? todayStart
        return calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: exerciseDay
        ) ?? exerciseDay
    }

    private static func demoReceiptImageData() -> Data? {
        let size = CGSize(width: 900, height: 1_500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor(red: 0.22, green: 0.19, blue: 0.27, alpha: 1).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            let receiptRect = CGRect(x: 105, y: 45, width: 690, height: 1_410)
            UIColor(white: 0.97, alpha: 1).setFill()
            context.cgContext.fill(receiptRect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            ("演示餐厅\nDemo Garden Grill" as NSString).draw(
                in: CGRect(x: 145, y: 90, width: 610, height: 100),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph,
                ]
            )

            let lines = [
                "1  蔬菜米线                    $12.00",
                "2  烤鸡肉串                    $8.00",
                "2  香菇豆腐串                 $6.50",
                "1  烤玉米（2）               $5.00",
                "2  柠檬鱼串（2）            $9.50",
                "1  蔬菜蒸饺（6）            $8.00",
                "2  烤西兰花（2）            $6.00",
                "2  凉拌黄瓜                    $5.50",
                "1  味噌汤                        $3.00",
                "2  香料牛肉串                 $8.50",
                "1  水果杯（2）               $5.00",
                "1  酸奶杯（5）               $7.00",
            ]
            let lineAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 25, weight: .regular),
                .foregroundColor: UIColor.black,
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 150, y: 245 + CGFloat(index) * 72),
                    withAttributes: lineAttributes
                )
            }

            context.cgContext.setStrokeColor(UIColor.darkGray.cgColor)
            context.cgContext.setLineWidth(3)
            context.cgContext.move(to: CGPoint(x: 145, y: 1_180))
            context.cgContext.addLine(to: CGPoint(x: 755, y: 1_180))
            context.cgContext.strokePath()

            ("Items Subtotal                          $93.50\nGrand Total                              $102.85" as NSString).draw(
                in: CGRect(x: 150, y: 1_225, width: 600, height: 120),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 25, weight: .bold),
                    .foregroundColor: UIColor.black,
                ]
            )
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    static func seedIfNeeded(context: ModelContext) {
        seedProductsIfNeeded(context: context)

        let calendar = Calendar.current
        let now = Date()
        let language = AppLanguage.sharedSelection().resolvedLanguage()
        func text(
            _ simplified: String,
            _ traditional: String,
            _ english: String
        ) -> String {
            switch language {
            case .traditionalChinese:
                traditional
            case .english:
                english
            case .system, .simplifiedChinese:
                simplified
            }
        }
        if demoExerciseEnabled || demoTrendsEnabled {
            seedExerciseIfNeeded(context: context, now: now)
        }

        let foodCount = (try? context.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0
        guard foodCount == 0 else { return }

        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }

        // 今日饮食
        var foods: [FoodEntry] = [
            FoodEntry(name: text("燕麦牛奶粥", "燕麥牛奶粥", "Oat milk oatmeal"),
                      calories: 320, protein: 14, carbs: 48, fat: 8,
                      portionText: text("一大碗", "一大碗", "1 large bowl"),
                      mealType: .breakfast, source: .manual, date: at(8, 10)),
            FoodEntry(name: text("水煮蛋", "水煮蛋", "Hard-boiled egg"),
                      calories: 72, protein: 6, carbs: 0.4, fat: 5,
                      portionText: text("1 个", "1 個", "1 egg"),
                      mealType: .breakfast, source: .manual, date: at(8, 12)),
            FoodEntry(name: text("美式咖啡", "美式咖啡", "Americano"),
                      calories: 15, protein: 1, carbs: 2, fat: 0,
                      portionText: text("Grande（演示）", "Grande（示範）", "Grande (demo)"),
                      mealType: .breakfast, source: .brandCalculator,
                      date: at(8, 15), caffeineMg: 225),
            FoodEntry(name: text("鸡胸肉蔬菜沙拉", "雞胸肉蔬菜沙拉", "Chicken vegetable salad"),
                      calories: 420, protein: 42, carbs: 18, fat: 19,
                      portionText: text("一份（约 350g）", "一份（約 350g）", "1 serving (about 350 g)"),
                      mealType: .lunch, source: .ai, date: at(12, 35)),
            FoodEntry(name: text("全麦面包", "全麥麵包", "Whole-wheat bread"),
                      calories: 160, protein: 8, carbs: 28, fat: 2,
                      portionText: text("2 片", "2 片", "2 slices"),
                      mealType: .lunch, source: .ai, date: at(12, 36)),
            FoodEntry(name: "Kirkland Signature Protein Bar", calories: 190, protein: 21, carbs: 22, fat: 7,
                      portionText: text("1.0 份（60g）", "1.0 份（60g）", "1 serving (60 g)"),
                      mealType: .snack, source: .barcode, date: at(15, 40)),
        ]
        if demoRepeatFoodsEnabled || demoHistoryFoodRepeatEnabled {
            func onPreviousDay(
                _ daysAgo: Int,
                hour: Int,
                minute: Int
            ) -> Date {
                let day = calendar.date(
                    byAdding: .day,
                    value: -daysAgo,
                    to: now
                ) ?? now
                return calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: day
                ) ?? day
            }
            if demoRepeatFoodsEnabled {
                // 只有这个专用场景才注入跨日历史，避免改变其他演示和趋势数据。
                foods.append(contentsOf: [
                FoodEntry(
                    name: "Kirkland Signature Protein Bar",
                    calories: 190,
                    protein: 21,
                    carbs: 22,
                    fat: 7,
                    portionText: text("1.0 份（60g）", "1.0 份（60g）", "1 serving (60 g)"),
                    mealType: .snack,
                    source: .barcode,
                    date: onPreviousDay(1, hour: 15, minute: 40)
                ),
                FoodEntry(
                    name: "Kirkland Signature Protein Bar",
                    calories: 190,
                    protein: 21,
                    carbs: 22,
                    fat: 7,
                    portionText: text("1.0 份（60g）", "1.0 份（60g）", "1 serving (60 g)"),
                    mealType: .snack,
                    source: .barcode,
                    date: onPreviousDay(4, hour: 15, minute: 40)
                ),
                FoodEntry(
                    name: text("水煮蛋", "水煮蛋", "Hard-boiled egg"),
                    calories: 72,
                    protein: 6,
                    carbs: 0.4,
                    fat: 5,
                    portionText: text("1 个", "1 個", "1 egg"),
                    mealType: .breakfast,
                    source: .manual,
                    date: onPreviousDay(1, hour: 8, minute: 12)
                ),
                FoodEntry(
                    name: text("水煮蛋", "水煮蛋", "Hard-boiled egg"),
                    calories: 72,
                    protein: 6,
                    carbs: 0.4,
                    fat: 5,
                    portionText: text("1 个", "1 個", "1 egg"),
                    mealType: .breakfast,
                    source: .manual,
                    date: onPreviousDay(5, hour: 8, minute: 12)
                ),
                FoodEntry(
                    name: text("美式咖啡", "美式咖啡", "Americano"),
                    calories: 15,
                    protein: 1,
                    carbs: 2,
                    fat: 0,
                    portionText: text("Grande（演示）", "Grande（示範）", "Grande (demo)"),
                    mealType: .breakfast,
                    source: .brandCalculator,
                    date: onPreviousDay(2, hour: 8, minute: 15),
                    caffeineMg: 225
                ),
                FoodEntry(
                    name: text("全麦面包", "全麥麵包", "Whole-wheat bread"),
                    calories: 160,
                    protein: 8,
                    carbs: 28,
                    fat: 2,
                    portionText: text("2 片", "2 片", "2 slices"),
                    mealType: .lunch,
                    source: .ai,
                    date: onPreviousDay(3, hour: 12, minute: 36)
                ),
                ])
            }

            if demoHistoryFoodRepeatEnabled {
                foods.append(
                    FoodEntry(
                        name: text(
                            "照烧三文鱼饭（45 天前）",
                            "照燒鮭魚飯（45 天前）",
                            "Teriyaki salmon bowl (45 days ago)"
                        ),
                        calories: 640,
                        protein: 38,
                        carbs: 72,
                        fat: 22,
                        portionText: text(
                            "1 碗（演示历史）",
                            "1 碗（示範歷史）",
                            "1 bowl (demo history)"
                        ),
                        mealType: .dinner,
                        source: .manual,
                        date: onPreviousDay(45, hour: 19, minute: 15),
                        fiber: 6,
                        sugar: 10,
                        sodiumMg: 980
                    )
                )
            }
            if demoFrequentOverflowEnabled {
                // 独立验收数据：每种恰好出现两天，没有一次性食品补位。
                // 使用参考库中文名，亦可验证用繁体/英文搜索旧记录。
                foods = [
                    "white-rice-cooked", "chicken-breast-cooked", "egg-hard-boiled",
                    "banana-raw", "broccoli-raw", "shrimp-cooked",
                ].enumerated().flatMap { index, id -> [FoodEntry] in
                    guard let food = CommonFoodCatalog.food(id: id) else { return [] }
                    let nutrition = food.nutritionPer100Grams
                    return [1, 2].map { daysAgo in
                        FoodEntry(
                            name: food.localizedDisplayName(locale: Locale(identifier: "zh-Hans")),
                            calories: nutrition.energyKcal.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
                            protein: nutrition.proteinG.map { NSDecimalNumber(decimal: $0).doubleValue },
                            carbs: nutrition.carbohydratesG.map { NSDecimalNumber(decimal: $0).doubleValue },
                            fat: nutrition.fatG.map { NSDecimalNumber(decimal: $0).doubleValue },
                            portionText: "100 g",
                            mealType: .lunch,
                            source: .manual,
                            date: onPreviousDay(daysAgo, hour: 12, minute: 10 - index)
                        )
                    }
                }
            }
        }
        if demoTrendsEnabled {
            for daysAgo in 1...29 {
                // 留出一个完全未记录饮食的日期，不能在趋势中伪装成 0 千卡。
                guard daysAgo != 6 else { continue }
                let day = calendar.date(
                    byAdding: .day,
                    value: -daysAgo,
                    to: now
                ) ?? now
                let weekday = calendar.component(.weekday, from: day)
                let isWeekend = weekday == 1 || weekday == 7
                let totalCalories = isWeekend
                    ? 2_850 + Double(daysAgo % 2) * 180
                    : 1_820 + Double(daysAgo % 4) * 70
                let firstCalories = totalCalories * 0.42
                let secondCalories = totalCalories - firstCalories
                let firstDate = calendar.date(
                    bySettingHour: 12,
                    minute: 20,
                    second: 0,
                    of: day
                ) ?? day
                let secondDate = calendar.date(
                    bySettingHour: 19,
                    minute: 10,
                    second: 0,
                    of: day
                ) ?? day
                let hasCompleteMacros = daysAgo != 3

                foods.append(
                    FoodEntry(
                        name: isWeekend
                            ? text("周末午餐（演示）", "週末午餐（示範）", "Weekend lunch (demo)")
                            : text("工作日午餐（演示）", "平日午餐（示範）", "Weekday lunch (demo)"),
                        calories: firstCalories,
                        protein: hasCompleteMacros ? firstCalories / 18 : nil,
                        carbs: hasCompleteMacros ? firstCalories / 9 : nil,
                        fat: hasCompleteMacros ? firstCalories / 38 : nil,
                        portionText: text("演示趋势", "示範趨勢", "Demo trend"),
                        mealType: .lunch,
                        source: .manual,
                        date: firstDate
                    )
                )
                foods.append(
                    FoodEntry(
                        name: isWeekend
                            ? text("周末聚餐（演示）", "週末聚餐（示範）", "Weekend meal (demo)")
                            : text("工作日晚餐（演示）", "平日晚餐（示範）", "Weekday dinner (demo)"),
                        calories: secondCalories,
                        protein: secondCalories / 18,
                        carbs: secondCalories / 9,
                        fat: secondCalories / 38,
                        portionText: text("演示趋势", "示範趨勢", "Demo trend"),
                        mealType: .dinner,
                        source: .manual,
                        date: secondDate
                    )
                )
            }
        }
        foods.forEach { context.insert($0) }

        // 近四周虚构体重（80.0 缓慢降到 78.6）与体脂
        let weightSeries: [(daysAgo: Int, kg: Double, fat: Double?)] = [
            (28, 80.0, 28.1), (25, 79.8, nil), (22, 79.9, 27.8), (19, 79.5, nil),
            (16, 79.4, 27.4), (13, 79.1, nil), (10, 79.2, 27.1), (7, 78.9, nil),
            (5, 78.8, 26.8), (3, 78.9, nil), (1, 78.7, 26.6), (0, 78.6, 26.5),
        ]
        for point in weightSeries {
            let date = calendar.date(byAdding: .day, value: -point.daysAgo, to: at(7, 30)) ?? now
            context.insert(WeightEntry(date: date, weightKg: point.kg, bodyFatPercent: point.fat))
        }

        // 目标起点与演示数据对齐
        let defaults = UserDefaults.standard
        defaults.set(calendar.date(byAdding: .day, value: -28, to: now), forKey: ProfileStore.Keys.goalStartDate)
        defaults.set(calendar.date(byAdding: .day, value: 62, to: now), forKey: ProfileStore.Keys.goalEndDate)
        defaults.set(80.0, forKey: ProfileStore.Keys.goalStartWeight)
        defaults.set(75.0, forKey: ProfileStore.Keys.goalWeight)
    }

    private static func seedExerciseIfNeeded(context: ModelContext, now: Date) {
        let exerciseCount = (try? context.fetchCount(FetchDescriptor<ExerciseEntry>())) ?? 0
        let startDate = demoTrendsEnabled
            ? demoTrendExerciseStart(referenceDate: now, calendar: .current)
            : now.addingTimeInterval(-7_200)
        guard exerciseCount == 0,
              let entry = ExerciseEntry.estimated(
                startDate: startDate,
                durationMinutes: 60,
                intensity: .basketballGeneral,
                weightKg: 78.6
              ) else {
            return
        }
        context.insert(entry)
    }

    private static func seedProductsIfNeeded(context: ModelContext) {
        let productCount = (try? context.fetchCount(FetchDescriptor<FoodProduct>())) ?? 0
        guard productCount == 0 else { return }

        let product = FoodProduct(
            barcodeRaw: "096619365475",
            gtin14: BarcodeNormalizer.gtin14(from: "096619365475"),
            name: "Protein Bar",
            brand: "Kirkland Signature",
            nutritionBasis: .perServing,
            nutrition: NutritionValues(
                energyKcal: 190,
                proteinG: 21,
                carbohydratesG: 22,
                fatG: 7,
                fiberG: 10,
                sugarG: 2,
                sodiumMg: 220
            ),
            servingSizeText: "1 bar (60g)",
            gramsPerServing: 60,
            unitsPerServing: 1,
            servingsPerPackage: 20,
            source: .demo,
            verifiedByUser: true,
            isFavorite: true,
            preferredAmount: 1,
            preferredUnit: .servings,
            useCount: 6,
            lastUsedAt: .now
        )
        context.insert(product)
    }
}
