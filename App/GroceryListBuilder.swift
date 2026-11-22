import Foundation

enum GroceryListBuilder {
  private struct IngredientKey: Hashable {
    var name: String
    var unit: String
  }

  private static let categoryOrder = ["Produce", "Meat & seafood", "Dairy & eggs", "Bakery", "Pantry", "Other"]

  static func build(slots: [MealPlanSlot], recipes: [Recipe]) -> [GroceryListItem] {
    let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    var grouped: [IngredientKey: GroceryListItem] = [:]

    for slot in slots where !slot.isSkipped && !slot.isLeftovers {
      guard let recipeID = slot.recipeID, let recipe = recipesByID[recipeID] else { continue }
      let scale = Double(max(1, slot.servings)) / Double(max(1, recipe.servings))

      for ingredient in recipe.ingredients {
        let displayName = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { continue }
        let key = IngredientKey(name: displayName.localizedLowercase, unit: ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase)
        if var existing = grouped[key] {
          existing.amount += max(0, ingredient.amount) * scale
          grouped[key] = existing
        } else {
          grouped[key] = GroceryListItem(
            name: displayName,
            amount: max(0, ingredient.amount) * scale,
            unit: ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category(for: displayName)
          )
        }
      }
    }

    return grouped.values.sorted { left, right in
      let leftIndex = categoryOrder.firstIndex(of: left.category) ?? categoryOrder.count
      let rightIndex = categoryOrder.firstIndex(of: right.category) ?? categoryOrder.count
      if leftIndex != rightIndex { return leftIndex < rightIndex }
      return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
  }

  private static func category(for name: String) -> String {
    let value = name.localizedLowercase
    if containsAny(value, ["apple", "avocado", "banana", "basil", "berry", "berries", "broccoli", "carrot", "celery", "cilantro", "cucumber", "garlic", "herb", "lettuce", "lemon", "lime", "mushroom", "onion", "orange", "parsley", "pepper", "potato", "spinach", "tomato", "vegetable", "zucchini"]) {
      return "Produce"
    }
    if containsAny(value, ["beef", "chicken", "fish", "lamb", "pork", "salmon", "sausage", "shrimp", "turkey", "tuna", "cod", "tofu"]) {
      return "Meat & seafood"
    }
    if containsAny(value, ["butter", "cheese", "cream", "egg", "milk", "parmesan", "yogurt"]) {
      return "Dairy & eggs"
    }
    if containsAny(value, ["baguette", "bread", "bun", "roll", "tortilla", "pita"]) {
      return "Bakery"
    }
    if containsAny(value, ["flour", "oil", "rice", "pasta", "sugar", "salt", "pepper", "spice", "stock", "broth", "beans", "lentil", "vinegar", "sauce", "miso", "honey", "oat", "polenta", "canned"]) {
      return "Pantry"
    }
    return "Other"
  }

  private static func containsAny(_ value: String, _ options: [String]) -> Bool {
    options.contains { value.localizedStandardContains($0) }
  }
}
