import Foundation
import SwiftData

enum PlannedMeal: String, Codable, CaseIterable, Identifiable, Sendable {
  case breakfast
  case lunch
  case dinner

  var id: String { rawValue }

  var title: String {
    switch self {
    case .breakfast: "Breakfast"
    case .lunch: "Lunch"
    case .dinner: "Dinner"
    }
  }

  var symbol: String {
    switch self {
    case .breakfast: "sun.max"
    case .lunch: "sun.horizon"
    case .dinner: "moon.stars"
    }
  }
}

struct MealPlanSlot: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var date: Date
  var meal: PlannedMeal
  var recipeID: UUID?
  var servings: Int
  var note: String = ""
  var isSkipped: Bool = false
  var isLeftovers: Bool = false

  private enum CodingKeys: String, CodingKey {
    case id, date, meal, recipeID, servings, note, isSkipped, isLeftovers
  }

  init(
    id: UUID = UUID(),
    date: Date,
    meal: PlannedMeal,
    recipeID: UUID?,
    servings: Int,
    note: String = "",
    isSkipped: Bool = false,
    isLeftovers: Bool = false
  ) {
    self.id = id
    self.date = date
    self.meal = meal
    self.recipeID = recipeID
    self.servings = servings
    self.note = note
    self.isSkipped = isSkipped
    self.isLeftovers = isLeftovers
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    date = try values.decode(Date.self, forKey: .date)
    meal = try values.decode(PlannedMeal.self, forKey: .meal)
    recipeID = try values.decodeIfPresent(UUID.self, forKey: .recipeID)
    servings = try values.decodeIfPresent(Int.self, forKey: .servings) ?? 1
    note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
    isSkipped = try values.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
    isLeftovers = try values.decodeIfPresent(Bool.self, forKey: .isLeftovers) ?? false
  }
}

struct GroceryListItem: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var name: String
  var amount: Double
  var unit: String
  var category: String
  var isChecked: Bool = false

  var displayText: String {
    guard amount > 0 else { return name }
    let quantity = KitchenQuantity.format(amount)
    let unitText = unit.isEmpty ? "" : " \(KitchenQuantity.unitLabel(unit, amount: amount))"
    return "\(quantity)\(unitText) \(name)"
  }
}

@Model
final class MealPlan {
  var id: UUID = UUID()
  var title: String = ""
  var startDate: Date = Date()
  var createdAt: Date = Date()
  var slotsJSON: String = "[]"
  var groceryItemsJSON: String = "[]"
  var occasion: String = ""
  var constraints: String = ""
  var dailyCalorieTarget: Int = 0
  var peopleEating: Int = 4
  var plansLeftovers: Bool = false
  var usesCalendar: Bool = false
  var reminderListID: String = ""
  var reminderListName: String = ""

  init(
    title: String,
    startDate: Date,
    slots: [MealPlanSlot],
    occasion: String,
    constraints: String,
    dailyCalorieTarget: Int,
    peopleEating: Int,
    plansLeftovers: Bool,
    usesCalendar: Bool
  ) {
    self.id = UUID()
    self.title = title
    self.startDate = startDate
    self.createdAt = .now
    self.slotsJSON = Self.encode(slots)
    self.groceryItemsJSON = "[]"
    self.occasion = occasion
    self.constraints = constraints
    self.dailyCalorieTarget = max(0, dailyCalorieTarget)
    self.peopleEating = max(1, peopleEating)
    self.plansLeftovers = plansLeftovers
    self.usesCalendar = usesCalendar
  }

  var slots: [MealPlanSlot] {
    get { Self.decode(slotsJSON, as: [MealPlanSlot].self) ?? [] }
    set { slotsJSON = Self.encode(newValue) }
  }

  var groceryItems: [GroceryListItem] {
    get { Self.decode(groceryItemsJSON, as: [GroceryListItem].self) ?? [] }
    set { groceryItemsJSON = Self.encode(newValue) }
  }

  private static func encode<Value: Encodable>(_ value: Value) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
  }

  private static func decode<Value: Decodable>(_ value: String, as type: Value.Type) -> Value? {
    guard let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}
