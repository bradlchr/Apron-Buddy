import Foundation
import SwiftUI

enum DishCategory: String, CaseIterable {
  case pasta = "Pasta"
  case poultry = "Poultry"
  case seafood = "Seafood"
  case baking = "Baking"
  case dessert = "Dessert"
  case appetizer = "Appetizer"
  case breakfast = "Breakfast"
  case vegetarian = "Vegetarian"
  case soup = "Soup"
  case dinner = "Dinner"

  static func infer(name: String, category: String, ingredients: [RecipeIngredient]) -> Self {
    if let explicit = allCases.first(where: { $0 != .dinner && $0.rawValue.caseInsensitiveCompare(category) == .orderedSame }) {
      return explicit
    }
    let title = name.lowercased()
    let contents = ingredients.map { $0.name.lowercased() }.joined(separator: " ")
    let rules: [(Self, [String])] = [
      (.breakfast, ["pancake", "waffle", "omelet", "granola", "french toast"]),
      (.dessert, ["cake", "cookie", "brownie", "ice cream", "pudding"]),
      (.pasta, ["pasta", "rigatoni", "spaghetti", "lasagna", "noodle"]),
      (.soup, ["soup", "chowder", "bisque"]),
      (.appetizer, ["dip", "bruschetta", "croquette", "canapé"]),
      (.baking, ["bread", "biscuit", "scone", "focaccia"]),
      (.poultry, ["chicken", "turkey", "duck"]),
      (.seafood, ["salmon", "shrimp", "prawn", "tuna", "cod", "trout", "crab", "tilapia"]),
      (.vegetarian, ["mushroom", "lentil", "tofu", "salad", "vegetarian"])
    ]
    for (dish, words) in rules where words.contains(where: { title.localizedStandardContains($0) }) { return dish }
    for (dish, words) in rules where [.poultry, .seafood, .pasta].contains(dish) {
      if words.contains(where: { contents.localizedStandardContains($0) }) { return dish }
    }
    return .dinner
  }

  var colors: [Color] {
    switch self {
    case .pasta: [Color(red: 0.58, green: 0.22, blue: 0.16), Color(red: 0.86, green: 0.49, blue: 0.31)]
    case .poultry: [Color(red: 0.54, green: 0.34, blue: 0.16), Color(red: 0.80, green: 0.61, blue: 0.32)]
    case .seafood: [Color(red: 0.12, green: 0.35, blue: 0.44), Color(red: 0.40, green: 0.65, blue: 0.69)]
    case .baking, .breakfast: [Color(red: 0.68, green: 0.43, blue: 0.21), Color(red: 0.90, green: 0.70, blue: 0.44)]
    case .dessert: [Color(red: 0.47, green: 0.24, blue: 0.39), Color(red: 0.78, green: 0.50, blue: 0.58)]
    case .appetizer: [Color(red: 0.36, green: 0.34, blue: 0.52), Color(red: 0.61, green: 0.55, blue: 0.74)]
    case .vegetarian: [Color(red: 0.23, green: 0.37, blue: 0.24), Color(red: 0.61, green: 0.68, blue: 0.44)]
    case .soup, .dinner: [Color(red: 0.45, green: 0.37, blue: 0.25), Color(red: 0.74, green: 0.55, blue: 0.39)]
    }
  }
}
