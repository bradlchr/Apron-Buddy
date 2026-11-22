#if os(iOS)
import SwiftUI

struct CookingAccessory: View {
  var session: CookingSession
  var open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: 10) {
        Image(systemName: "fork.knife")
          .font(.subheadline.weight(.semibold))
          .frame(width: 34, height: 34)
          .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 1) {
          Text(session.recipeName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text("Step \(session.stepIndex + 1) · \(session.stepTitle)")
            .font(.caption)
            .lineLimit(1)
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
        Image(systemName: "chevron.up")
          .font(.caption.weight(.semibold))
          .accessibilityHidden(true)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Resumes cooking at the current step")
  }
}
#endif
