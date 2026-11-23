import Foundation

enum KitchenQuantity {
  struct Style: ParseableFormatStyle {
    var parseStrategy: FractionParser { FractionParser() }

    func format(_ value: Double) -> String { KitchenQuantity.format(value) }
  }

  struct FractionParser: ParseStrategy {
    func parse(_ value: String) throws -> Double {
      guard let amount = KitchenQuantity.parse(value) else { throw CocoaError(.formatting) }
      return amount
    }
  }

  static func parse(_ text: String) -> Double? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let number = Double(value), number.isFinite, number >= 0 { return number }
    if let last = value.last,
       let fraction = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3,
                       "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875][String(last)] {
      let prefix = value.dropLast().trimmingCharacters(in: .whitespaces)
      guard prefix.isEmpty || Int(prefix).map({ $0 >= 0 }) == true else { return nil }
      return (Double(prefix) ?? 0) + fraction
    }
    let parts = value.replacingOccurrences(of: "⁄", with: "/").split(whereSeparator: \.isWhitespace)
    guard (1...2).contains(parts.count), let last = parts.last else { return nil }
    let fraction = last.split(separator: "/")
    guard fraction.count == 2, let numerator = Int(fraction[0]), let denominator = Int(fraction[1]),
          numerator >= 0, denominator > 0 else { return nil }
    let whole = parts.count == 2 ? Int(parts[0]) : 0
    guard let whole, whole >= 0 else { return nil }
    return Double(whole) + Double(numerator) / Double(denominator)
  }

  static func unitLabel(_ unit: String, amount: Double) -> String {
    guard unit.caseInsensitiveCompare("cup") == .orderedSame || unit.caseInsensitiveCompare("cups") == .orderedSame else { return unit }
    return amount > 1 ? "cups" : "cup"
  }

  static func format(_ value: Double) -> String {
    guard value.isFinite, value >= 0, value < Double(Int.max) else { return value.formatted() }
    let whole = Int(value)
    let remainder = value - Double(whole)
    if remainder < 0.005 { return whole.formatted() }
    for denominator in [2, 3, 4, 5, 6, 8, 12, 16] {
      let numerator = Int((remainder * Double(denominator)).rounded())
      guard numerator > 0, abs(remainder - Double(numerator) / Double(denominator)) <= 0.0075 else { continue }
      if numerator == denominator { return (whole + 1).formatted() }
      let fraction = "\(numerator)/\(denominator)"
      return whole == 0 ? fraction : "\(whole.formatted()) \(fraction)"
    }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }
}
