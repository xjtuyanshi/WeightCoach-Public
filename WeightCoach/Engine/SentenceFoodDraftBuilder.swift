import Foundation

enum SentenceFoodDraftValidationError: Error, Equatable {
    case noFoods
    case duplicateFoodIdentifier
    case unconfirmedFood(index: Int)
    case emptyName(index: Int)
    case nameTooLong(index: Int)
    case portionTooLong(index: Int)
    case invalidCalories(index: Int)
    case invalidNutrition(index: Int)
    case futureDate
}

/// Any user edit makes model-derived nutrition stale. The UI keeps the edited
/// headline value, clears derived values, and requires a fresh confirmation.
enum SentenceFoodReviewMutation {
    static func invalidateDerivedEstimate(_ food: inout RecognizedFood) {
        food.protein = nil
        food.carbs = nil
        food.fat = nil
        food.caffeineMg = nil
        food.calorieLowerBound = nil
        food.calorieUpperBound = nil
        food.confidence = nil
        food.needsConfirmation = true
    }
}

/// Converts user-reviewed sentence-recognition results into the app's existing
/// write model. The selected date and meal always come from the app; model
/// output is deliberately unable to override either value.
enum SentenceFoodDraftBuilder {
    static let maximumNameLength = 80
    static let maximumPortionLength = 120
    static let maximumCalories = 5_000.0
    static let maximumMacroGrams = 1_000.0
    static let maximumCaffeineMg = 2_000.0

    static func makeDrafts(
        from foods: [RecognizedFood],
        confirmedFoodIDs: Set<UUID>,
        authoritativeDate: Date,
        authoritativeMealType: MealType,
        manualFoodIDs: Set<UUID> = [],
        now: Date = .now
    ) throws -> [FoodEntryDraft] {
        guard !foods.isEmpty else {
            throw SentenceFoodDraftValidationError.noFoods
        }
        guard Set(foods.map(\.id)).count == foods.count else {
            throw SentenceFoodDraftValidationError.duplicateFoodIdentifier
        }
        guard authoritativeDate <= now else {
            throw SentenceFoodDraftValidationError.futureDate
        }

        return try foods.enumerated().map { index, food in
            guard confirmedFoodIDs.contains(food.id) else {
                throw SentenceFoodDraftValidationError.unconfirmedFood(index: index)
            }

            let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw SentenceFoodDraftValidationError.emptyName(index: index)
            }
            guard name.count <= maximumNameLength else {
                throw SentenceFoodDraftValidationError.nameTooLong(index: index)
            }
            guard food.calories.isFinite,
                  food.calories > 0,
                  food.calories <= maximumCalories else {
                throw SentenceFoodDraftValidationError.invalidCalories(index: index)
            }
            guard [food.protein, food.carbs, food.fat]
                .compactMap({ $0 })
                .allSatisfy({
                    $0.isFinite && $0 >= 0 && $0 <= maximumMacroGrams
                }),
                food.caffeineMg.map({
                    $0.isFinite && $0 >= 0 && $0 <= maximumCaffeineMg
                }) ?? true
            else {
                throw SentenceFoodDraftValidationError.invalidNutrition(index: index)
            }

            let portion = food.portion
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard portion.count <= maximumPortionLength else {
                throw SentenceFoodDraftValidationError.portionTooLong(index: index)
            }
            let retainsCalorieRange =
                food.calorieLowerBound.map {
                    $0.isFinite && $0 >= 1 && $0 <= food.calories
                } == true
                && food.calorieUpperBound.map {
                    $0.isFinite
                        && food.calories <= $0
                        && $0 <= maximumCalories
                } == true

            return FoodEntryDraft(
                name: name,
                calories: food.calories,
                protein: food.protein,
                carbs: food.carbs,
                fat: food.fat,
                portionText: portion.isEmpty ? nil : portion,
                mealType: authoritativeMealType,
                source: manualFoodIDs.contains(food.id) ? .manual : .ai,
                date: authoritativeDate,
                caffeineMg: food.caffeineMg,
                calorieLowerBound: retainsCalorieRange
                    ? food.calorieLowerBound
                    : nil,
                calorieUpperBound: retainsCalorieRange
                    ? food.calorieUpperBound
                    : nil
            )
        }
    }
}
