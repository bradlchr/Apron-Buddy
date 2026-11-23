import Foundation

enum IngredientNormalization {
  static func clean(_ ingredient: RecipeIngredient) -> RecipeIngredient {
    var ingredient = ingredient
    ingredient.name = tidy(ingredient.name)
    ingredient.unit = tidy(ingredient.unit)
    ingredient.section = ingredient.section.flatMap {
      let title = tidy($0)
      return title.isEmpty ? nil : title
    }
    let unitKey = key(ingredient.unit)
    let words = ingredient.name.split(separator: " ")
    if words.count >= 3, let first = words.first, let last = words.last,
       key(String(first)) == key(String(last)) {
      ingredient.name = words.dropFirst().joined(separator: " ")
    }
    if !unitKey.isEmpty, measurement(for: unitKey) == nil {
      let words = ingredient.name.split(separator: " ")
      if words.last.map({ key(String($0)) }) == unitKey {
        ingredient.unit = ""
        if words.count > 1, words.first.map({ key(String($0)) }) == unitKey {
          ingredient.name = words.dropFirst().joined(separator: " ")
        }
      }
    }
    return ingredient
  }

  static func tidy(_ name: String) -> String {
    var words: [Substring] = []
    for word in name.split(whereSeparator: \.isWhitespace) {
      if words.last?.caseInsensitiveCompare(word) != .orderedSame { words.append(word) }
    }
    return words.joined(separator: " ")
  }

  static func key(_ name: String) -> String {
    tidy(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
      .split(separator: " ")
      .map { word in
        switch word {
        case "eggs": "egg"
        case "tortillas": "tortilla"
        case "tomatoes": "tomato"
        case "potatoes": "potato"
        case "onions": "onion"
        case "carrots": "carrot"
        case "mushrooms": "mushroom"
        case "lemons": "lemon"
        case "limes": "lime"
        case "cloves": "clove"
        default: String(word)
        }
      }
      .joined(separator: " ")
  }

  struct Measurement {
    var family: String
    var factor: Double
  }

  static func measurement(for unit: String, ingredientName: String = "butter") -> Measurement? {
    let unit = unit.replacingOccurrences(of: ".", with: "")
    switch unit {
    case "tsp", "tsps", "teaspoon", "teaspoons": return .init(family: "usVolume", factor: 1)
    case "tbsp", "tbsps", "tablespoon", "tablespoons": return .init(family: "usVolume", factor: 3)
    case "cup", "cups": return .init(family: "usVolume", factor: 48)
    case "stick", "sticks": return ingredientName.contains("butter") ? .init(family: "usVolume", factor: 24) : nil
    case "ml", "milliliter", "milliliters": return .init(family: "metricVolume", factor: 1)
    case "l", "liter", "liters": return .init(family: "metricVolume", factor: 1_000)
    case "g", "gram", "grams": return .init(family: "metricMass", factor: 1)
    case "kg", "kilogram", "kilograms": return .init(family: "metricMass", factor: 1_000)
    case "oz", "ounce", "ounces": return .init(family: "usMass", factor: 1)
    case "lb", "lbs", "pound", "pounds": return .init(family: "usMass", factor: 16)
    default: return nil
    }
  }

  static func displayMeasurement(_ base: Double, family: String) -> (amount: Double, unit: String) {
    switch family {
    case "usVolume":
      if base >= 12 { return (base / 48, "cup") }
      if base >= 3 { return (base / 3, "tbsp") }
      return (base, "tsp")
    case "metricVolume": return base >= 1_000 ? (base / 1_000, "L") : (base, "mL")
    case "metricMass": return base >= 1_000 ? (base / 1_000, "kg") : (base, "g")
    case "usMass": return base >= 16 ? (base / 16, "lb") : (base, "oz")
    default: return (base, family)
    }
  }

  static func groceryName(for ingredient: RecipeIngredient) -> String {
    let clean = clean(ingredient)
    let name = clean.name.replacingOccurrences(of: #"\s*,\s*(chopped|diced|minced|sliced|melted|softened|divided)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    return tidy(name)
  }
}
