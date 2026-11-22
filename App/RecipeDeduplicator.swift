import Foundation
import SwiftData

@MainActor
enum RecipeDeduplicator {
  private struct IngredientIdentity: Hashable {
    var amount: Double
    var unit: String
    var name: String
    var note: String
  }

  private struct StepIdentity: Hashable {
    var title: String
    var detail: String
    var timerMinutes: Int
  }

  private struct RecipeIdentity: Hashable {
    var name: String
    var category: String
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var sourceURL: String
    var ingredients: [IngredientIdentity]
    var steps: [StepIdentity]
  }

  static func changeKey(for recipes: [Recipe]) -> String {
    recipes.map { recipe in
      let identity = identity(for: recipe)
      return [
        recipe.id.uuidString,
        identity.name,
        identity.category,
        String(identity.servings),
        String(identity.prepMinutes),
        String(identity.cookMinutes),
        identity.sourceURL,
        identity.ingredients.map { "\($0.amount)|\($0.unit)|\($0.name)|\($0.note)" }.joined(separator: ";"),
        identity.steps.map { "\($0.title)|\($0.detail)|\($0.timerMinutes)" }.joined(separator: ";"),
        recipe.userNotes,
        recipe.summary,
        String(recipe.rating),
        String(recipe.isFavorite)
      ].joined(separator: "|")
    }
    .sorted()
    .joined(separator: "\n")
  }

  @discardableResult
  static func removeExactDuplicates(in context: ModelContext) -> Bool {
    let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
    var groups: [RecipeIdentity: [Recipe]] = [:]
    for recipe in recipes {
      groups[identity(for: recipe), default: []].append(recipe)
    }

    var replacements: [UUID: UUID] = [:]
    var ambiguousIDs: Set<UUID> = []
    var didChange = false

    for group in groups.values where group.count > 1 {
      let ordered = group.sorted(by: preferredOrder)
      guard let keeper = ordered.first else { continue }
      merge(ordered, into: keeper)

      for duplicate in ordered.dropFirst() {
        if let existing = replacements[duplicate.id], existing != keeper.id {
          ambiguousIDs.insert(duplicate.id)
        } else {
          replacements[duplicate.id] = keeper.id
        }
        context.delete(duplicate)
        didChange = true
      }
    }

    for id in ambiguousIDs {
      replacements.removeValue(forKey: id)
    }
    if !replacements.isEmpty {
      let plans = (try? context.fetch(FetchDescriptor<MealPlan>())) ?? []
      for plan in plans {
        var slots = plan.slots
        var changedSlots = false
        for index in slots.indices {
          guard let recipeID = slots[index].recipeID,
                let replacement = replacements[recipeID],
                replacement != recipeID else { continue }
          slots[index].recipeID = replacement
          changedSlots = true
        }
        if changedSlots {
          plan.slots = slots
          didChange = true
        }
      }
    }

    if didChange {
      try? context.save()
    }
    return didChange
  }

  private static func identity(for recipe: Recipe) -> RecipeIdentity {
    RecipeIdentity(
      name: normalized(recipe.name),
      category: normalized(recipe.category),
      servings: recipe.servings,
      prepMinutes: recipe.prepMinutes,
      cookMinutes: recipe.cookMinutes,
      sourceURL: normalized(recipe.sourceURL),
      ingredients: recipe.ingredients.map {
        IngredientIdentity(
          amount: $0.amount,
          unit: normalized($0.unit),
          name: normalized($0.name),
          note: normalized($0.note)
        )
      },
      steps: recipe.steps.map {
        StepIdentity(
          title: normalized($0.title),
          detail: normalized($0.detail),
          timerMinutes: $0.timerMinutes
        )
      }
    )
  }

  private static func preferredOrder(_ left: Recipe, _ right: Recipe) -> Bool {
    if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
    return left.id.uuidString < right.id.uuidString
  }

  private static func merge(_ recipes: [Recipe], into keeper: Recipe) {
    let notes = recipes
      .map { $0.userNotes.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .reduce(into: [String]()) { result, note in
        if !result.contains(note) { result.append(note) }
      }
    if !notes.isEmpty { keeper.userNotes = notes.joined(separator: "\n\n") }

    if keeper.summary.isEmpty, let summary = recipes.first(where: { !$0.summary.isEmpty })?.summary {
      keeper.summary = summary
    }
    if keeper.sourceName.isEmpty, let sourceName = recipes.first(where: { !$0.sourceName.isEmpty })?.sourceName {
      keeper.sourceName = sourceName
    }
    if keeper.photoData == nil {
      keeper.photoData = recipes.compactMap(\.photoData).first
    }

    keeper.rating = recipes.map(\.rating).max() ?? keeper.rating
    keeper.lastCooked = recipes.compactMap(\.lastCooked).max()
    keeper.caloriesPerServing = recipes.map(\.caloriesPerServing).max() ?? keeper.caloriesPerServing
    keeper.isFavorite = recipes.contains(where: \.isFavorite)
    let goodForValues = Set(recipes.flatMap { $0.goodFor.map(\.rawValue) })
    keeper.goodFor = RecipeGoodFor.allCases.filter { goodForValues.contains($0.rawValue) }
    keeper.cookbookIDs = Array(Set(recipes.flatMap(\.cookbookIDs))).sorted { $0.uuidString < $1.uuidString }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
  }
}
