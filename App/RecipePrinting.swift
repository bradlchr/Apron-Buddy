import Foundation
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum RecipePrinting {
  static func print(_ recipe: Recipe) {
    let content = printableText(for: recipe)
    #if os(iOS)
    let controller = UIPrintInteractionController.shared
    let info = UIPrintInfo(dictionary: nil)
    info.jobName = recipe.name
    info.outputType = .general
    controller.printInfo = info
    controller.printFormatter = UISimpleTextPrintFormatter(text: content)
    controller.present(animated: true, completionHandler: nil)
    #elseif os(macOS)
    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .automatic
    let pageWidth = printInfo.imageablePageBounds.width
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 900))
    textView.string = content
    textView.isEditable = false
    textView.isRichText = false
    textView.font = .systemFont(ofSize: 12)
    textView.textContainerInset = .zero
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(width: pageWidth, height: .greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    if let textContainer = textView.textContainer, let layoutManager = textView.layoutManager {
      layoutManager.ensureLayout(for: textContainer)
      let documentHeight = max(printInfo.imageablePageBounds.height, layoutManager.usedRect(for: textContainer).height + 24)
      textView.setFrameSize(NSSize(width: pageWidth, height: documentHeight))
    }
    let operation = NSPrintOperation(view: textView, printInfo: printInfo)
    operation.showsPrintPanel = true
    operation.run()
    #endif
  }

  private static func printableText(for recipe: Recipe) -> String {
    let ingredients = recipe.ingredients.map {
      "• \(format($0))"
    }
    let steps = recipe.steps.enumerated().map { index, step in
      var text = "\(index + 1). \(step.title)\n\(step.detail)"
      if step.timerMinutes > 0 { text += "\nTimer: \(step.timerMinutes) minutes" }
      return text
    }
    var sections = [
      recipe.name,
      "\(recipe.category) · Serves \(recipe.servings) · Prep \(recipe.prepMinutes) min · Cook \(recipe.cookMinutes) min"
    ]
    if !recipe.summary.isEmpty { sections.append(recipe.summary) }
    if !ingredients.isEmpty { sections.append("INGREDIENTS\n\(ingredients.joined(separator: "\n"))") }
    if !steps.isEmpty { sections.append("METHOD\n\(steps.joined(separator: "\n\n"))") }
    if !recipe.userNotes.isEmpty { sections.append("MY NOTES\n\(recipe.userNotes)") }
    if !recipe.sourceURL.isEmpty { sections.append("Source: \(recipe.sourceURL)") }
    return sections.joined(separator: "\n\n")
  }

  private static func format(_ ingredient: RecipeIngredient) -> String {
    [ingredient.displayAmount, ingredient.unit, ingredient.name, ingredient.note]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
