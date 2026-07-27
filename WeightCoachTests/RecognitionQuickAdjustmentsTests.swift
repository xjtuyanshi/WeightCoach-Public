import XCTest
@testable import WeightCoach

final class RecognitionQuickAdjustmentsTests: XCTestCase {
    func testEveryOrderShareExposesExpectedFactorAndTitle() {
        let locale = Locale(identifier: "zh-Hans")
        XCTAssertEqual(RecognitionOrderShare.allCases.count, 4)
        XCTAssertEqual(RecognitionOrderShare.quarter.factor, 0.25)
        XCTAssertEqual(
            RecognitionOrderShare.quarter.localizedButtonTitle(locale: locale),
            "¼"
        )
        XCTAssertEqual(RecognitionOrderShare.half.factor, 0.5)
        XCTAssertEqual(
            RecognitionOrderShare.half.localizedButtonTitle(locale: locale),
            "½"
        )
        XCTAssertEqual(RecognitionOrderShare.threeQuarters.factor, 0.75)
        XCTAssertEqual(
            RecognitionOrderShare.threeQuarters.localizedButtonTitle(locale: locale),
            "¾"
        )
        XCTAssertEqual(RecognitionOrderShare.all.factor, 1)
        XCTAssertEqual(
            RecognitionOrderShare.all.localizedButtonTitle(locale: locale),
            "全部"
        )
        XCTAssertEqual(
            RecognitionOrderShare.quarter.localizedAccessibilityTitle(locale: locale),
            "四分之一"
        )
        XCTAssertEqual(
            RecognitionOrderShare.half.localizedAccessibilityTitle(locale: locale),
            "二分之一"
        )
        XCTAssertEqual(
            RecognitionOrderShare.threeQuarters.localizedAccessibilityTitle(locale: locale),
            "四分之三"
        )
        XCTAssertEqual(
            RecognitionOrderShare.all.localizedAccessibilityTitle(locale: locale),
            "全部"
        )
    }

    func testOrderShareScalesWholeOrderAndPreservesIDsAndUnknownNutrition() {
        let firstID = UUID()
        let secondID = UUID()
        let foods = [
            RecognizedFood(
                id: firstID,
                name: "羊肉串",
                portion: "2 串",
                calories: 400,
                protein: 30,
                carbs: nil,
                fat: 24,
                calorieLowerBound: 320,
                calorieUpperBound: 480,
                caffeineMg: nil,
                confidence: 0.8,
                note: "大小不确定",
                inputKind: .receiptOrMenu
            ),
            RecognizedFood(
                id: secondID,
                name: "锡纸花甲粉",
                portion: "1 份",
                calories: 600,
                protein: nil,
                carbs: 80,
                fat: nil,
                caffeineMg: 20,
                confidence: 0.72,
                inputKind: .receiptOrMenu
            ),
        ]

        let adjusted = RecognitionOrderShare.quarter.applying(
            to: foods,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(adjusted.map(\.id), [firstID, secondID])
        XCTAssertEqual(adjusted[0].calories, 100)
        XCTAssertEqual(adjusted[0].protein, 7.5)
        XCTAssertNil(adjusted[0].carbs)
        XCTAssertEqual(adjusted[0].fat, 6)
        XCTAssertEqual(adjusted[0].calorieLowerBound, 80)
        XCTAssertEqual(adjusted[0].calorieUpperBound, 120)
        XCTAssertNil(adjusted[0].caffeineMg)
        XCTAssertEqual(adjusted[1].calories, 150)
        XCTAssertNil(adjusted[1].protein)
        XCTAssertEqual(adjusted[1].carbs, 20)
        XCTAssertNil(adjusted[1].fat)
        XCTAssertEqual(adjusted[1].caffeineMg, 5)
        XCTAssertTrue(adjusted.allSatisfy(\.needsConfirmation))
        XCTAssertTrue(adjusted.allSatisfy { $0.portion.contains("整单 ¼") })
        XCTAssertTrue(adjusted.allSatisfy { $0.note?.contains("请核对") == true })
        XCTAssertEqual(adjusted.map(\.inputKind), [.receiptOrMenu, .receiptOrMenu])

        XCTAssertEqual(foods[0].calories, 400, "纯函数不得修改原识别结果")
        XCTAssertEqual(foods[1].calories, 600, "纯函数不得修改原识别结果")
    }

    func testEveryOrderShareScalesFromOriginalValues() {
        let original = [
            RecognizedFood(
                name: "鸡肉串",
                portion: "4 串",
                calories: 800,
                protein: 60,
                carbs: 20,
                fat: 40,
                calorieLowerBound: 700,
                calorieUpperBound: 900,
                caffeineMg: 100
            )
        ]

        for share in RecognitionOrderShare.allCases {
            let adjusted = share.applying(
                to: original,
                locale: Locale(identifier: "zh-Hans")
            )[0]
            XCTAssertEqual(adjusted.calories, 800 * share.factor, accuracy: 0.001)
            XCTAssertEqual(adjusted.protein, 60 * share.factor)
            XCTAssertEqual(adjusted.carbs, 20 * share.factor)
            XCTAssertEqual(adjusted.fat, 40 * share.factor)
            XCTAssertEqual(adjusted.calorieLowerBound, 700 * share.factor)
            XCTAssertEqual(adjusted.calorieUpperBound, 900 * share.factor)
            XCTAssertEqual(adjusted.caffeineMg, 100 * share.factor)
            XCTAssertTrue(adjusted.needsConfirmation)
            XCTAssertTrue(adjusted.note?.contains("估算") == true)
        }
    }

    func testOrderShareHandlesEmptyOrder() {
        XCTAssertTrue(
            RecognitionOrderShare.half.applying(
                to: [],
                locale: Locale(identifier: "zh-Hans")
            ).isEmpty
        )
    }

    func testPortionMultiplierScalesOnlyKnownNutritionAndMarksEstimate() {
        let recognized = RecognizedFood(
            name: "鸡胸肉",
            portion: "约 180 克",
            calories: 300,
            protein: 54,
            carbs: nil,
            fat: 8,
            calorieLowerBound: 260,
            calorieUpperBound: 340,
            caffeineMg: 120,
            confidence: 0.9
        )

        let adjusted = RecognitionPortionMultiplier.half.applying(
            to: recognized,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(adjusted.calories, 150)
        XCTAssertEqual(adjusted.protein, 27)
        XCTAssertNil(adjusted.carbs, "未知营养素不得被快捷修正编造")
        XCTAssertEqual(adjusted.fat, 4)
        XCTAssertEqual(adjusted.calorieLowerBound, 130)
        XCTAssertEqual(adjusted.calorieUpperBound, 170)
        XCTAssertEqual(adjusted.caffeineMg, 60)
        XCTAssertTrue(adjusted.needsConfirmation)
        XCTAssertTrue(adjusted.portion.contains("½ 份"))
        XCTAssertTrue(adjusted.note?.contains("估算") == true)
    }

    func testOriginalMultiplierRestoresOriginalNutritionWithoutRounding() {
        let recognized = RecognizedFood(
            name: "糙米饭",
            portion: "约 1 碗",
            calories: 220,
            protein: 5,
            carbs: 46,
            fat: 2
        )

        let adjusted = RecognitionPortionMultiplier.original.applying(
            to: recognized,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(adjusted.calories, 220)
        XCTAssertEqual(adjusted.protein, 5)
        XCTAssertEqual(adjusted.carbs, 46)
        XCTAssertEqual(adjusted.fat, 2)
        XCTAssertTrue(adjusted.note?.contains("可撤销") == true)
    }

    func testOilQuickAdditionIsExplicitEstimate() {
        let oil = RecognitionQuickAddition.teaspoonOfCookingOil.makeFood(
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(oil.name, "烹调油（估算）")
        XCTAssertEqual(oil.calories, 40)
        XCTAssertEqual(oil.fat, 4.5)
        XCTAssertTrue(oil.needsConfirmation)
        XCTAssertTrue(oil.note?.contains("可撤销") == true)
    }

    func testSauceQuickAdditionDoesNotInventNutrition() {
        let sauce = RecognitionQuickAddition.sauceNeedsConfirmation.makeFood(
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(sauce.name, "酱汁（待确认）")
        XCTAssertEqual(sauce.calories, 0)
        XCTAssertNil(sauce.protein)
        XCTAssertNil(sauce.carbs)
        XCTAssertNil(sauce.fat)
        XCTAssertTrue(sauce.needsConfirmation)
        XCTAssertTrue(sauce.note?.contains("未估算") == true)
    }

    func testAppGeneratedAdjustmentsLocalizeWithoutChangingAIText() {
        let original = RecognizedFood(
            name: "原始 AI 名称",
            portion: "AI portion",
            calories: 200,
            note: "AI note"
        )

        let english = RecognitionPortionMultiplier.half.applying(
            to: original,
            locale: Locale(identifier: "en")
        )
        let traditional = RecognitionOrderShare.all.applying(
            to: [original],
            locale: Locale(identifier: "zh-Hant")
        )[0]

        XCTAssertEqual(english.name, "原始 AI 名称")
        XCTAssertTrue(english.portion.contains("½ serving"))
        XCTAssertTrue(english.note?.hasPrefix("AI note") == true)
        XCTAssertTrue(english.note?.contains("Quick adjustment") == true)
        XCTAssertEqual(traditional.name, "原始 AI 名称")
        XCTAssertTrue(traditional.portion.contains("全部"))
        XCTAssertTrue(traditional.note?.hasPrefix("AI note") == true)
        XCTAssertTrue(traditional.note?.contains("整張訂單食用比例") == true)
    }
}
