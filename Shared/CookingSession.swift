#if os(iOS)
import Foundation

struct CookingSession: Codable, Identifiable {
  struct Step: Codable {
    var title: String
    var instructions: String
    var timerMinutes: Int
    var measuredInstructions: String? = nil

    var defaultTimerSeconds: Double {
      CookingTimeMention.matches(in: instructions).first.map { Double($0.seconds) } ?? Double(timerMinutes) * 60
    }
  }

  struct StepTimer: Codable {
    var id: UUID
    var startedAt: Date
    var endsAt: Date
  }

  let id: UUID
  var recipeID: UUID
  var libraryID: String? = nil
  var recipeName: String
  var servings: Int
  var steps: [Step]
  var ingredientMeasurements: [String]? = nil
  var usesMetricMeasurements: Bool? = nil
  var resolvedStepMeasurements: Bool? = nil
  var stepIndex = 0
  var timers: [Int: StepTimer] = [:]

  var step: Step { steps[stepIndex] }

  var nextTimerEnd: Date? {
    let now = Date.now
    return timers.values.map(\.endsAt).filter { $0 > now }.min()
  }

  var stepTitle: String {
    step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? String(localized: "Step \(stepIndex + 1)")
      : step.title
  }
}
#endif
