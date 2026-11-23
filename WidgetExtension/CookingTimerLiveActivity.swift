#if os(iOS)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

struct CookingTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<CookingTimerMetadata>.self) { context in
      CookingTimerCard(context: context)
        .activityBackgroundTint(Color(red: 0.14, green: 0.19, blue: 0.12))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(context.attributes.metadata?.url)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          CookingTimerCard(context: context)
        }
      } compactLeading: {
        Image(systemName: "timer")
          .accessibilityLabel("Step timer")
      } compactTrailing: {
        CompactIslandContent {
          CookingTimerCountdown(mode: context.state.mode, compact: true)
            .font(.caption.monospacedDigit())
        } narrow: {
          EmptyView()
        }
      } minimal: {
        Image(systemName: "timer")
          .accessibilityLabel("Step timer")
      }
      .widgetURL(context.attributes.metadata?.url)
      .keylineTint(.green)
    }
    .supplementalActivityFamilies([.small, .medium])
  }
}

private struct CookingTimerCard: View {
  @Environment(\.activityFamily) private var family

  var context: ActivityViewContext<AlarmAttributes<CookingTimerMetadata>>

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "timer")
        .foregroundStyle(.white)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(context.attributes.metadata?.title ?? String(localized: "Step timer"))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
        CookingTimerCountdown(mode: context.state.mode)
          .font(.title3.monospacedDigit())
          .foregroundStyle(.white)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if family != .small {
        Button(intent: StopCookingTimerIntent(timerID: context.state.alarmID)) {
          Label("Stop timer", systemImage: "stop.fill")
            .labelStyle(.iconOnly)
            .frame(minWidth: 28, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(.white)
      }
    }
    .padding(family == .small ? 8 : 14)
  }
}

private struct CookingTimerCountdown: View {
  var mode: AlarmPresentationState.Mode
  var compact = false

  var body: some View {
    switch mode {
    case .countdown(let countdown):
      let interval = countdown.startDate...max(countdown.startDate, countdown.fireDate)
      if compact {
        CompactCookingCountdown(interval: interval)
      } else {
        Text(timerInterval: interval, countsDown: true, showsHours: true)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    case .paused(let paused):
      Text(Duration.seconds(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)).formatted(.time(pattern: .hourMinuteSecond)))
    case .alert:
      Text("Done")
    @unknown default:
      Image(systemName: "timer")
    }
  }
}
#endif
