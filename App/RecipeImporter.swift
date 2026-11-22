import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ImportedRecipeDraft {
  var name: String
  var summary: String
  var category: String
  var servings: Int
  var caloriesPerServing: Int = 0
  var prepMinutes: Int
  var cookMinutes: Int
  var ingredients: [RecipeIngredient]
  var steps: [RecipeStep]
  var goodFor: [RecipeGoodFor] = []
  var aiExtracted = true
}

enum RecipeImportError: LocalizedError {
  case unsupportedFile
  case unreadableFile
  case noTextFound
  case modelUnavailable
  case modelUnsupported

  var errorDescription: String? {
    switch self {
    case .unsupportedFile: "This file type can’t be read yet. Try a PDF, text file, or recipe link."
    case .unreadableFile: "Apron Buddy couldn’t read that file. Try sharing it again."
    case .noTextFound: "No recipe text was found. You can paste the recipe below instead."
    case .modelUnavailable: "Apple Intelligence isn’t available on this device right now. You can still add the recipe by hand."
    case .modelUnsupported: "AI recipe extraction isn’t available on this system version."
    }
  }
}

enum RecipeSourceReader {
  static func text(fromImagePages pages: [Data]) throws -> String {
    let text = pages.compactMap { data -> String? in
      guard let recognized = try? recognizeText(in: data) else { return nil }
      return recognized
    }.joined(separator: "\n\n")
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RecipeImportError.noTextFound
    }
    return text
  }

  static func text(from url: URL) async throws -> String {
    if url.isFileURL {
      if ["html", "htm"].contains(url.pathExtension.lowercased()),
         let html = try? String(contentsOf: url, encoding: .utf8) {
        return cleanHTML(html)
      }
      if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
        guard let imageData = compressedImageData(from: url, maxPixelSize: 1600) else {
          throw RecipeImportError.unreadableFile
        }
        return try recognizeText(in: imageData)
      }
      if let document = PDFDocument(url: url) {
        let pageLimit = min(document.pageCount, 20)
        let pageText = (0..<pageLimit).compactMap { document.page(at: $0)?.string }
          .joined(separator: "\n\n")
        if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return String(pageText.prefix(40_000))
        }
        return try recognizeText(in: document)
      }
      if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
        return text
      }
      if let data = try? Data(contentsOf: url), let ocr = try? recognizeText(in: data), !ocr.isEmpty {
        return ocr
      }
      throw RecipeImportError.unsupportedFile
    }

    let (data, response) = try await URLSession.shared.data(from: url)
    if response.mimeType == UTType.pdf.preferredMIMEType,
       let document = PDFDocument(data: data), let text = document.string, !text.isEmpty {
      return text
    }
    guard let html = String(data: data, encoding: .utf8) else { throw RecipeImportError.unreadableFile }
    return cleanHTML(html)
  }

  static func compressedImageData(from url: URL, maxPixelSize: Int = 1800) -> Data? {
    autoreleasepool {
      let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
      let thumbnailOptions: CFDictionary = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceShouldCacheImmediately: true
      ] as CFDictionary
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
        return nil
      }
      CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.76] as CFDictionary)
      guard CGImageDestinationFinalize(destination) else { return nil }
      return output as Data
    }
  }

  private static func cleanHTML(_ html: String) -> String {
    let cleaned = html
      .replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&#x27;", with: "'")
    return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func recognizeText(in data: Data) throws -> String {
    try autoreleasepool {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      try VNImageRequestHandler(data: data).perform([request])
      let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
      guard !text.isEmpty else { throw RecipeImportError.noTextFound }
      return text
    }
  }

  private static func recognizeText(in document: PDFDocument) throws -> String {
    var pageTexts: [String] = []
    let pageLimit = min(document.pageCount, 12)
    for index in 0..<pageLimit {
      let pageText: String? = autoreleasepool {
        guard let page = document.page(at: index),
              let data = imageData(for: page) else { return nil }
        return try? recognizeText(in: data)
      }
      if let pageText { pageTexts.append(pageText) }
    }
    guard !pageTexts.isEmpty else { throw RecipeImportError.noTextFound }
    return pageTexts.joined(separator: "\n\n")
  }

  private static func imageData(for page: PDFPage) -> Data? {
    let size = CGSize(width: 1300, height: 1750)
    #if canImport(UIKit)
    return page.thumbnail(of: size, for: .mediaBox).jpegData(compressionQuality: 0.72)
    #elseif canImport(AppKit)
    let image = page.thumbnail(of: size, for: .mediaBox)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    #else
    return nil
    #endif
  }
}

enum OnDeviceRecipeAI {
  static func extract(from source: String) async throws -> ImportedRecipeDraft {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      guard case .available = SystemLanguageModel.default.availability else {
        throw RecipeImportError.modelUnavailable
      }
      let session = LanguageModelSession(instructions: """
        You are a careful recipe editor. Extract only details supported by the source. Keep ingredient quantities, units, and steps faithful to the source. Capture calories per serving only when the source explicitly lists them; use zero when they are missing, and never estimate nutrition. If another detail is missing, use a sensible short value and never invent safety guidance. Return a concise recipe.
        """)
      let response = try await session.respond(to: source, generating: GeneratedRecipe.self)
      let value = response.content
      return ImportedRecipeDraft(
        name: value.name,
        summary: value.summary,
        category: value.category,
        servings: max(1, value.servings),
        caloriesPerServing: max(0, value.caloriesPerServing),
        prepMinutes: max(0, value.prepMinutes),
        cookMinutes: max(0, value.cookMinutes),
        ingredients: value.ingredients.map {
          RecipeIngredient(amount: max(0, $0.amount), unit: $0.unit, name: $0.name, note: $0.note)
        },
        steps: value.steps.map {
          RecipeStep(title: $0.title, detail: $0.detail, timerMinutes: max(0, $0.timerMinutes))
        },
        aiExtracted: true
      )
    }
    #endif
    throw RecipeImportError.modelUnsupported
  }
}

enum SimpleRecipeParser {
  private enum Section {
    case details
    case ingredients
    case method
  }

  static func extract(from source: String, suggestedName: String) -> ImportedRecipeDraft {
    let lines = source
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let fallbackTitle = suggestedName
      .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: ".txt", with: "", options: .caseInsensitive)
    let titleLine = lines.first(where: { !isHeading($0) }) ?? "Imported recipe"
    let name = titleLine.count < 100 ? titleLine : (fallbackTitle.isEmpty ? "Imported recipe" : fallbackTitle)
    var section = Section.details
    var ingredientLines: [String] = []
    var stepLines: [String] = []
    var details: [String] = []

    for (index, line) in lines.enumerated() {
      if isIngredientHeading(line) { section = .ingredients; continue }
      if isMethodHeading(line) { section = .method; continue }
      if isHeading(line) { continue }
      if index == lines.firstIndex(of: titleLine) { continue }

      switch section {
      case .ingredients:
        ingredientLines.append(line)
      case .method:
        stepLines.append(line)
      case .details:
        if looksLikeNumberedStep(line) {
          stepLines.append(line)
        } else if looksLikeIngredient(line) {
          ingredientLines.append(line)
        } else {
          details.append(line)
        }
      }
    }

    let ingredients = ingredientLines.compactMap(parseIngredient)
    var steps = stepLines.map(parseStep)
    if steps.isEmpty {
      let body = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : source
      if !body.isEmpty { steps = [RecipeStep(title: "Imported recipe text", detail: body)] }
    }
    if steps.isEmpty {
      steps = [RecipeStep(title: "Add your first step", detail: "Edit this recipe and add its cooking method.")]
    }

    let summary = details.first(where: { $0.count > 12 && $0.count < 180 })
      ?? "Imported from \(fallbackTitle.isEmpty ? "a shared source" : fallbackTitle)."
    let lower = source.lowercased()
    let category = lower.contains("breakfast") || lower.contains("pancake") ? "Breakfast"
      : lower.contains("dessert") || lower.contains("cake") || lower.contains("cookie") ? "Dessert"
      : lower.contains("pasta") || lower.contains("rigatoni") || lower.contains("spaghetti") ? "Pasta"
      : lower.contains("vegetarian") || lower.contains("mushroom") ? "Vegetarian"
      : "Dinner"
    let servings = firstInteger(matching: #"(?i)(?:serves|servings|yield)\s*(?:about\s*)?(\d+)"#, in: source) ?? 4
    return ImportedRecipeDraft(
      name: name,
      summary: summary,
      category: category,
      servings: min(24, max(1, servings)),
      caloriesPerServing: firstInteger(
        matching: #"(?i)(?:calories|kcal)\s*(?:per serving)?\s*[:·]?\s*(\d{1,4})|(\d{1,4})\s*(?:kcal|calories)(?:\s+per serving)?"#,
        in: source
      ) ?? 0,
      prepMinutes: firstInteger(matching: #"(?i)prep(?:aration)?\s*(?:time)?\s*[:·]?\s*(\d+)"#, in: source) ?? 0,
      cookMinutes: firstInteger(matching: #"(?i)cook(?:ing)?\s*(?:time)?\s*[:·]?\s*(\d+)"#, in: source) ?? 0,
      ingredients: ingredients,
      steps: steps,
      aiExtracted: false
    )
  }

  private static func isHeading(_ line: String) -> Bool {
    let value = line.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    return ["ingredients", "what you need", "what you'll need", "you will need", "method", "instructions", "directions", "preparation", "notes"].contains(value)
  }

  private static func isIngredientHeading(_ line: String) -> Bool {
    let value = line.lowercased()
    return value.contains("ingredient") || value.contains("what you'll need") || value.contains("what you need")
  }

  private static func isMethodHeading(_ line: String) -> Bool {
    let value = line.lowercased()
    return ["method", "instructions", "directions"].contains { value.contains($0) } || value == "preparation"
  }

  private static func looksLikeNumberedStep(_ line: String) -> Bool {
    line.range(of: #"^\s*\d+[.)]\s+\p{L}"#, options: .regularExpression) != nil
  }

  private static func looksLikeIngredient(_ line: String) -> Bool {
    line.range(of: #"^\s*(?:[-•*]\s*)?(?:\d|[¼½¾])"#, options: .regularExpression) != nil
  }

  private static func parseIngredient(_ sourceLine: String) -> RecipeIngredient? {
    let line = sourceLine.replacingOccurrences(of: #"^\s*[-•*]\s*"#, with: "", options: .regularExpression)
    guard !line.isEmpty else { return nil }
    let pattern = #"^\s*(\d+\s+\d+\/\d+|\d+\/\d+|\d+(?:\.\d+)?|[¼½¾])\s*(.*)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
          let quantityRange = Range(match.range(at: 1), in: line),
          let remainderRange = Range(match.range(at: 2), in: line) else {
      return RecipeIngredient(amount: 1, unit: "", name: line)
    }
    let amount = parseQuantity(String(line[quantityRange])) ?? 1
    let remainder = String(line[remainderRange]).trimmingCharacters(in: .whitespaces)
    let words = remainder.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
    guard !words.isEmpty else { return nil }
    let knownUnits: Set<String> = ["tsp", "teaspoon", "teaspoons", "tbsp", "tablespoon", "tablespoons", "cup", "cups", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "kg", "ml", "l", "clove", "cloves", "bunch", "pinch", "can", "cans"]
    let unit = knownUnits.contains(words[0].lowercased()) ? words[0] : ""
    let name = unit.isEmpty ? remainder : words.dropFirst().joined(separator: " ")
    return RecipeIngredient(amount: amount, unit: unit, name: name.isEmpty ? remainder : name)
  }

  private static func parseStep(_ sourceLine: String) -> RecipeStep {
    let cleaned = sourceLine.replacingOccurrences(of: #"^\s*(?:[-•*]\s*)?\d+[.)]?\s*"#, with: "", options: .regularExpression)
    let timer = firstInteger(matching: #"(?i)(\d+)\s*(?:minutes?|mins?)"#, in: cleaned) ?? 0
    let title = String(cleaned.prefix(65)).split(separator: ".").first.map(String.init) ?? "Continue"
    return RecipeStep(title: title.isEmpty ? "Continue" : title, detail: cleaned, timerMinutes: timer)
  }

  private static func parseQuantity(_ value: String) -> Double? {
    let cleaned = value.trimmingCharacters(in: .whitespaces)
    if let unicode = ["¼": 0.25, "½": 0.5, "¾": 0.75][cleaned] { return unicode }
    if cleaned.contains(" "), let last = cleaned.split(separator: " ").last, let fractional = parseFraction(String(last)) {
      let whole = cleaned.split(separator: " ").first.flatMap { Double($0) } ?? 0
      return whole + fractional
    }
    if let fraction = parseFraction(cleaned) { return fraction }
    return Double(cleaned)
  }

  private static func parseFraction(_ value: String) -> Double? {
    let parts = value.split(separator: "/")
    guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 else { return nil }
    return numerator / denominator
  }

  private static func firstInteger(matching pattern: String, in value: String) -> Int? {
    guard let range = value.range(of: pattern, options: .regularExpression),
          let match = value[range].range(of: #"\d+"#, options: .regularExpression) else { return nil }
    return Int(value[match])
  }
}

#if canImport(FoundationModels)
@Generable(description: "A recipe carefully extracted from source text")
private struct GeneratedRecipe {
  var name: String
  var summary: String
  var category: String
  @Guide(description: "Number of servings", .range(1...24))
  var servings: Int
  @Guide(description: "Calories per serving when explicitly stated in the source, otherwise zero", .range(0...5000))
  var caloriesPerServing: Int
  @Guide(description: "Preparation time in minutes", .range(0...600))
  var prepMinutes: Int
  @Guide(description: "Cooking time in minutes", .range(0...1200))
  var cookMinutes: Int
  var ingredients: [GeneratedIngredient]
  var steps: [GeneratedStep]
}

@Generable(description: "A recipe ingredient with its quantity")
private struct GeneratedIngredient {
  var amount: Double
  var unit: String
  var name: String
  var note: String
}

@Generable(description: "One instruction in a recipe")
private struct GeneratedStep {
  var title: String
  var detail: String
  @Guide(description: "Timer duration in minutes, or zero if no timer is stated", .range(0...1440))
  var timerMinutes: Int
}
#endif
