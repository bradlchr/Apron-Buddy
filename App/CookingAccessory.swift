#if os(iOS)
import SwiftUI

struct CookingAccessory: View {
  @KitchenPalette private var palette
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  var session: CookingSession
  var open: () -> Void

  private var isInline: Bool { placement == .inline }
  private var glassTint: Color { palette.strongAccent.mix(with: .black, by: 0.22).opacity(0.74) }

  var body: some View {
    Button(action: open) {
      HStack(spacing: isInline ? 8 : 10) {
        Image(systemName: "fork.knife")
          .font(.subheadline.weight(.semibold))
          .frame(width: isInline ? 28 : 34, height: isInline ? 28 : 34)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 1) {
          Text(session.recipeName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text(isInline ? "Step \(session.stepIndex + 1)" : "Step \(session.stepIndex + 1) · \(session.stepTitle)")
            .font(.caption)
            .lineLimit(1)
            .accessibilityLabel("Step \(session.stepIndex + 1), \(session.stepTitle)")
        }
        Spacer(minLength: 4)
        if let end = session.nextTimerEnd {
          TimelineView(.explicit([.now, end])) { timeline in
            if timeline.date < end {
              Text(timerInterval: timeline.date...end, countsDown: true, showsHours: true)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
            }
          }
        }
        if !isInline {
          Image(systemName: "chevron.up")
            .font(.caption.weight(.semibold))
            .accessibilityHidden(true)
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, isInline ? 10 : 12)
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: placement == nil ? nil : .infinity)
      .glassEffect(.regular.tint(glassTint).interactive(), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Resumes cooking at the current step")
  }
}
#endif
