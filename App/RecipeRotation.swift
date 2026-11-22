import Foundation

enum RecipeRotation {
  static func score(_ recipe: Recipe, on date: Date) -> Int {
    let preference = recipe.rating * 3 + (recipe.isFavorite ? 5 : 0)
    guard let days = daysSinceCooking(recipe, on: date) else { return preference + 5 }

    if days < 7 {
      return preference - (7 - days) * 4
    }
    return preference + min(14, days / 3)
  }

  static func daysSinceCooking(_ recipe: Recipe, on date: Date) -> Int? {
    guard let lastCooked = recipe.lastCooked else { return nil }
    let calendar = Calendar.current
    return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCooked), to: calendar.startOfDay(for: date)).day ?? 0)
  }

  static func ranked(_ recipes: [Recipe], on date: Date) -> [Recipe] {
    recipes.map { ($0, score($0, on: date)) }
      .sorted { left, right in
        if left.1 != right.1 { return left.1 > right.1 }
        let leftDate = left.0.lastCooked ?? .distantPast
        let rightDate = right.0.lastCooked ?? .distantPast
        if leftDate != rightDate { return leftDate < rightDate }
        return left.0.createdAt > right.0.createdAt
      }
      .map(\.0)
  }
}
