import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotPublisher {
  static func changeKey(recipes: [Recipe], cookbooks: [Cookbook], plans: [MealPlan]) -> String {
    let recipePart = RecipeDeduplicator.changeKey(for: recipes)
    let recipeLinks = recipes.map {
      "\($0.id)|\($0.cookbookIDsJSON)|\($0.isSharedRecipeCopy)|\($0.difficulty)|\($0.sourceName)|\($0.caloriesPerServing)|\($0.goodForJSON)"
    }.sorted().joined(separator: "\n")
    let cookbookPart = cookbooks.map { "\($0.id)|\($0.name)|\($0.detail)|\($0.isSharedCopy)" }.sorted().joined(separator: "\n")
    let planPart = plans.map { "\($0.id)|\($0.title)|\($0.startDate)|\($0.slotsJSON)|\($0.groceryItemsJSON)" }.sorted().joined(separator: "\n")
    return [recipePart, recipeLinks, cookbookPart, planPart].joined(separator: "\n--\n")
  }

  static func publish(recipes: [Recipe], cookbooks: [Cookbook], plans: [MealPlan]) {
    let recipeSnapshots = recipes.map { recipe -> SharedRecipeSnapshot in
      var snapshot = SharedRecipeSnapshot(recipe)
      snapshot.photoData = nil
      return snapshot
    }

    let cookbookSummaries = cookbooks.map { cookbook in
      SharedCookbookSummary(
        id: cookbook.id,
        name: cookbook.name,
        recipeNames: recipes
          .filter { $0.cookbookIDs.contains(cookbook.id) }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
          .map(\.name)
      )
    }

    let today = Calendar.current.startOfDay(for: .now)
    let activePlan = plans.first { plan in
      plan.slots.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    let nextPlan = plans
      .filter { Calendar.current.startOfDay(for: $0.startDate) >= today }
      .min { $0.startDate < $1.startDate }
    let selectedPlan = activePlan ?? nextPlan ?? plans.max { $0.startDate < $1.startDate }
    let planSummary = selectedPlan.map { plan in
      let entries = plan.slots.sorted { $0.date < $1.date }.map { slot in
        SharedMealPlanEntry(
          id: slot.id,
          date: slot.date,
          meal: slot.meal.title,
          recipeID: slot.recipeID,
          recipeName: recipes.first { $0.id == slot.recipeID }?.name ?? "",
          isSkipped: slot.isSkipped,
          isLeftovers: slot.isLeftovers,
          servings: slot.servings
        )
      }
      let groceries = plan.groceryItems.map {
        SharedGroceryItem(id: $0.id, name: $0.name, amount: $0.amount, unit: $0.unit, category: $0.category, isChecked: $0.isChecked)
      }
      return SharedMealPlanSummary(id: plan.id, title: plan.title, startDate: plan.startDate, entries: entries, groceries: groceries)
    }

    do {
      try SharedKitchenSnapshotStore.save(
        SharedKitchenSnapshot(updatedAt: .now, recipes: recipeSnapshots, cookbooks: cookbookSummaries, mealPlan: planSummary)
      )
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      // Widgets can continue showing the last complete snapshot until storage is available again.
    }
  }
}
