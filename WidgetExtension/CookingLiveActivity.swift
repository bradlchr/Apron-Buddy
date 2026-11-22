#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct CookingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CookingActivityAttributes.self) { context in
      CookingActivityCard(context: context)
        .activityBackgroundTint(Color(red: 0.14, green: 0.19, blue: 0.12))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(context.attributes.url)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          CookingActivityCard(context: context)
        }
      } compactLeading: {
        CompactIslandContent {
          if context.state.nextTimerEnd != nil {
            stepProgress(context)
              .font(.caption.monospacedDigit())
          } else {
            cookingIcon
          }
        } narrow: {
          cookingIcon
        }
      } compactTrailing: {
        CompactIslandContent {
          if let end = context.state.nextTimerEnd {
            Text(timerInterval: min(.now, end)...end, countsDown: true, showsHours: true)
              .font(.caption.monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: 64)
              .accessibilityLabel("Cooking timer")
          } else {
            stepProgress(context)
          }
        } narrow: {
          stepProgress(context)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 24)
        }
      } minimal: {
        cookingIcon
      }
      .widgetURL(context.attributes.url)
      .keylineTint(.green)
    }
    .supplementalActivityFamilies([.small, .medium])
  }

  private var cookingIcon: some View {
    Image(systemName: "fork.knife")
      .accessibilityLabel("Cooking")
  }

  private func stepProgress(_ context: ActivityViewContext<CookingActivityAttributes>) -> some View {
    Text("\(context.state.stepIndex + 1)/\(context.attributes.stepCount)")
      .monospacedDigit()
      .accessibilityLabel("Step \(context.state.stepIndex + 1) of \(context.attributes.stepCount)")
  }
}

private struct CookingActivityCard: View {
  @Environment(\.activityFamily) private var family

  var context: ActivityViewContext<CookingActivityAttributes>

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.recipeName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.8))
          .lineLimit(1)
        Text(context.state.stepTitle)
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)
        Text("Step \(context.state.stepIndex + 1) of \(context.attributes.stepCount)")
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.8))
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if family != .small {
        stepButton(forward: false)
          .disabled(context.state.stepIndex == 0)
        stepButton(forward: true)
          .disabled(context.state.stepIndex + 1 >= context.attributes.stepCount)
      }
    }
    .padding(family == .small ? 8 : 14)
  }

  private func stepButton(forward: Bool) -> some View {
    Button(intent: MoveCookingStepIntent(
      sessionID: context.attributes.sessionID,
      stepIndex: context.state.stepIndex,
      forward: forward
    )) {
      Label(
        forward ? "Next step" : "Previous step",
        systemImage: forward ? "chevron.forward" : "chevron.backward"
      )
      .labelStyle(.iconOnly)
      .frame(minWidth: 28, minHeight: 30)
    }
    .buttonStyle(.bordered)
    .tint(.white)
  }
}
#endif
