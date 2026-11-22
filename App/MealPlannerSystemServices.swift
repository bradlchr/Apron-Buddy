import EventKit
import Foundation

struct CalendarDinnerContext: Sendable {
  enum Kind: Equatable, Sendable {
    case open
    case busy
    case dinnerInvitation
  }

  var date: Date
  var kind: Kind

  var message: String {
    switch kind {
    case .open: "No dinner event found"
    case .busy: "Busy during dinner time"
    case .dinnerInvitation: "Dinner invitation found"
    }
  }
}

struct ReminderListOption: Hashable, Identifiable, Sendable {
  var id: String
  var title: String
  var isEditable: Bool
}

enum MealPlannerSystemError: LocalizedError {
  case calendarAccess
  case remindersAccess
  case reminderListUnavailable

  var errorDescription: String? {
    switch self {
    case .calendarAccess: "Calendar access is unavailable. Enable it in Settings, or turn off calendar-aware suggestions and try again."
    case .remindersAccess: "Reminders access is unavailable. Enable it in Settings to add groceries to a Reminders list."
    case .reminderListUnavailable: "That Reminders list is no longer available. Choose another list and try again."
    }
  }
}

@MainActor
final class MealPlannerSystemServices {
  static let shared = MealPlannerSystemServices()

  private let eventStore = EKEventStore()

  private init() { }

  func dinnerContexts(starting startDate: Date, dayCount: Int) async throws -> [CalendarDinnerContext] {
    try await requestCalendarAccess()

    let calendar = Calendar.current
    let firstDay = calendar.startOfDay(for: startDate)
    guard let endDate = calendar.date(byAdding: .day, value: dayCount, to: firstDay) else { return [] }
    let predicate = eventStore.predicateForEvents(withStart: firstDay, end: endDate, calendars: nil)
    let events = eventStore.events(matching: predicate)

    return (0..<dayCount).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay),
            let dinnerStart = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: date),
            let dinnerEnd = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date) else { return nil }
      let overlapping = events.filter { !$0.isAllDay && $0.startDate < dinnerEnd && $0.endDate > dinnerStart }
      let hasDinnerInvitation = overlapping.contains { event in
        let title = event.title?.localizedLowercase ?? ""
        return ["dinner", "restaurant", "reservation", "supper", "cookout", "potluck", "rehearsal dinner"]
          .contains { title.localizedStandardContains($0) }
      }
      let kind: CalendarDinnerContext.Kind = hasDinnerInvitation
        ? .dinnerInvitation
        : (overlapping.isEmpty ? .open : .busy)
      return CalendarDinnerContext(date: date, kind: kind)
    }
  }

  func reminderLists() async throws -> [ReminderListOption] {
    try await requestReminderAccess()
    eventStore.refreshSourcesIfNecessary()
    var calendars = eventStore.calendars(for: .reminder)
    if let defaultCalendar = eventStore.defaultCalendarForNewReminders(),
       !calendars.contains(where: { $0.calendarIdentifier == defaultCalendar.calendarIdentifier }) {
      calendars.append(defaultCalendar)
    }
    return calendars
      .map {
        ReminderListOption(
          id: $0.calendarIdentifier,
          title: $0.title,
          isEditable: $0.allowsContentModifications
        )
      }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  func add(_ items: [GroceryListItem], to reminderListID: String) async throws {
    try await requestReminderAccess()
    guard let reminderCalendar = eventStore.calendars(for: .reminder)
      .first(where: { $0.calendarIdentifier == reminderListID && $0.allowsContentModifications }) else {
      throw MealPlannerSystemError.reminderListUnavailable
    }

    for item in items where !item.isChecked {
      let reminder = EKReminder(eventStore: eventStore)
      reminder.title = item.displayText
      reminder.calendar = reminderCalendar
      try eventStore.save(reminder, commit: false)
    }
    try eventStore.commit()
  }

  private func requestCalendarAccess() async throws {
    let status = EKEventStore.authorizationStatus(for: .event)
    if status == .fullAccess { return }
    guard status == .notDetermined else { throw MealPlannerSystemError.calendarAccess }
    guard try await eventStore.requestFullAccessToEvents() else { throw MealPlannerSystemError.calendarAccess }
  }

  private func requestReminderAccess() async throws {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if status == .fullAccess { return }
    guard status == .notDetermined else { throw MealPlannerSystemError.remindersAccess }
    guard try await eventStore.requestFullAccessToReminders() else { throw MealPlannerSystemError.remindersAccess }
  }
}
