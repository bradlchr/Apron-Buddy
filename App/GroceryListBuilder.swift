import Foundation

enum GroceryListBuilder {
  private struct IngredientKey: Hashable {
    var name: String
    var unit: String
  }

  private static let categoryOrder = ["Produce", "Meat & seafood", "Dairy & eggs", "Bakery", "Pantry", "Other"]

  static func build(slots: [MealPlanSlot], recipes: [Recipe]) -> [GroceryListItem] {
    let recipesByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let items = slots.filter { !$0.isSkipped && !$0.isLeftovers }.flatMap { slot -> [GroceryListItem] in
      guard let recipeID = slot.recipeID, let recipe = recipesByID[recipeID] else { return [] }
      let scale = Double(max(1, slot.servings)) / Double(max(1, recipe.servings))
      return recipe.ingredients.map { ingredient in
        let quantity = ingredient.amount.isFinite ? max(0, ingredient.amount) : 0
        return GroceryListItem(name: ingredient.name, amount: quantity * scale, unit: ingredient.unit, category: "")
      }
    }
    return normalized(items)
  }

  static func normalized(_ items: [GroceryListItem]) -> [GroceryListItem] {
    var grouped: [IngredientKey: GroceryListItem] = [:]
    for item in items {
      let clean = IngredientNormalization.clean(.init(amount: item.amount, unit: item.unit, name: item.name))
      let displayName = IngredientNormalization.groceryName(for: clean)
      guard !displayName.isEmpty else { continue }
      let name = IngredientNormalization.key(displayName)
      let unit = IngredientNormalization.key(clean.unit)
      let measurement = IngredientNormalization.measurement(for: unit, ingredientName: name)
      let key = IngredientKey(name: name, unit: measurement?.family ?? unit)
      let amount = clean.amount.isFinite ? max(0, clean.amount) * (measurement?.factor ?? 1) : 0
      if var existing = grouped[key] {
        existing.amount += amount
        existing.isChecked = existing.isChecked && item.isChecked
        grouped[key] = existing
      } else {
        var entry = item
        entry.name = displayName
        entry.amount = amount
        entry.unit = key.unit
        entry.category = item.category.isEmpty ? category(for: displayName) : item.category
        grouped[key] = entry
      }
    }

    let butterKeys = ["salted butter", "unsalted butter"].map { IngredientKey(name: $0, unit: "usVolume") }
    if let salted = grouped[butterKeys[0]], let unsalted = grouped[butterKeys[1]] {
      let portions = [salted, unsalted].map { item in
        let volume = IngredientNormalization.displayMeasurement(item.amount, family: item.unit)
        let kind = item.name.localizedCaseInsensitiveContains("unsalted") ? "unsalted" : "salted"
        return "\(KitchenQuantity.format(volume.amount)) \(volume.unit) \(kind)"
      }
      grouped[butterKeys[0]] = nil
      grouped[butterKeys[1]] = nil
      grouped[IngredientKey(name: "butter with specified salt", unit: "usVolume")] = GroceryListItem(
        id: salted.id, name: "butter (\(portions.joined(separator: ", ")))", amount: salted.amount + unsalted.amount,
        unit: "usVolume", category: "Dairy & eggs", isChecked: salted.isChecked && unsalted.isChecked
      )
    }

    return grouped.values.map { item in
      var item = item
      let measurement = IngredientNormalization.displayMeasurement(item.amount, family: item.unit)
      item.amount = measurement.amount
      item.unit = measurement.unit
      return item
    }.sorted { left, right in
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
