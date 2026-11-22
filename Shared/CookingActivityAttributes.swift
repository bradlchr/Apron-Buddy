#if os(iOS)
import ActivityKit
import Foundation

struct CookingActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var stepIndex: Int
    var stepTitle: String
    var nextTimerEnd: Date? = nil
  }

  var sessionID: UUID
  var recipeName: String
  var stepCount: Int

  var url: URL? { URL(string: "apronbuddy://cooking/\(sessionID.uuidString)") }
}
#endif
