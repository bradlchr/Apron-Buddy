#if os(iOS)
import ActivityKit
import AlarmKit
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class CookingSessionStore {
  static let shared = CookingSessionStore()

  private(set) var session: CookingSession?
  private(set) var presentationRequest = UUID()
  private(set) var activityMessage: String?
  private(set) var timerMessage: String?
  private(set) var needsTimerPermission = false
  private(set) var isStartingTimer = false

  @ObservationIgnored private var activityUpdate: Task<Void, Never>?
  private static let storageKey = "activeCookingSession"

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
       let saved = try? JSONDecoder().decode(CookingSession.self, from: data),
       saved.steps.indices.contains(saved.stepIndex) {
      session = saved
    }
  }

  func start(_ newSession: CookingSession) {
    guard !newSession.steps.isEmpty else { return }
    if session?.recipeID != newSession.recipeID {
      finish()
      save(newSession)
    }
    requestPresentation()
  }

  func requestPresentation() {
    guard session != nil else { return }
    presentationRequest = UUID()
    startActivityIfNeeded()
  }

  func finish() {
    let activities = Activity<CookingActivityAttributes>.activities
    save(nil)
    activityMessage = nil
    timerMessage = nil
    needsTimerPermission = false

    let previousUpdate = activityUpdate
    activityUpdate = Task {
      await previousUpdate?.value
      for activity in activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  func move(by offset: Int, sessionID: UUID, from index: Int) async {
    guard var session, session.id == sessionID, session.stepIndex == index,
          offset == -1 || offset == 1,
          session.steps.indices.contains(index + offset) else { return }
    session.stepIndex += offset
    save(session)
    timerMessage = nil
    needsTimerPermission = false

    await updateActivity(for: session).value
  }

  @discardableResult
  private func updateActivity(for session: CookingSession) -> Task<Void, Never> {
    let content = activityContent(for: session)
    let activities = Activity<CookingActivityAttributes>.activities.filter { $0.attributes.sessionID == session.id }
    let previousUpdate = activityUpdate
    let update = Task {
      await previousUpdate?.value
      for activity in activities {
        await activity.update(content)
      }
    }
    activityUpdate = update
    return update
  }

  func startActivityIfNeeded() {
    guard let session else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      activityMessage = String(localized: "Live Activities are turned off for Apron Buddy.")
      return
    }
    activityMessage = nil
    guard !Activity<CookingActivityAttributes>.activities.contains(where: { $0.attributes.sessionID == session.id }) else { return }

    do {
      let attributes = CookingActivityAttributes(
        sessionID: session.id,
        recipeName: String(session.recipeName.unicodeScalars.prefix(160)),
        stepCount: session.steps.count
      )
      _ = try Activity.request(attributes: attributes, content: activityContent(for: session), pushType: nil)
    } catch {
      activityMessage = String(localized: "Couldn’t start the cooking Live Activity. You can still follow the recipe here.")
    }
  }

  func observeTimers() async {
    let manager = AlarmManager.shared
    if let alarms = try? manager.alarms { reconcileTimers(alarms) }
    for await alarms in manager.alarmUpdates {
      reconcileTimers(alarms)
    }
  }

  func startTimer() async {
    guard let current = session, current.step.timerMinutes > 0,
          current.timers[current.stepIndex] == nil, !isStartingTimer else { return }
    isStartingTimer = true
    timerMessage = nil
    needsTimerPermission = false
    defer { isStartingTimer = false }

    let manager = AlarmManager.shared
    do {
      let authorization = try await manager.requestAuthorization()
      guard authorization == .authorized else {
        needsTimerPermission = true
        timerMessage = String(localized: "Allow alarms for Apron Buddy in Settings to start a step timer.")
        return
      }
      guard session?.id == current.id else { return }

      let title = String(current.stepTitle.prefix(160))
      let alertTitle: LocalizedStringResource = "\(title)"
      let alert: AlarmPresentation.Alert
      if #available(iOS 26.1, *) {
        alert = .init(title: alertTitle)
      } else {
        alert = .init(title: alertTitle, stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
      }
      let attributes = AlarmAttributes(
        presentation: .init(alert: alert, countdown: .init(title: alertTitle)),
        metadata: CookingTimerMetadata(sessionID: current.id, title: title),
        tintColor: .green
      )
      let duration = TimeInterval(current.step.timerMinutes) * 60
      let id = UUID()
      let startedAt = Date.now
      _ = try await manager.schedule(id: id, configuration: .timer(duration: duration, attributes: attributes))
      if var latest = session, latest.id == current.id {
        latest.timers[current.stepIndex] = .init(id: id, startedAt: startedAt, endsAt: startedAt.addingTimeInterval(duration))
        save(latest)
        startActivityIfNeeded()
        await updateActivity(for: latest).value
      }
    } catch {
      timerMessage = String(localized: "Couldn’t start the system timer. Try again.")
    }
  }

  func stopTimer() {
    guard var session, let timer = session.timers[session.stepIndex] else { return }
    do {
      try Self.stopTimer(id: timer.id)
      session.timers.removeValue(forKey: session.stepIndex)
      save(session)
      updateActivity(for: session)
      timerMessage = nil
    } catch {
      timerMessage = String(localized: "Couldn’t stop the system timer. Try again.")
    }
  }

  static func stopTimer(id: UUID) throws {
    let manager = AlarmManager.shared
    guard let alarm = try manager.alarms.first(where: { $0.id == id }) else { return }
    if alarm.state == .alerting {
      try manager.stop(id: id)
    } else {
      try manager.cancel(id: id)
    }
  }

  private func reconcileTimers(_ alarms: [Alarm]) {
    guard var session else { return }
    let ids = Set(alarms.map(\.id))
    let timers = session.timers.filter { ids.contains($0.value.id) }
    guard timers.count != session.timers.count else { return }
    session.timers = timers
    save(session)
    updateActivity(for: session)
  }

  private func activityContent(for session: CookingSession) -> ActivityContent<CookingActivityAttributes.ContentState> {
    .init(
      state: .init(
        stepIndex: session.stepIndex,
        stepTitle: String(session.stepTitle.unicodeScalars.prefix(160)),
        nextTimerEnd: session.nextTimerEnd
      ),
      staleDate: nil,
      relevanceScore: 100
    )
  }

  private func save(_ session: CookingSession?) {
    self.session = session
    if let session, let data = try? JSONEncoder().encode(session) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    } else {
      UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
  }
}
#endif
