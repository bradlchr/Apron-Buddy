import Foundation

enum HouseholdLibraryEntry: Codable {
  case recipe(RecipeRecord)
  case cookbook(CookbookRecord)
  case plan(PlanRecord)
  case grocery(GroceryRecord)

  struct RecipeRecord: Codable {
    var content: SharedRecipeSnapshot
    var cookbookIDs: [UUID]
    var lastCooked: Date?
  }

  struct CookbookRecord: Codable {
    var id: UUID
    var name: String
    var detail: String
    var createdAt: Date
  }

  struct PlanRecord: Codable {
    var id: UUID
    var title: String
    var startDate: Date
    var createdAt: Date
    var slots: [MealPlanSlot]
    var occasion: String
    var constraints: String
    var dailyCalorieTarget: Int
    var peopleEating: Int
    var plansLeftovers: Bool
    var usesCalendar: Bool
  }

  struct GroceryRecord: Codable {
    var planID: UUID
    var item: GroceryListItem
  }

  var key: String {
    switch self {
    case .recipe(let value): "recipe.\(value.content.id)"
    case .cookbook(let value): "book.\(value.id)"
    case .plan(let value): "plan.\(value.id)"
    case .grocery(let value): "grocery.\(value.planID).\(value.item.id)"
    }
  }

  var recordType: String {
    switch self {
    case .recipe, .cookbook: "MiseHouseholdCatalogItem"
    case .plan: "MiseHouseholdPlan"
    case .grocery: "MiseHouseholdGrocery"
    }
  }

  var order: Int {
    switch self {
    case .cookbook: 0
    case .recipe: 1
    case .plan: 2
    case .grocery: 3
    }
  }

  var photo: Data? {
    if case .recipe(let row) = self { return row.content.photoData }
    return nil
  }

  func replacingPhoto(_ photo: Data?) -> Self {
    guard case .recipe(var row) = self else { return self }
    row.content.photoData = photo
    return .recipe(row)
  }
}
