import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum CookingStepMeasurements {
  struct Portion: Sendable {
    var ingredient: Int
    var amount: Double
  }

  struct Placement: Sendable {
    var step: Int
    var phrase: String
    var portions: [Portion]
    var isGroup = false
  }

  private struct Match {
    var ingredient: Int
    var phrase: String
    var explicitAmount: Double?
    var usesRemainder: Bool
  }

  static func baseline(ingredients: [RecipeIngredient], steps: [String], originalServings: Int, servings: Int, metric: Bool) -> [String] {
    render(fallback(ingredients: ingredients, steps: steps), ingredients: ingredients, steps: steps,
           originalServings: originalServings, servings: servings, metric: metric)
  }

  static func enhanced(ingredients: [RecipeIngredient], steps: [String], originalServings: Int, servings: Int, metric: Bool) async -> [String]? {
    #if canImport(FoundationModels)
    guard !ingredients.isEmpty, !steps.isEmpty, ingredients.count <= 80, steps.count <= 45,
          case .available = SystemLanguageModel.default.availability else { return nil }
    let inventory = ingredients.enumerated().map { index, item in
      "\(index + 1). \(item.amount) \(item.unit) \(item.name); section: \(item.section ?? "main"); note: \(item.note)"
    }.joined(separator: "\n")
    let directions = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    guard inventory.count + directions.count <= 12_000 else { return nil }
    let session = LanguageModelSession(instructions: """
      Match recipe ingredient numbers to the exact phrases in each step that add them. Do not rewrite the directions. When a step says to add dry ingredients, include every dry ingredient for that section used at that point, such as flour, sugar, baking powder, baking soda, and salt. Respect sections such as cake and frosting. Never invent a division or change a quantity. Skip uses of previously prepared mixtures and omit portions when the amount cannot be determined from the recipe. Amounts must be expressed in the ingredient's original unit. An ingredient can be spent only once unless explicitly divided.
      """)
    do {
      let output = try await session.respond(to: """
        Ingredients:
        \(inventory)

        Steps:
        \(directions)
        """, generating: StepMeasurementResponse.self)
      let defaults = fallback(ingredients: ingredients, steps: steps)
      var placements = defaults
      var assigned = Set(defaults.flatMap { $0.portions.map(\.ingredient) })
      for match in output.content.placements.sorted(by: { $0.step < $1.step }) {
        let step = match.step - 1
        guard steps.indices.contains(step), !match.phrase.isEmpty,
              match.phrase.count < 100, spokenRange(of: match.phrase, in: steps[step]) != nil else { continue }
        let group = match.portions.count > 1
        var portions: [Portion] = []
        for proposed in match.portions {
          let index = proposed.ingredient - 1
          guard ingredients.indices.contains(index), !assigned.contains(index) else { continue }
          let item = ingredients[index]
          guard item.amount > 0, !isDivided(item), !hasQuantityImmediatelyBefore(match.phrase, in: steps[step]),
                abs(proposed.amount - item.amount) < 0.01 else { continue }
          portions.append(.init(ingredient: index, amount: item.amount))
          assigned.insert(index)
        }
        if !portions.isEmpty {
          placements.append(.init(step: step, phrase: match.phrase, portions: portions, isGroup: group))
        }
      }
      return render(placements, ingredients: ingredients, steps: steps,
                    originalServings: originalServings, servings: servings, metric: metric)
    } catch {
      return nil
    }
    #else
    return nil
    #endif
  }

  private static func fallback(ingredients: [RecipeIngredient], steps: [String]) -> [Placement] {
    let sections = RecipeIngredientSection.group(ingredients).map(\.title).filter { !$0.isEmpty }
    var sectionIndex = sections.indices.first
    var used: [Int: Double] = [:]
    var result: [Placement] = []

    for (stepIndex, text) in steps.enumerated() {
      // Once a later section is introduced, mentioning the finished cake again does not reset the active section.
      if let later = sections.indices.last(where: { index in
        let label = sections[index].replacingOccurrences(of: #"(?i)^for\s+(?:the\s+)?"#, with: "", options: .regularExpression)
        return index >= (sectionIndex ?? 0) && spokenRange(of: label, in: text) != nil
      }) {
        sectionIndex = later
      }
      let currentSection = sectionIndex.map { sections[$0] }
      let matches = ingredients.enumerated().compactMap { index, item -> Match? in
        guard item.amount.isFinite, item.amount > 0,
              item.section == nil || item.section == currentSection else { return nil }
        return directMatch(index: index, ingredient: item, in: text)
      }
      let counts = Dictionary(grouping: matches, by: { $0.phrase.lowercased() }).mapValues(\.count)
      for match in matches where counts[match.phrase.lowercased()] == 1 {
        let item = ingredients[match.ingredient]
        let previous = used[match.ingredient, default: 0]
        let remaining = item.amount - previous
        guard remaining > 0.0001 else { continue }
        let amount: Double
        if let explicit = match.explicitAmount {
          guard explicit <= remaining + 0.01 else { continue }
          amount = min(explicit, remaining)
        } else if match.usesRemainder, previous > 0 {
          amount = remaining
        } else if !isDivided(item), previous == 0 {
          amount = item.amount
        } else {
          continue
        }
        used[match.ingredient] = previous + amount
        result.append(.init(step: stepIndex, phrase: match.phrase, portions: [.init(ingredient: match.ingredient, amount: amount)]))
      }

      if let range = text.range(of: #"(?i)\b(?:the\s+)?dry ingredients\b"#, options: .regularExpression) {
        let dry = ingredients.enumerated().compactMap { index, item -> Portion? in
          guard used[index] == nil, item.amount.isFinite, item.amount > 0, !isDivided(item), isDry(item),
                item.section == nil || item.section == currentSection else { return nil }
          used[index] = item.amount
          return Portion(ingredient: index, amount: item.amount)
        }
        if !dry.isEmpty { result.append(.init(step: stepIndex, phrase: String(text[range]), portions: dry, isGroup: true)) }
      }
    }
    return result
  }

  private static func directMatch(index: Int, ingredient: RecipeIngredient, in text: String) -> Match? {
    let name = ingredient.name.components(separatedBy: ",")[0]
    let aliases = ["baking powder", "baking soda", "cream cheese", "vanilla extract", "flour", "sugar", "butter",
                   "salt", "milk", "egg", "oil", "cocoa", "yeast", "water", "cream", "oats"]
    let key = IngredientNormalization.key(name)
    let names = [name] + aliases.filter { key.hasSuffix($0) || key.hasSuffix(" " + $0 + "s") }
    for name in names where !name.isEmpty {
      let term = NSRegularExpression.escapedPattern(for: name)
      let pattern = #"(?i)\b(?:(?:the\s+)?(?:remaining|rest of the|half(?: of)?(?: the)?)\s+|the\s+)?"# + term + #"s?\b"#
      guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
      let phrase = String(text[range])
      let lower = phrase.lowercased()
      if lower.hasPrefix("half") {
        return .init(ingredient: index, phrase: phrase, explicitAmount: ingredient.amount / 2, usesRemainder: false)
      }
      let prefix = String(text[..<range.lowerBound])
      if let explicit = explicitAmount(in: prefix, ingredient: ingredient) {
        let full = explicit.phrase + phrase
        return .init(ingredient: index, phrase: full, explicitAmount: explicit.amount, usesRemainder: false)
      }
      if hasQuantityImmediatelyBefore(phrase, in: text) { continue }
      return .init(ingredient: index, phrase: phrase, explicitAmount: nil, usesRemainder: lower.contains("remaining") || lower.contains("rest of"))
    }
    return nil
  }

  private static func explicitAmount(in prefix: String, ingredient: RecipeIngredient) -> (phrase: String, amount: Double)? {
    let expression = try? NSRegularExpression(pattern: #"(?i)(?<![\w./])(\d+\s+\d+/\d+|\d+/\d+|\d+\.\d+|\d+[¼½¾⅓⅔]|[¼½¾⅓⅔]|\d+)\s*(cups?|c\.?|tablespoons?|tbsp\.?|teaspoons?|tsp\.?|sticks?|g|grams?|oz|ounces?|lb|lbs|pounds?|ml|milliliters?)?\s+(?:of\s+)?$"#)
    guard let match = expression?.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
          let range = Range(match.range, in: prefix), let value = Range(match.range(at: 1), in: prefix),
          let amount = KitchenQuantity.parse(String(prefix[value])) else { return nil }
    if let unitRange = Range(match.range(at: 2), in: prefix) {
      let found = String(prefix[unitRange]).lowercased()
      let unit = found == "c" || found == "c." ? "cup" : found
      let target = IngredientNormalization.measurement(for: IngredientNormalization.key(ingredient.unit), ingredientName: ingredient.name.lowercased())
      let source = IngredientNormalization.measurement(for: unit, ingredientName: ingredient.name.lowercased())
      if unit == IngredientNormalization.key(ingredient.unit) { return (String(prefix[range]), amount) }
      if let source, let target, source.family == target.family {
        return (String(prefix[range]), amount * source.factor / target.factor)
      }
      return nil
    }
    return ingredient.unit.isEmpty ? (String(prefix[range]), amount) : nil
  }

  private static func spokenRange(of phrase: String, in text: String) -> Range<String.Index>? {
    let escaped = NSRegularExpression.escapedPattern(for: phrase)
    return text.range(of: #"(?i)(?<!\w)"# + escaped + #"(?!\w)"#, options: .regularExpression)
  }

  private static func hasQuantityImmediatelyBefore(_ phrase: String, in text: String) -> Bool {
    guard let range = spokenRange(of: phrase, in: text) else { return false }
    return text[..<range.lowerBound].range(of: #"(?i)\d[\d./]*\s*(?:[a-z.]+\s+)?(?:of\s+)?$"#, options: .regularExpression) != nil
  }

  private static func isDivided(_ item: RecipeIngredient) -> Bool {
    (item.name + " " + item.note).localizedCaseInsensitiveContains("divided")
  }

  private static func isDry(_ item: RecipeIngredient) -> Bool {
    let name = IngredientNormalization.key(item.name)
    return ["flour", "sugar", "baking powder", "baking soda", "salt", "cocoa", "cornstarch", "cinnamon", "nutmeg", "spice", "yeast", "oat"]
      .contains { name.contains($0) }
  }

  private static func render(_ placements: [Placement], ingredients: [RecipeIngredient], steps: [String], originalServings: Int, servings: Int, metric: Bool) -> [String] {
    let byStep = Dictionary(grouping: placements, by: \.step)
    return steps.enumerated().map { index, text in
      var replacements: [(Range<String.Index>, String)] = []
      for placement in byStep[index] ?? [] {
        guard let range = spokenRange(of: placement.phrase, in: text),
              !replacements.contains(where: { $0.0.overlaps(range) }) else { continue }
        let values = placement.portions.map { portion in
          var item = ingredients[portion.ingredient]
          item.amount = portion.amount
          return IngredientFormatter.format(item, from: originalServings, to: servings, metric: metric)
        }.joined(separator: ", ")
        let replacement = placement.isGroup ? "\(text[range]) (\(values))" : values
        replacements.append((range, replacement))
      }
      var output = text
      for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
        output.replaceSubrange(range, with: replacement)
      }
      return output
    }
  }
}

#if canImport(FoundationModels)
@Generable
private struct StepMeasurementResponse {
  var placements: [StepMeasurementPlacement]
}

@Generable
private struct StepMeasurementPlacement {
  @Guide(description: "One-based step number from the source directions")
  var step: Int
  @Guide(description: "Verbatim short phrase from this step where the ingredients are being added")
  var phrase: String
  var portions: [StepMeasurementPortion]
}

@Generable
private struct StepMeasurementPortion {
  @Guide(description: "One-based ingredient number from the list")
  var ingredient: Int
  @Guide(description: "Amount in the original ingredient unit")
  var amount: Double
}
#endif
