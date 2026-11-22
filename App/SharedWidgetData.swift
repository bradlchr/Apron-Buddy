import Foundation

struct SharedRecipeSnapshot: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var summary: String
  var userNotes: String
  var category: String
  var servings: Int
  var caloriesPerServing: Int
  var prepMinutes: Int
  var cookMinutes: Int
  var difficulty: String
  var sourceURL: String
  var sourceName: String
  var ingredientsJSON: String
  var stepsJSON: String
  var goodForJSON: String
  var rating: Int
  var isFavorite: Bool
  var createdAt: Date
  var photoData: Data?
}

struct SharedCookbookSummary: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var recipeNames: [String]
}

struct SharedMealPlanEntry: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var date: Date
  var meal: String
  var recipeID: UUID?
  var recipeName: String
  var isSkipped: Bool
  var isLeftovers: Bool
  var servings: Int
}

struct SharedGroceryItem: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var amount: Double
  var unit: String
  var category: String
  var isChecked: Bool

  var displayText: String {
    guard amount > 0 else { return name }
    let quantity = amount.formatted(.number.precision(.fractionLength(0...2)))
    return "\(quantity)\(unit.isEmpty ? "" : " \(unit)") \(name)"
  }
}

struct SharedMealPlanSummary: Codable, Hashable, Identifiable, Sendable {
  var id: UUID
  var title: String
  var startDate: Date
  var entries: [SharedMealPlanEntry]
  var groceries: [SharedGroceryItem]
}

struct SharedKitchenSnapshot: Codable, Sendable {
  var updatedAt: Date
  var recipes: [SharedRecipeSnapshot]
  var cookbooks: [SharedCookbookSummary]
  var mealPlan: SharedMealPlanSummary?

  static var empty: Self {
    Self(updatedAt: .now, recipes: [], cookbooks: [], mealPlan: nil)
  }
}

enum SharedKitchenSnapshotStore {
  static let appGroup = "group.app.bitrig.christopherbradley.newproject.shared"
  private static let fileName = "ApronBuddyKitchenSnapshot.json"

  static func load() -> SharedKitchenSnapshot {
    guard let url = snapshotURL,
          let data = try? Data(contentsOf: url),
          let snapshot = try? JSONDecoder().decode(SharedKitchenSnapshot.self, from: data) else {
      return .empty
    }
    return snapshot
  }

  static func save(_ snapshot: SharedKitchenSnapshot) throws {
    guard let url = snapshotURL else { throw SnapshotError.appGroupUnavailable }
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: url, options: .atomic)
  }

  private static var snapshotURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appending(path: fileName)
  }

  enum SnapshotError: LocalizedError {
    case appGroupUnavailable
    var errorDescription: String? { "Apron Buddy couldn't access its shared widget data." }
  }
}
