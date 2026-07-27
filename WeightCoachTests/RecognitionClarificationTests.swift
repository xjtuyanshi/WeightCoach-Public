import XCTest
@testable import WeightCoach

final class RecognitionClarificationTests: XCTestCase {
    func testOilOrSauceQuestionWinsOverAnotherLowerConfidenceFood() {
        let chicken = RecognizedFood(
            name: "鸡胸肉",
            portion: "约 180 克",
            calories: 300,
            confidence: 0.88,
            needsConfirmation: true,
            note: "请确认烹调油和实际重量"
        )
        let rice = RecognizedFood(
            name: "米饭",
            portion: "约 1 碗",
            calories: 220,
            confidence: 0.45,
            needsConfirmation: true
        )

        let question = RecognitionClarificationSelector.mostImportant(for: [rice, chicken])

        XCTAssertEqual(question?.foodID, chicken.id)
        XCTAssertEqual(question?.kind, .oilOrSauce)
        XCTAssertTrue(
            question?.prompt(locale: Locale(identifier: "zh-Hans"))
                .contains("烹调油") == true
        )
    }

    func testOtherwiseSelectsLowestConfidencePortionQuestion() {
        let rice = RecognizedFood(
            name: "米饭",
            portion: "约 1 碗",
            calories: 220,
            confidence: 0.72,
            needsConfirmation: true
        )
        let broccoli = RecognizedFood(
            name: "西兰花",
            portion: "约 120 克",
            calories: 42,
            confidence: 0.53,
            needsConfirmation: true
        )

        let question = RecognitionClarificationSelector.mostImportant(for: [rice, broccoli])

        XCTAssertEqual(question?.foodID, broccoli.id)
        XCTAssertEqual(question?.kind, .portion)
        XCTAssertTrue(
            question?.prompt(locale: Locale(identifier: "zh-Hans"))
                .contains("份量") == true
        )
    }

    func testHighConfidenceFoodsDoNotAddAnUnnecessaryQuestion() {
        let food = RecognizedFood(
            name: "苹果",
            portion: "1 个",
            calories: 95,
            confidence: 0.92
        )

        XCTAssertNil(RecognitionClarificationSelector.mostImportant(for: [food]))
    }

    func testConfidenceThresholdIsStrictlyBelowPointSix() {
        let belowThreshold = RecognizedFood(
            name: "米饭",
            portion: "约 1 碗",
            calories: 220,
            confidence: 0.59
        )
        let atThreshold = RecognizedFood(
            name: "苹果",
            portion: "1 个",
            calories: 95,
            confidence: 0.60
        )

        XCTAssertEqual(
            RecognitionClarificationSelector.mostImportant(for: [belowThreshold])?.foodID,
            belowThreshold.id
        )
        XCTAssertNil(RecognitionClarificationSelector.mostImportant(for: [atThreshold]))
    }

    func testNeedsConfirmationStillAsksWhenConfidenceIsMissing() {
        let food = RecognizedFood(
            name: "炖牛肉",
            portion: "约 1 碗",
            calories: 480,
            needsConfirmation: true
        )

        let question = RecognitionClarificationSelector.mostImportant(for: [food])

        XCTAssertEqual(question?.foodID, food.id)
        XCTAssertEqual(question?.kind, .portion)
    }

    func testLowestConfidenceOilOrSauceCandidateWins() {
        let chicken = RecognizedFood(
            name: "鸡胸肉",
            portion: "约 180 克",
            calories: 300,
            confidence: 0.75,
            needsConfirmation: true,
            note: "请确认烹调油"
        )
        let salad = RecognizedFood(
            name: "沙拉",
            portion: "约 1 盘",
            calories: 180,
            confidence: 0.55,
            needsConfirmation: true,
            note: "酱汁用量不确定"
        )

        let question = RecognitionClarificationSelector.mostImportant(for: [chicken, salad])

        XCTAssertEqual(question?.foodID, salad.id)
        XCTAssertEqual(question?.kind, .oilOrSauce)
    }

    func testFoodNameContainingOilCharacterIsNotTreatedAsCookingOil() {
        let food = RecognizedFood(
            name: "油麦菜",
            portion: "约 1 盘",
            calories: 60,
            confidence: 0.55,
            needsConfirmation: true
        )

        XCTAssertEqual(
            RecognitionClarificationSelector.mostImportant(for: [food])?.kind,
            .portion
        )
    }

    func testSessionFreezesOriginalQuestionAndDoesNotAskAgainAfterDismissal() {
        let chicken = RecognizedFood(
            name: "鸡胸肉",
            portion: "约 180 克",
            calories: 300,
            confidence: 0.7,
            needsConfirmation: true,
            note: "请确认烹调油"
        )
        let addedOil = RecognitionQuickAddition.teaspoonOfCookingOil.makeFood()
        var session = RecognitionClarificationSession()

        session.begin(with: [chicken])
        XCTAssertEqual(session.pending?.foodID, chicken.id)

        // 若从修改后的 foods 重算，这里仍会产生问题；session 必须冻结原问题。
        let editedFoods = [chicken, addedOil]
        XCTAssertNotNil(RecognitionClarificationSelector.mostImportant(for: editedFoods))
        XCTAssertEqual(session.pending?.foodID, chicken.id)

        session.dismiss(foodID: chicken.id)
        XCTAssertNil(session.pending)
    }

    func testSessionIgnoresDismissalForAnUnrelatedFood() {
        let food = RecognizedFood(
            name: "米饭",
            portion: "约 1 碗",
            calories: 220,
            confidence: 0.4
        )
        var session = RecognitionClarificationSession()
        session.begin(with: [food])

        session.dismiss(foodID: UUID())

        XCTAssertEqual(session.pending?.foodID, food.id)
    }

    func testPromptLocalizesWhileKeepingAINameVerbatim() throws {
        let food = RecognizedFood(
            name: "House Special 原名",
            portion: "1 plate",
            calories: 420,
            confidence: 0.4
        )
        let clarification = try XCTUnwrap(
            RecognitionClarificationSelector.mostImportant(for: [food])
        )

        XCTAssertEqual(
            clarification.prompt(locale: Locale(identifier: "en")),
            "House Special 原名 — which portion is closest?"
        )
        XCTAssertEqual(
            clarification.prompt(locale: Locale(identifier: "zh-Hant")),
            "House Special 原名 的份量更接近哪一個？"
        )
    }

    func testTraditionalOilWordingStillSelectsOilClarification() {
        let food = RecognizedFood(
            name: "雞胸肉",
            portion: "約 180 克",
            calories: 300,
            confidence: 0.7,
            needsConfirmation: true,
            note: "請確認烹調油與醬汁"
        )

        XCTAssertEqual(
            RecognitionClarificationSelector.mostImportant(for: [food])?.kind,
            .oilOrSauce
        )
    }
}
