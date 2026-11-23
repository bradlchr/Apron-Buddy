import Foundation

struct CookingTimeMention {
  var range: Range<String.Index>
  var seconds: Int

  private static let fractions = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]
  private static let quantity = #"\d{1,4}(?:\s+\d{1,2}/\d{1,2}|/\d{1,2}|\.\d{1,3}|[¼½¾⅓⅔])?|[¼½¾⅓⅔]|half(?:\s+an?)?|an?"#
  private static let units = #"hours?|hrs?|h|minutes?|mins?|seconds?|secs?"#
  private static let expression = try? NSRegularExpression(
    pattern: #"(?<![\w./])("# + quantity + #")(?:\s*(?:[-–—]|\bto\b)\s*(?:"# + quantity + #"))?\s*("# + units + #")\b(?:\s*(?:and\s+)?("# + quantity + #")\s*(minutes?|mins?|seconds?|secs?)\b)?"#,
    options: .caseInsensitive
  )

  static func matches(in text: String) -> [Self] {
    guard let expression else { return [] }
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
      guard let range = Range(match.range, in: text) else { return nil }
      let seconds = duration(match, value: 1, unit: 2, in: text) + duration(match, value: 3, unit: 4, in: text)
      guard seconds > 0, seconds <= 86_400 else { return nil }
      return CookingTimeMention(range: range, seconds: seconds)
    }
  }

  private static func duration(_ match: NSTextCheckingResult, value: Int, unit: Int, in text: String) -> Int {
    guard let valueRange = Range(match.range(at: value), in: text),
          let unitRange = Range(match.range(at: unit), in: text),
          let number = parseQuantity(String(text[valueRange])) else { return 0 }
    let multiplier: Double
    switch text[unitRange].lowercased().first {
    case "h": multiplier = 3_600
    case "m": multiplier = 60
    default: multiplier = 1
    }
    return Int((number * multiplier).rounded())
  }

  private static func parseQuantity(_ raw: String) -> Double? {
    let value = raw.lowercased()
    if value.hasPrefix("half") { return 0.5 }
    if value == "a" || value == "an" { return 1 }
    if let number = Double(value) { return number }
    if let last = value.last, let fraction = fractions[String(last)] {
      return (Double(value.dropLast()) ?? 0) + fraction
    }
    let parts = value.split(whereSeparator: \.isWhitespace)
    guard let last = parts.last else { return nil }
    let ratio = last.split(separator: "/")
    guard ratio.count == 2, let numerator = Double(ratio[0]), let denominator = Double(ratio[1]), denominator > 0 else { return nil }
    let whole = parts.count > 1 ? (Double(parts[0]) ?? 0) : 0
    return whole + numerator / denominator
  }
}
