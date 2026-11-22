#if os(iOS)
import AppIntents
import Foundation

struct MoveCookingStepIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Change cooking step"
  static let isDiscoverable = false

  @Parameter(title: "Cooking session") var sessionID: String
  @Parameter(title: "Current step") var stepIndex: Int
  @Parameter(title: "Go forward") var forward: Bool

  init() {}

  init(sessionID: UUID, stepIndex: Int, forward: Bool) {
    self.sessionID = sessionID.uuidString
    self.stepIndex = stepIndex
    self.forward = forward
  }

  func perform() async throws -> some IntentResult {
    if let id = UUID(uuidString: sessionID) {
      await CookingSessionStore.shared.move(by: forward ? 1 : -1, sessionID: id, from: stepIndex)
    }
    return .result()
  }
}

struct StopCookingTimerIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Stop cooking timer"
  static let isDiscoverable = false

  @Parameter(title: "Timer") var timerID: String

  init() {}

  init(timerID: UUID) {
    self.timerID = timerID.uuidString
  }

  func perform() async throws -> some IntentResult {
    if let id = UUID(uuidString: timerID) {
      try await CookingSessionStore.stopTimer(id: id)
    }
    return .result()
  }
}
#endif
