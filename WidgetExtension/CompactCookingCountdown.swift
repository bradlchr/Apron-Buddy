#if os(iOS)
import SwiftUI

struct CompactCookingCountdown: View {
  var interval: ClosedRange<Date>

  private var duration: TimeInterval {
    interval.upperBound.timeIntervalSince(interval.lowerBound).rounded(.up)
  }

  var body: some View {
    let showsHours = duration >= 3600
    let pattern: Duration.TimeFormatStyle.Pattern = showsHours ? .hourMinuteSecond : .minuteSecond

    // A live timer text expands to the available width. Size it for the longest value it can show.
    Text(Duration.seconds(duration), format: .time(pattern: pattern))
      .hidden()
      .overlay(alignment: .trailing) {
        Text(timerInterval: interval, countsDown: true, showsHours: showsHours)
          .multilineTextAlignment(.trailing)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
  }
}
#endif
