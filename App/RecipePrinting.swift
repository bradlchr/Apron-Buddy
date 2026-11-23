import CoreGraphics
import CoreText
import Foundation
import PDFKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum RecipePrinting {
  private static let forest = CGColor(red: 0.17, green: 0.29, blue: 0.19, alpha: 1)
  private static let cream = CGColor(red: 0.99, green: 0.98, blue: 0.94, alpha: 1)
  private static let ink = CGColor(red: 0.16, green: 0.18, blue: 0.15, alpha: 1)

  @discardableResult
  static func print(_ recipe: Recipe) -> Bool {
    guard let data = pdf(for: recipe) else { return false }
    #if os(iOS)
    guard UIPrintInteractionController.isPrintingAvailable else { return false }
    let controller = UIPrintInteractionController.shared
    let info = UIPrintInfo(dictionary: nil)
    info.jobName = recipe.name
    info.outputType = .general
    controller.printInfo = info
    controller.printingItem = data
    return controller.present(animated: true, completionHandler: nil)
    #elseif os(macOS)
    guard let document = PDFDocument(data: data),
          let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
    else { return false }
    operation.jobTitle = recipe.name
    operation.showsPrintPanel = true
    operation.run()
    return true
    #else
    return false
    #endif
  }

  static func pdf(for recipe: Recipe) -> Data? {
    let content = recipeText(recipe)
    let typesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
    let data = NSMutableData()
    var page = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { return nil }

    let textArea = CGPath(rect: CGRect(x: 52, y: 54, width: 508, height: 686), transform: nil)
    var offset = 0
    var pageNumber = 1
    while offset < content.length {
      let frame = CTFramesetterCreateFrame(typesetter, CFRange(location: offset, length: 0), textArea, nil)
      let visible = CTFrameGetVisibleStringRange(frame)
      guard visible.length > 0 else { return nil }

      context.beginPDFPage(nil)
      context.setFillColor(cream)
      context.fill(page)
      context.setFillColor(forest)
      context.fill(CGRect(x: 0, y: 780, width: page.width, height: 12))
      CTFrameDraw(frame, context)
      let footer = CTLineCreateWithAttributedString(styled("APRON BUDDY  ·  \(pageNumber)", size: 9, color: forest) as CFAttributedString)
      context.textPosition = CGPoint(x: 52, y: 30)
      CTLineDraw(footer, context)
      context.endPDFPage()
      offset = visible.location + visible.length
      pageNumber += 1
    }
    context.closePDF()
    return data as Data
  }

  private static func recipeText(_ recipe: Recipe) -> NSAttributedString {
    let text = NSMutableAttributedString()
    func append(_ value: String, size: CGFloat = 12, color: CGColor? = nil, font: String = "Helvetica") {
      text.append(styled(value + "\n", size: size, color: color ?? ink, font: font))
    }
    func heading(_ value: String) {
      append("\n" + value, size: 13, color: forest, font: "Helvetica-Bold")
    }

    append(recipe.name, size: 34, color: forest, font: "Georgia-Bold")
    append("\(recipe.category)  ·  Serves \(recipe.servings)  ·  Prep \(recipe.prepMinutes) min  ·  Cook \(recipe.cookMinutes) min", color: forest)
    if !recipe.summary.isEmpty { append("\n" + recipe.summary) }
    if !recipe.ingredients.isEmpty {
      heading("Ingredients")
      for section in RecipeIngredientSection.group(recipe.ingredients) {
        if !section.title.isEmpty {
          append(section.title, size: 12, color: forest, font: "Helvetica-Bold")
        }
        for ingredient in section.ingredients {
          let item = IngredientNormalization.clean(ingredient)
          let measurement = item.amount > 0 ? [item.displayAmount, KitchenQuantity.unitLabel(item.unit, amount: item.amount)] : []
          append("•  " + (measurement + [item.name, item.note]).filter { !$0.isEmpty }.joined(separator: " "))
        }
      }
    }
    if !recipe.steps.isEmpty {
      heading("Method")
      for (index, step) in recipe.steps.enumerated() {
        append("\(index + 1). \(step.title)", size: 13, color: forest, font: "Helvetica-Bold")
        append(step.detail)
        if step.timerMinutes > 0 { append("Timer · \(step.timerMinutes) min", size: 10, color: forest) }
        append("")
      }
    }
    if !recipe.userNotes.isEmpty { heading("Notes"); append(recipe.userNotes) }
    if !recipe.sourceURL.isEmpty { append("Source · \(recipe.sourceURL)", size: 10, color: forest) }
    return text
  }

  private static func styled(_ text: String, size: CGFloat, color: CGColor, font: String = "Helvetica") -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    paragraph.paragraphSpacing = 3
    return NSAttributedString(string: text, attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      .paragraphStyle: paragraph
    ])
  }
}
