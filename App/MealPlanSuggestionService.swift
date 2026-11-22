import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct MealPlanDraftSlot: Identifiable {
  var id: UUID = UUID()
  var date: Date
  var meal: PlannedMeal
  var recipeID: UUID?
  var suggestedRecipeID: UUID?
  var servings: Int
  var note: String = ""
  var isSkipped = false
  var isLeftovers = false

  var savedSlot: MealPlanSlot {
    MealPlanSlot(id: id, date: date, meal: meal, recipeID: recipeID, servings: servings, note: note, isSkipped: isSkipped, isLeftovers: isLeftovers)
  }
}

enum MealPlanSuggestionService {
  static var isAIAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      if case .available = SystemLanguageModel.default.availability { return true }
    }
    #endif
    return false
  }

  static func suggest(
    slots: [MealPlanDraftSlot],
    recipes: [Recipe],
    occasion: String,
    constraints: String,
    dailyCalorieTarget: Int,
    mealsPerDay: Int,
    peopleEating: Int,
    plansLeftovers: Bool,
    useAI: Bool
  ) async -> (slots: [MealPlanDraftSlot], usedAI: Bool) {
    var proposed = slots
    var usedAI = false

    #if canImport(FoundationModels)
    if useAI, isAIAvailable, #available(iOS 26.0, macOS 26.0, *) {
      if let selections = await selectWithAI(
        slots: proposed,
        recipes: recipes,
        occasion: occasion,
        constraints: constraints,
        dailyCalorieTarget: dailyCalorieTarget,
        mealsPerDay: mealsPerDay
      ) {
        let slotIndexes = Dictionary(uniqueKeysWithValues: proposed.enumerated().map { ($0.element.id.uuidString, $0.offset) })
        let recipeIDs = Set(recipes.map { $0.id.uuidString })
        var usedRecipes: Set<String> = []
        for selection in selections {
          guard recipeIDs.contains(selection.recipeID),
                !usedRecipes.contains(selection.recipeID),
                let index = slotIndexes[selection.slotID],
                !proposed[index].isSkipped,
                let recipe = recipes.first(where: { $0.id.uuidString == selection.recipeID }),
                isPlausible(recipe, for: proposed[index].meal) else { continue }
          proposed[index].recipeID = UUID(uuidString: selection.recipeID)
          proposed[index].suggestedRecipeID = proposed[index].recipeID
          usedRecipes.insert(selection.recipeID)
        }
        usedAI = true
      }
    }
    #endif

    fillMissingSlots(
      &proposed,
      recipes: recipes,
      constraints: constraints,
      occasion: occasion,
      dailyCalorieTarget: dailyCalorieTarget,
      mealsPerDay: mealsPerDay,
      allowRecipeReuse: false
    )
    for index in proposed.indices where proposed[index].suggestedRecipeID == nil {
      proposed[index].suggestedRecipeID = proposed[index].recipeID
    }
    updateForLeftovers(&proposed, peopleEating: peopleEating, plansLeftovers: plansLeftovers)
    if plansLeftovers {
      fillMissingSlots(
        &proposed,
        recipes: recipes,
        constraints: constraints,
        occasion: occasion,
        dailyCalorieTarget: dailyCalorieTarget,
        mealsPerDay: mealsPerDay,
        allowRecipeReuse: true
      )
      updateForLeftovers(&proposed, peopleEating: peopleEating, plansLeftovers: plansLeftovers)
    }
    return (proposed, usedAI)
  }

  static func updateForLeftovers(_ slots: inout [MealPlanDraftSlot], peopleEating: Int, plansLeftovers: Bool) {
    struct LeftoverBatch {
      var recipeID: UUID
      var meal: PlannedMeal
      var date: Date
      var servingsRemaining: Int
    }

    var batches: [LeftoverBatch] = []
    let people = max(1, peopleEating)

    for index in slots.indices {
      slots[index].recipeID = slots[index].suggestedRecipeID ?? slots[index].recipeID
      slots[index].isLeftovers = false
      slots[index].servings = people
      if slots[index].note.hasPrefix("Leftovers from") { slots[index].note = "" }
      guard !slots[index].isSkipped else { continue }
      let date = Calendar.current.startOfDay(for: slots[index].date)
      if plansLeftovers,
         let batchIndex = batches.firstIndex(where: { $0.meal == slots[index].meal && $0.date < date && $0.servingsRemaining >= people }) {
        let batch = batches[batchIndex]
        slots[index].recipeID = batch.recipeID
        slots[index].servings = people
        slots[index].isLeftovers = true
        slots[index].note = "Leftovers from the previous \(slots[index].meal.title.lowercased())"
        batches[batchIndex].servingsRemaining -= people
        continue
      }

      slots[index].isLeftovers = false
      slots[index].servings = people
      guard let recipeID = slots[index].recipeID else { continue }
      let hasLaterMealOfSameKind = slots[(index + 1)...].contains { $0.meal == slots[index].meal && Calendar.current.startOfDay(for: $0.date) > date && !$0.isSkipped }
      if plansLeftovers, hasLaterMealOfSameKind {
        slots[index].servings = people * 2
        batches.append(LeftoverBatch(recipeID: recipeID, meal: slots[index].meal, date: date, servingsRemaining: people))
      }
    }
  }

  private static func fillMissingSlots(
    _ slots: inout [MealPlanDraftSlot],
    recipes: [Recipe],
    constraints: String,
    occasion: String,
    dailyCalorieTarget: Int,
    mealsPerDay: Int,
    allowRecipeReuse: Bool
  ) {
    var usedRecipeIDs = Set(slots.filter { !$0.isLeftovers }.compactMap(\.recipeID))
    let needCalorieTarget = dailyCalorieTarget > 0
    let targetPerMeal = needCalorieTarget ? dailyCalorieTarget / max(1, mealsPerDay) : 0

    for index in slots.indices where !slots[index].isSkipped && !slots[index].isLeftovers && slots[index].recipeID == nil {
      let isBusyEvening = slots[index].meal == .dinner && slots[index].note == "Busy during dinner time"
      let candidates = recipes.filter { isPlausible($0, for: slots[index].meal) }
      let unused = candidates.filter { !usedRecipeIDs.contains($0.id) }
      let available = unused.isEmpty && allowRecipeReuse ? candidates : unused
      let recipe = available
        .max { left, right in
          score(left, for: slots[index], isBusyEvening: isBusyEvening, occasion: occasion, constraints: constraints, targetCalories: targetPerMeal)
            < score(right, for: slots[index], isBusyEvening: isBusyEvening, occasion: occasion, constraints: constraints, targetCalories: targetPerMeal)
        }
      guard let recipe else { continue }
      slots[index].recipeID = recipe.id
      slots[index].suggestedRecipeID = recipe.id
      usedRecipeIDs.insert(recipe.id)
    }
  }

  private static func isPlausible(_ recipe: Recipe, for meal: PlannedMeal) -> Bool {
    let category = recipe.category.localizedLowercase
    if category.contains("dessert") || category.contains("snack") { return false }
    if meal == .breakfast {
      return category.contains("breakfast")
        || recipe.name.localizedCaseInsensitiveContains("oat")
        || recipe.name.localizedCaseInsensitiveContains("pancake")
        || recipe.name.localizedCaseInsensitiveContains("toast")
        || recipe.name.localizedCaseInsensitiveContains("egg")
    }
    return true
  }

  private static func score(
    _ recipe: Recipe,
    for slot: MealPlanDraftSlot,
    isBusyEvening: Bool,
    occasion: String,
    constraints: String,
    targetCalories: Int
  ) -> Int {
    let text = ([recipe.name, recipe.summary, recipe.category] + recipe.ingredients.map(\.name) + recipe.goodFor.map(\.title))
      .joined(separator: " ")
      .localizedLowercase
    var score = recipe.rating * 3 + (recipe.isFavorite ? 2 : 0)
    let tokens = (occasion + " " + constraints)
      .localizedLowercase
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map(String.init)
      .filter { $0.count > 2 }
    score += tokens.filter { text.localizedStandardContains($0) }.count * 4
    if slot.meal == .breakfast && recipe.category.localizedCaseInsensitiveContains("breakfast") { score += 8 }
    if constraints.localizedCaseInsensitiveContains("healthy") || constraints.localizedCaseInsensitiveContains("light") {
      if recipe.category.localizedCaseInsensitiveContains("vegetarian") || text.contains("salad") || text.contains("vegetable") {
        score += 5
      }
    }
    let totalMinutes = recipe.prepMinutes + recipe.cookMinutes
    if isBusyEvening { score -= max(0, totalMinutes - 30) }
    if targetCalories > 0, recipe.caloriesPerServing > 0 {
      score -= min(30, abs(recipe.caloriesPerServing - targetCalories) / 25)
    }
    return score
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private static func selectWithAI(
    slots: [MealPlanDraftSlot],
    recipes: [Recipe],
    occasion: String,
    constraints: String,
    dailyCalorieTarget: Int,
    mealsPerDay: Int
  ) async -> [MealPlanAISelection]? {
    let openSlots = Array(slots.filter { !$0.isSkipped }.prefix(24))
    let availableRecipes = Array(recipes.prefix(40))
    guard !openSlots.isEmpty, !availableRecipes.isEmpty else { return nil }
    let slotText = openSlots.map { slot in
      "slotID=\(slot.id.uuidString), date=\(slot.date.formatted(date: .abbreviated, time: .omitted)), meal=\(slot.meal.title), context=\(slot.note.isEmpty ? "open" : slot.note)"
    }.joined(separator: "\n")
    let recipeText = availableRecipes.map { recipe in
      "recipeID=\(recipe.id.uuidString), name=\(recipe.name), category=\(recipe.category), minutes=\(recipe.prepMinutes + recipe.cookMinutes), caloriesPerServing=\(recipe.caloriesPerServing), rating=\(recipe.rating), goodFor=\(recipe.goodFor.map(\.title).joined(separator: ", ")), ingredients=\(recipe.ingredients.prefix(10).map(\.name).joined(separator: ", "))"
    }.joined(separator: "\n")
    let prompt = """
      Choose saved recipes for the open meal slots. Select only recipe IDs from the supplied list, use each recipe at most once, and return no invented recipes. Prioritize the occasion and constraints. For a busy dinner choose a recipe that takes 30 minutes or less when possible. If calories are supplied, prefer a balanced distribution near the daily target, but do not claim precision when a recipe has zero calories. Leave a slot out if no suitable recipe is available.

      Occasion: \(occasion.isEmpty ? "none" : occasion)
      Dietary and other constraints: \(constraints.isEmpty ? "none" : constraints)
      Daily calorie target: \(dailyCalorieTarget > 0 ? "\(dailyCalorieTarget)" : "none")
      Meals per day: \(mealsPerDay)

      Slots:
      \(slotText)

      Saved recipes:
      \(recipeText)
      """
    do {
      let session = LanguageModelSession(instructions: "You are a careful meal planner. Treat calendar context and dietary preferences as constraints. Only select provided recipe identifiers.")
      let response = try await session.respond(to: prompt, generating: MealPlanAISelectionResponse.self)
      return response.content.selections
    } catch {
      return nil
    }
  }
  #endif
}

#if canImport(FoundationModels)
@Generable(description: "A list of meal slots paired with saved recipe IDs")
private struct MealPlanAISelectionResponse {
  var selections: [MealPlanAISelection]
}

@Generable(description: "One saved recipe selected for one meal slot")
private struct MealPlanAISelection {
  var slotID: String
  var recipeID: String
}
#endif
