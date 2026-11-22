#if os(iOS)
import AlarmKit
import Foundation

struct CookingTimerMetadata: AlarmMetadata {
  var sessionID: UUID
  var title: String

  var url: URL? { URL(string: "apronbuddy://cooking/\(sessionID.uuidString)") }
}
#endif
