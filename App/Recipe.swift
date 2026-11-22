import Foundation
import SwiftData

struct RecipeIngredient: Codable, Identifiable, Hashable, Sendable {
  var id: UUID = UUID()
  var amount: Double
  var unit: String
  var name: String
  var note: String = ""

  var displayAmount: String {
    if amount.rounded() == amount { return String(Int(amount)) }
    return amount.formatted(.number.precision(.fractionLength(0...2)))
  }
}

struct RecipeStep: Codable, Identifiable, Hashable, Sendable {
  var id: UUID = UUID()
  var title: String
  var detail: String
  var timerMinutes: Int = 0
}

enum RecipeGoodFor: String, Codable, CaseIterable, Identifiable, Sendable {
  case quickWeeknight
  case event
  case birthday
  case largeGroups
  case kids
  case mealPrep
  case potluck
  case holiday
  case dateNight

  var id: String { rawValue }

  var title: String {
    switch self {
    case .quickWeeknight: "Quick weeknight"
    case .event: "Event"
    case .birthday: "Birthday"
    case .largeGroups: "Large groups"
    case .kids: "Kids"
    case .mealPrep: "Meal prep"
    case .potluck: "Potluck"
    case .holiday: "Holiday"
    case .dateNight: "Date night"
    }
  }

  var symbol: String {
    switch self {
    case .quickWeeknight: "clock"
    case .event: "sparkles"
    case .birthday: "birthday.cake"
    case .largeGroups: "person.3"
    case .kids: "figure.and.child.holdinghands"
    case .mealPrep: "takeoutbag.and.cup.and.straw"
    case .potluck: "basket"
    case .holiday: "gift"
    case .dateNight: "heart"
    }
  }
}

@Model
final class Recipe {
  var id: UUID = UUID()
  var name: String = ""
  var summary: String = ""
  var userNotes: String = ""
  var category: String = "Dinner"
  var servings: Int = 4
  var caloriesPerServing: Int = 0
  var prepMinutes: Int = 15
  var cookMinutes: Int = 30
  var difficulty: String = "Easy"
  var sourceURL: String = ""
  var sourceName: String = ""
  var ingredientsJSON: String = "[]"
  var stepsJSON: String = "[]"
  var cookbookIDsJSON: String = "[]"
  var goodForJSON: String = "[]"
  var rating: Int = 0
  var isFavorite: Bool = false
  var isCloudSharedRecipe: Bool = false
  var isSharedRecipeCopy: Bool = false
  var canEditSharedRecipe: Bool = false
  var sharedRecipeZoneName: String = ""
  var sharedRecipeOwnerName: String = ""
  var createdAt: Date = Date()
  var lastCooked: Date? = nil
  @Attribute(.externalStorage) var photoData: Data? = nil

  init(
    name: String,
    summary: String,
    userNotes: String = "",
    category: String,
    servings: Int,
    caloriesPerServing: Int = 0,
    prepMinutes: Int,
    cookMinutes: Int,
    difficulty: String = "Easy",
    ingredients: [RecipeIngredient],
    steps: [RecipeStep],
    sourceURL: String = "",
    sourceName: String = "",
    isFavorite: Bool = false,
    photoData: Data? = nil,
    cookbookIDs: [UUID] = [],
    goodFor: [RecipeGoodFor] = [],
    rating: Int = 0
  ) {
    self.id = UUID()
    self.name = name
    self.summary = summary
    self.userNotes = userNotes
    self.category = category
    self.servings = max(1, servings)
    self.caloriesPerServing = max(0, caloriesPerServing)
    self.prepMinutes = max(0, prepMinutes)
    self.cookMinutes = max(0, cookMinutes)
    self.difficulty = difficulty
    self.ingredientsJSON = Self.encode(ingredients)
    self.stepsJSON = Self.encode(steps)
    self.sourceURL = sourceURL
    self.sourceName = sourceName
    self.isFavorite = isFavorite
    self.createdAt = Date()
    self.photoData = photoData
    self.cookbookIDsJSON = Self.encode(cookbookIDs)
    self.goodForJSON = Self.encode(goodFor)
    self.rating = min(5, max(0, rating))
  }

  var ingredients: [RecipeIngredient] {
    get { Self.decode(ingredientsJSON, as: [RecipeIngredient].self) ?? [] }
    set { ingredientsJSON = Self.encode(newValue) }
  }

  var steps: [RecipeStep] {
    get { Self.decode(stepsJSON, as: [RecipeStep].self) ?? [] }
    set { stepsJSON = Self.encode(newValue) }
  }

  var cookbookIDs: [UUID] {
    get { Self.decode(cookbookIDsJSON, as: [UUID].self) ?? [] }
    set { cookbookIDsJSON = Self.encode(newValue) }
  }

  var goodFor: [RecipeGoodFor] {
    get { Self.decode(goodForJSON, as: [RecipeGoodFor].self) ?? [] }
    set { goodForJSON = Self.encode(newValue) }
  }

  func saveLastCooked(_ date: Date?, in context: ModelContext) throws {
    let previous = lastCooked
    lastCooked = date
    do {
      try context.save()
    } catch {
      lastCooked = previous
      throw error
    }
  }

  func add(to cookbookID: UUID) {
    guard !cookbookIDs.contains(cookbookID) else { return }
    cookbookIDs.append(cookbookID)
  }

  func remove(from cookbookID: UUID) {
    cookbookIDs.removeAll { $0 == cookbookID }
  }

  private static func encode<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
  }

  private static func decode<T: Decodable>(_ value: String, as type: T.Type) -> T? {
    guard let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

enum RecipeSamples {
  static func insertIfNeeded(into context: ModelContext, existing: [Recipe]) {
    guard existing.isEmpty else { return }
    samples.forEach(context.insert)
  }

  static var samples: [Recipe] {
    [
      Recipe(
        name: "Lemon herb roast chicken",
        summary: "Crisp skin, soft herbs, and a bright pan sauce for the whole table.",
        category: "Dinner", servings: 4, prepMinutes: 20, cookMinutes: 55,
        difficulty: "Comfortable",
        ingredients: [
          .init(amount: 1, unit: "", name: "whole chicken", note: "about 4 lb"),
          .init(amount: 2, unit: "", name: "lemons"),
          .init(amount: 4, unit: "tbsp", name: "softened butter"),
          .init(amount: 3, unit: "cloves", name: "garlic", note: "finely grated"),
          .init(amount: 1, unit: "tbsp", name: "chopped rosemary"),
          .init(amount: 1, unit: "lb", name: "baby potatoes")
        ],
        steps: [
          .init(title: "Get the oven ready", detail: "Heat the oven to 425°F. Pat the chicken very dry and season generously all over.", timerMinutes: 0),
          .init(title: "Mix the herb butter", detail: "Stir together the softened butter, garlic, rosemary, lemon zest, and a good pinch of salt. Rub under and over the chicken skin.", timerMinutes: 0),
          .init(title: "Roast until golden", detail: "Set the chicken over the potatoes and lemon halves. Roast until the thickest part of the thigh reaches 165°F.", timerMinutes: 55),
          .init(title: "Let it rest", detail: "Move the chicken to a board and rest before carving. Spoon the lemony pan juices over the top.", timerMinutes: 12)
        ], isFavorite: true
      ),
      Recipe(
        name: "Miso butter mushrooms",
        summary: "Deeply savory mushrooms over creamy polenta, finished with scallions.",
        category: "Vegetarian", servings: 2, prepMinutes: 10, cookMinutes: 25,
        difficulty: "Easy",
        ingredients: [
          .init(amount: 1, unit: "lb", name: "mixed mushrooms", note: "torn into bite-size pieces"),
          .init(amount: 2, unit: "tbsp", name: "white miso"),
          .init(amount: 3, unit: "tbsp", name: "butter"),
          .init(amount: 1, unit: "cup", name: "quick-cooking polenta"),
          .init(amount: 2, unit: "", name: "scallions")
        ],
        steps: [
          .init(title: "Start the polenta", detail: "Bring 4 cups of salted water to a simmer. Whisk in polenta and cook, stirring often, until creamy.", timerMinutes: 20),
          .init(title: "Brown the mushrooms", detail: "Cook mushrooms in a hot skillet with a splash of oil. Leave them undisturbed until the first side is deeply golden.", timerMinutes: 6),
          .init(title: "Make the miso butter", detail: "Turn off the heat. Stir in butter and miso with a spoonful of water until glossy. Serve over polenta with sliced scallions.", timerMinutes: 0)
        ], isFavorite: true
      ),
      Recipe(
        name: "Sunday tomato rigatoni",
        summary: "A slow-simmered tomato sauce with basil and a generous snowfall of parmesan.",
        category: "Pasta", servings: 4, prepMinutes: 15, cookMinutes: 40,
        difficulty: "Easy",
        ingredients: [
          .init(amount: 1, unit: "lb", name: "rigatoni"),
          .init(amount: 1, unit: "", name: "yellow onion", note: "finely diced"),
          .init(amount: 3, unit: "cloves", name: "garlic"),
          .init(amount: 28, unit: "oz", name: "whole peeled tomatoes"),
          .init(amount: 0.5, unit: "cup", name: "finely grated parmesan"),
          .init(amount: 1, unit: "bunch", name: "fresh basil")
        ],
        steps: [
          .init(title: "Soften the aromatics", detail: "Cook onion in olive oil with a pinch of salt until translucent. Stir in sliced garlic and cook just until fragrant.", timerMinutes: 8),
          .init(title: "Let the sauce simmer", detail: "Crush in the tomatoes, season well, and simmer gently until thick and glossy. Tear in half the basil.", timerMinutes: 30),
          .init(title: "Bring it together", detail: "Boil rigatoni until just shy of al dente. Toss with the sauce and a splash of pasta water. Finish with parmesan and basil.", timerMinutes: 11)
        ]
      ),
      Recipe(
        name: "Maple oat pancakes",
        summary: "Tender, lacy-edged pancakes made for a slow weekend morning.",
        category: "Breakfast", servings: 4, prepMinutes: 10, cookMinutes: 15,
        difficulty: "Easy",
        ingredients: [
          .init(amount: 1.5, unit: "cup", name: "all-purpose flour"),
          .init(amount: 0.5, unit: "cup", name: "rolled oats"),
          .init(amount: 1.5, unit: "cup", name: "buttermilk"),
          .init(amount: 2, unit: "tbsp", name: "maple syrup"),
          .init(amount: 1, unit: "", name: "egg")
        ],
        steps: [
          .init(title: "Whisk the dry ingredients", detail: "Combine flour, oats, baking powder, and a pinch of salt in a large bowl.", timerMinutes: 0),
          .init(title: "Rest the batter", detail: "Whisk in buttermilk, egg, maple syrup, and melted butter. Let the batter sit while the pan heats.", timerMinutes: 5),
          .init(title: "Cook until bubbly", detail: "Spoon batter into a buttered skillet. Flip when bubbles appear and edges look set; cook the second side until golden.", timerMinutes: 3)
        ]
      )
    ]
  }
}
