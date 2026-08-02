import XCTest
@testable import WeightCoach

final class SentenceFoodDraftBuilderTests: XCTestCase {
    func testBuildUsesAppDateAndMealForEveryRecognizedFood() throws {
        let authoritativeDate = Date(timeIntervalSince1970: 1_701_234_567)
        let sausage = food(
            name: "烤肠",
            portion: "1 根",
            calories: 180,
            protein: 7,
            carbs: 9,
            fat: 13
        )
        let wings = food(
            name: "鸡翅",
            portion: "2 个",
            calories: 210,
            protein: 18,
            carbs: 3,
            fat: 14
        )

        let drafts = try SentenceFoodDraftBuilder.makeDrafts(
            from: [sausage, wings],
            confirmedFoodIDs: [sausage.id, wings.id],
            authoritativeDate: authoritativeDate,
            authoritativeMealType: .dinner
        )

        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.date == authoritativeDate })
        XCTAssertTrue(drafts.allSatisfy { $0.mealType == .dinner })
        XCTAssertTrue(drafts.allSatisfy { $0.source == .ai })
    }

    func testBuildTrimsTextAndPreservesReviewedNutritionAndRange() throws {
        let recognized = food(
            name: "  烤肠  ",
            portion: "  1 根  ",
            calories: 180,
            protein: 7,
            carbs: 9,
            fat: 13,
            lower: 150,
            upper: 220,
            caffeine: 0
        )

        let draft = try XCTUnwrap(
            SentenceFoodDraftBuilder.makeDrafts(
                from: [recognized],
                confirmedFoodIDs: [recognized.id],
                authoritativeDate: .distantPast,
                authoritativeMealType: .snack
            ).first
        )

        XCTAssertEqual(draft.name, "烤肠")
        XCTAssertEqual(draft.portionText, "1 根")
        XCTAssertEqual(draft.calories, 180)
        XCTAssertEqual(draft.protein, 7)
        XCTAssertEqual(draft.carbs, 9)
        XCTAssertEqual(draft.fat, 13)
        XCTAssertEqual(draft.caffeineMg, 0)
        XCTAssertEqual(draft.calorieLowerBound, 150)
        XCTAssertEqual(draft.calorieUpperBound, 220)
    }

    func testBuildDropsRangeAfterReviewedCaloriesLeaveOriginalBounds() throws {
        let recognized = food(
            name: "鸡翅",
            portion: "2 个",
            calories: 260,
            lower: 150,
            upper: 220
        )

        let draft = try XCTUnwrap(
            SentenceFoodDraftBuilder.makeDrafts(
                from: [recognized],
                confirmedFoodIDs: [recognized.id],
                authoritativeDate: .distantPast,
                authoritativeMealType: .dinner
            ).first
        )

        XCTAssertNil(draft.calorieLowerBound)
        XCTAssertNil(draft.calorieUpperBound)
    }

    func testBuildRequiresEveryFoodToBeExplicitlyConfirmed() {
        let first = food(name: "烤肠", portion: "1 根", calories: 180)
        let second = food(name: "鸡翅", portion: "2 个", calories: 210)

        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [first, second],
                confirmedFoodIDs: [first.id],
                authoritativeDate: .now,
                authoritativeMealType: .dinner
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .unconfirmedFood(index: 1)
            )
        }
    }

    func testBuildRejectsEmptyOrInvalidResults() {
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [],
                confirmedFoodIDs: [],
                authoritativeDate: .now,
                authoritativeMealType: .snack
            )
        ) { error in
            XCTAssertEqual(error as? SentenceFoodDraftValidationError, .noFoods)
        }

        let emptyName = food(name: "  ", portion: "1 份", calories: 100)
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [emptyName],
                confirmedFoodIDs: [emptyName.id],
                authoritativeDate: .now,
                authoritativeMealType: .lunch
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .emptyName(index: 0)
            )
        }

        let invalidCalories = food(
            name: "鸡翅",
            portion: "2 个",
            calories: .infinity
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [invalidCalories],
                confirmedFoodIDs: [invalidCalories.id],
                authoritativeDate: .now,
                authoritativeMealType: .lunch
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .invalidCalories(index: 0)
            )
        }
    }

    func testBuildRejectsDuplicateIDsAndInvalidNutrition() {
        let duplicateID = UUID()
        let first = food(
            id: duplicateID,
            name: "烤肠",
            portion: "1 根",
            calories: 180
        )
        let second = food(
            id: duplicateID,
            name: "鸡翅",
            portion: "2 个",
            calories: 210
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [first, second],
                confirmedFoodIDs: [duplicateID],
                authoritativeDate: .now,
                authoritativeMealType: .dinner
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .duplicateFoodIdentifier
            )
        }

        let invalidNutrition = food(
            name: "烤肠",
            portion: "1 根",
            calories: 180,
            protein: -1
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [invalidNutrition],
                confirmedFoodIDs: [invalidNutrition.id],
                authoritativeDate: .now,
                authoritativeMealType: .dinner
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .invalidNutrition(index: 0)
            )
        }
    }

    func testBuildRejectsFutureDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recognized = food(name: "烤肠", portion: "1 根", calories: 180)

        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [recognized],
                confirmedFoodIDs: [recognized.id],
                authoritativeDate: now.addingTimeInterval(1),
                authoritativeMealType: .dinner,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .futureDate
            )
        }
    }

    func testBuildAppliesManualSourceOnlyToManuallyAddedFoods() throws {
        let recognized = food(name: "烤肠", portion: "1 根", calories: 180)
        let manual = food(name: "鸡翅", portion: "2 个", calories: 210)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let drafts = try SentenceFoodDraftBuilder.makeDrafts(
            from: [recognized, manual],
            confirmedFoodIDs: [recognized.id, manual.id],
            authoritativeDate: now,
            authoritativeMealType: .dinner,
            manualFoodIDs: [manual.id],
            now: now
        )

        XCTAssertEqual(
            drafts.map { $0.source.rawValue },
            [FoodSource.ai.rawValue, FoodSource.manual.rawValue]
        )
    }

    func testBuildRejectsValuesBeyondBridgeSafetyLimits() {
        let tooManyCalories = food(
            name: "超大份",
            portion: "1 份",
            calories: SentenceFoodDraftBuilder.maximumCalories + 1
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [tooManyCalories],
                confirmedFoodIDs: [tooManyCalories.id],
                authoritativeDate: .distantPast,
                authoritativeMealType: .lunch
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .invalidCalories(index: 0)
            )
        }

        let tooMuchProtein = food(
            name: "超大份",
            portion: "1 份",
            calories: 100,
            protein: SentenceFoodDraftBuilder.maximumMacroGrams + 1
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [tooMuchProtein],
                confirmedFoodIDs: [tooMuchProtein.id],
                authoritativeDate: .distantPast,
                authoritativeMealType: .lunch
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .invalidNutrition(index: 0)
            )
        }
    }

    func testBuildRejectsOverlongNameAndPortion() {
        let longName = food(
            name: String(
                repeating: "a",
                count: SentenceFoodDraftBuilder.maximumNameLength + 1
            ),
            portion: "1 份",
            calories: 100
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [longName],
                confirmedFoodIDs: [longName.id],
                authoritativeDate: .distantPast,
                authoritativeMealType: .snack
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .nameTooLong(index: 0)
            )
        }

        let longPortion = food(
            name: "鸡翅",
            portion: String(
                repeating: "a",
                count: SentenceFoodDraftBuilder.maximumPortionLength + 1
            ),
            calories: 100
        )
        XCTAssertThrowsError(
            try SentenceFoodDraftBuilder.makeDrafts(
                from: [longPortion],
                confirmedFoodIDs: [longPortion.id],
                authoritativeDate: .distantPast,
                authoritativeMealType: .snack
            )
        ) { error in
            XCTAssertEqual(
                error as? SentenceFoodDraftValidationError,
                .portionTooLong(index: 0)
            )
        }
    }

    func testReviewMutationClearsStaleDerivedNutrition() {
        var recognized = RecognizedFood(
            name: "烤肠",
            portion: "1 根",
            calories: 180,
            protein: 7,
            carbs: 9,
            fat: 13,
            calorieLowerBound: 150,
            calorieUpperBound: 220,
            caffeineMg: 12,
            confidence: 0.8,
            needsConfirmation: false
        )

        SentenceFoodReviewMutation.invalidateDerivedEstimate(&recognized)

        XCTAssertNil(recognized.protein)
        XCTAssertNil(recognized.carbs)
        XCTAssertNil(recognized.fat)
        XCTAssertNil(recognized.caffeineMg)
        XCTAssertNil(recognized.calorieLowerBound)
        XCTAssertNil(recognized.calorieUpperBound)
        XCTAssertNil(recognized.confidence)
        XCTAssertTrue(recognized.needsConfirmation)
    }

    private func food(
        id: UUID = UUID(),
        name: String,
        portion: String,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        lower: Double? = nil,
        upper: Double? = nil,
        caffeine: Double? = nil
    ) -> RecognizedFood {
        RecognizedFood(
            id: id,
            name: name,
            portion: portion,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            calorieLowerBound: lower,
            calorieUpperBound: upper,
            caffeineMg: caffeine,
            needsConfirmation: true
        )
    }
}
