import SwiftUI

struct CookingInstructionText: View {
  @KitchenPalette private var palette
  var instruction: String
  var startTimer: (Int) -> Void

  var body: some View {
    Text(linkedInstruction)
      .font(.title3)
      .foregroundStyle(.secondary)
      .environment(\.openURL, OpenURLAction { url in
        guard url.scheme == "apronbuddy-timer", let seconds = Int(url.lastPathComponent) else { return .discarded }
        startTimer(seconds)
        return .handled
      })
      .tint(palette.accent)
  }

  private var linkedInstruction: AttributedString {
    var result = AttributedString(instruction)
    for mention in CookingTimeMention.matches(in: instruction).reversed() {
      guard let lower = AttributedString.Index(mention.range.lowerBound, within: result),
            let upper = AttributedString.Index(mention.range.upperBound, within: result) else { continue }
      result[lower..<upper].link = URL(string: "apronbuddy-timer://start/\(mention.seconds)")
      result[lower..<upper].underlineStyle = .single
    }
    return result
  }
}
