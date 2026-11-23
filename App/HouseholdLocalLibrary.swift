import Foundation
import SwiftData

@MainActor
struct HouseholdLocalLibrary {
  var context: ModelContext
  private var recipes: [UUID: Recipe]
  private var cookbooks: [UUID: Cookbook]
  private var plans: [UUID: MealPlan]

  init(context: ModelContext) throws {
    self.context = context
    recipes = Dictionary(try context.fetch(FetchDescriptor<Recipe>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    cookbooks = Dictionary(try context.fetch(FetchDescriptor<Cookbook>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    plans = Dictionary(try context.fetch(FetchDescriptor<MealPlan>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }

  func snapshot(ownedOnly: Bool = false) -> [HouseholdLibraryEntry] {
    let books: [HouseholdLibraryEntry] = cookbooks.values.compactMap { book in
      if ownedOnly && book.isSharedCopy { return nil }
      return .cookbook(.init(id: book.id, name: book.name, detail: book.detail, createdAt: book.createdAt))
    }
    let recipeRows: [HouseholdLibraryEntry] = recipes.values.compactMap { recipe in
      if ownedOnly && recipe.isSharedRecipeCopy { return nil }
      let bookIDs = recipe.cookbookIDs.filter { !ownedOnly || cookbooks[$0]?.isSharedCopy != true }
      if ownedOnly, !recipe.cookbookIDs.isEmpty, bookIDs.isEmpty { return nil }
      return .recipe(.init(content: SharedRecipeSnapshot(recipe), cookbookIDs: bookIDs.sorted { $0.uuidString < $1.uuidString }, lastCooked: recipe.lastCooked))
    }
    let planRows = plans.values.flatMap { plan -> [HouseholdLibraryEntry] in
      [.plan(.init(id: plan.id, title: plan.title, startDate: plan.startDate, createdAt: plan.createdAt,
                   slots: plan.slots, occasion: plan.occasion, constraints: plan.constraints, dailyCalorieTarget: plan.dailyCalorieTarget,
                   peopleEating: plan.peopleEating, plansLeftovers: plan.plansLeftovers, usesCalendar: plan.usesCalendar))]
      + plan.groceryItems.map { .grocery(.init(planID: plan.id, item: $0)) }
    }
    return books + recipeRows + planRows
  }

  mutating func apply(_ entries: [HouseholdLibraryEntry], deleting keys: Set<String>) {
    var groceries: [UUID: [UUID: GroceryListItem]] = [:]
    func loadGroceries(_ id: UUID) {
      guard let plan = plans[id], groceries[id] == nil else { return }
      groceries[id] = Dictionary(plan.groceryItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    for key in keys {
      let parts = key.split(separator: ".")
      guard parts.count >= 2, let id = UUID(uuidString: String(parts[1])) else { continue }
      switch parts[0] {
      case "recipe":
        if let recipe = recipes.removeValue(forKey: id) { context.delete(recipe) }
      case "book":
        if let book = cookbooks.removeValue(forKey: id) {
          for recipe in recipes.values where recipe.cookbookIDs.contains(id) { recipe.remove(from: id) }
          context.delete(book)
        }
      case "plan":
        if let plan = plans.removeValue(forKey: id) { context.delete(plan) }
      case "grocery":
        guard parts.count == 3, let item = UUID(uuidString: String(parts[2])) else { continue }
        loadGroceries(id)
        groceries[id]?[item] = nil
      default: break
      }
    }

    for entry in entries.sorted(by: { $0.order < $1.order }) where !keys.contains(entry.key) {
      switch entry {
      case .recipe(let value):
        let snapshot = value.content
        let recipe = recipes[snapshot.id] ?? Recipe(name: snapshot.name, summary: snapshot.summary, category: snapshot.category,
          servings: snapshot.servings, prepMinutes: snapshot.prepMinutes, cookMinutes: snapshot.cookMinutes, ingredients: [], steps: [])
        if recipes[snapshot.id] == nil {
          context.insert(recipe)
          recipe.id = snapshot.id
          recipes[snapshot.id] = recipe
        }
        recipe.name = snapshot.name
        recipe.summary = snapshot.summary
        recipe.userNotes = snapshot.userNotes
        recipe.category = snapshot.category
        recipe.servings = snapshot.servings
        recipe.caloriesPerServing = snapshot.caloriesPerServing
        recipe.prepMinutes = snapshot.prepMinutes
        recipe.cookMinutes = snapshot.cookMinutes
        recipe.difficulty = snapshot.difficulty
        recipe.sourceURL = snapshot.sourceURL
        recipe.sourceName = snapshot.sourceName
        recipe.ingredientsJSON = snapshot.ingredientsJSON
        recipe.stepsJSON = snapshot.stepsJSON
        recipe.goodForJSON = snapshot.goodForJSON
        recipe.rating = snapshot.rating
        recipe.isFavorite = snapshot.isFavorite
        recipe.createdAt = snapshot.createdAt
        recipe.photoData = snapshot.photoData
        recipe.cookbookIDs = value.cookbookIDs.filter { !keys.contains("book.\($0)") }
        recipe.lastCooked = value.lastCooked

      case .cookbook(let value):
        let cookbook = cookbooks[value.id] ?? Cookbook(name: value.name, detail: value.detail)
        if cookbooks[value.id] == nil {
          context.insert(cookbook)
          cookbook.id = value.id
          cookbooks[value.id] = cookbook
        }
        cookbook.name = value.name
        cookbook.detail = value.detail
        cookbook.createdAt = value.createdAt

      case .plan(let value):
        let plan = plans[value.id] ?? MealPlan(title: value.title, startDate: value.startDate, slots: [], occasion: value.occasion,
          constraints: value.constraints, dailyCalorieTarget: value.dailyCalorieTarget,
          peopleEating: value.peopleEating, plansLeftovers: value.plansLeftovers, usesCalendar: value.usesCalendar)
        if plans[value.id] == nil {
          context.insert(plan)
          plan.id = value.id
          plans[value.id] = plan
        }
        plan.title = value.title
        plan.startDate = value.startDate
        plan.createdAt = value.createdAt
        plan.slots = value.slots
        plan.occasion = value.occasion
        plan.constraints = value.constraints
        plan.dailyCalorieTarget = value.dailyCalorieTarget
        plan.peopleEating = value.peopleEating
        plan.plansLeftovers = value.plansLeftovers
        plan.usesCalendar = value.usesCalendar

      case .grocery(let value):
        loadGroceries(value.planID)
        groceries[value.planID]?[value.item.id] = value.item
      }
    }

    for (id, items) in groceries {
      plans[id]?.groceryItems = items.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }
}
