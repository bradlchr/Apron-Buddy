import AppIntents
import SwiftUI
import WidgetKit

@main
struct ApronBuddyWidgets: WidgetBundle {
  var body: some Widget {
    CookbookWidget()
    TodayMealWidget()
    MealPlanOverviewWidget()
    GroceryListWidget()
  }
}

struct WidgetCookbookEntity: AppEntity, Identifiable, Sendable {
  var id: String
  @Property(title: "Name")
  var name: String

  init(id: String, name: String) {
    self.id = id
    self.name = name
  }

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cookbook")
  static var defaultQuery = WidgetCookbookEntityQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetCookbookEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [WidgetCookbookEntity] {
    let wanted = Set(identifiers)
    return SharedKitchenSnapshotStore.load().cookbooks
      .filter { wanted.contains($0.id.uuidString) }
      .map { WidgetCookbookEntity(id: $0.id.uuidString, name: $0.name) }
  }

  func suggestedEntities() async throws -> [WidgetCookbookEntity] {
    SharedKitchenSnapshotStore.load().cookbooks
      .map { WidgetCookbookEntity(id: $0.id.uuidString, name: $0.name) }
  }

  func entities(matching string: String) async throws -> [WidgetCookbookEntity] {
    SharedKitchenSnapshotStore.load().cookbooks
      .filter { $0.name.localizedCaseInsensitiveContains(string) }
      .map { WidgetCookbookEntity(id: $0.id.uuidString, name: $0.name) }
  }
}

struct CookbookWidgetConfiguration: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Choose a cookbook"
  static var description = IntentDescription("Open one of your Apron Buddy cookbooks.")

  @Parameter(title: "Cookbook") var cookbook: WidgetCookbookEntity?
}

private struct CookbookWidgetEntry: TimelineEntry {
  var date: Date
  var cookbook: SharedCookbookSummary?
}

private struct CookbookWidgetProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> CookbookWidgetEntry {
    CookbookWidgetEntry(date: .now, cookbook: SharedCookbookSummary(id: UUID(), name: "Family favorites", recipeNames: ["Sunday tomato rigatoni", "Lemon herb chicken"]))
  }

  func snapshot(for configuration: CookbookWidgetConfiguration, in context: Context) async -> CookbookWidgetEntry {
    entry(for: configuration)
  }

  func timeline(for configuration: CookbookWidgetConfiguration, in context: Context) async -> Timeline<CookbookWidgetEntry> {
    Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(60 * 60)))
  }

  private func entry(for configuration: CookbookWidgetConfiguration) -> CookbookWidgetEntry {
    let snapshot = SharedKitchenSnapshotStore.load()
    let cookbook = snapshot.cookbooks.first { $0.id.uuidString == configuration.cookbook?.id }
    return CookbookWidgetEntry(date: .now, cookbook: cookbook)
  }
}

struct CookbookWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "ApronBuddyCookbookWidget", intent: CookbookWidgetConfiguration.self, provider: CookbookWidgetProvider()) { entry in
      CookbookWidgetView(cookbook: entry.cookbook)
    }
    .configurationDisplayName("Cookbook")
    .description("Open a cookbook and see a few recipes from it.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct KitchenWidgetEntry: TimelineEntry {
  var date: Date
  var snapshot: SharedKitchenSnapshot
}

private enum KitchenWidgetKind {
  case todayRecipe
  case overview
  case groceries
}

private struct KitchenWidgetProvider: TimelineProvider {
  var kind: KitchenWidgetKind

  func placeholder(in context: Context) -> KitchenWidgetEntry {
    KitchenWidgetEntry(date: .now, snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (KitchenWidgetEntry) -> Void) {
    completion(KitchenWidgetEntry(date: .now, snapshot: SharedKitchenSnapshotStore.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<KitchenWidgetEntry>) -> Void) {
    let entry = KitchenWidgetEntry(date: .now, snapshot: SharedKitchenSnapshotStore.load())
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60))))
  }
}

struct TodayMealWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "ApronBuddyTodayMealWidget", provider: KitchenWidgetProvider(kind: .todayRecipe)) { entry in
      TodayMealWidgetView(snapshot: entry.snapshot)
    }
    .configurationDisplayName("Today’s meal")
    .description("Open the recipe planned for today.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct MealPlanOverviewWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "ApronBuddyMealPlanWidget", provider: KitchenWidgetProvider(kind: .overview)) { entry in
      MealPlanOverviewWidgetView(snapshot: entry.snapshot)
    }
    .configurationDisplayName("Meal plan overview")
    .description("See the upcoming meals in your current plan.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

struct GroceryListWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "ApronBuddyGroceryWidget", provider: KitchenWidgetProvider(kind: .groceries)) { entry in
      GroceryListWidgetView(snapshot: entry.snapshot)
    }
    .configurationDisplayName("Grocery list")
    .description("See unchecked items from your current meal plan.")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}

private struct CookbookWidgetView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var cookbook: SharedCookbookSummary?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Cookbook", systemImage: "books.vertical.fill")
        .font(.caption.weight(.bold))
        .foregroundStyle(WidgetPalette.olive)
      if let cookbook {
        Text(cookbook.name)
          .font(.headline.weight(.semibold))
          .lineLimit(2)
        ForEach(cookbook.recipeNames.prefix(dynamicTypeSize.isAccessibilitySize ? 1 : 2), id: \.self) { name in
          Text(name)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
        Link("Open cookbook", destination: WidgetDeepLink.cookbook(cookbook.id))
          .font(.caption.weight(.semibold))
          .foregroundStyle(WidgetPalette.olive)
      } else {
        Text("Choose a cookbook in widget settings.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
    }
    .padding()
    .containerBackground(WidgetPalette.paper, for: .widget)
  }
}

private struct TodayMealWidgetView: View {
  var snapshot: SharedKitchenSnapshot

  private var todayEntry: SharedMealPlanEntry? {
    let entries = snapshot.mealPlan?.entries.filter {
      !$0.isSkipped && $0.recipeID != nil && Calendar.current.isDateInToday($0.date)
    } ?? []
    return entries.first { $0.meal == "Dinner" } ?? entries.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("Today’s meal", systemImage: "sun.max.fill")
        .font(.caption.weight(.bold))
        .foregroundStyle(WidgetPalette.olive)
      if let todayEntry, let id = todayEntry.recipeID {
        Text(todayEntry.recipeName)
          .font(.title3.weight(.semibold))
          .lineLimit(3)
          .foregroundStyle(WidgetPalette.ink)
        Text(todayEntry.meal)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Link("Open recipe", destination: WidgetDeepLink.recipe(id))
          .font(.caption.weight(.semibold))
          .foregroundStyle(WidgetPalette.olive)
      } else {
        Text("No recipe planned for today")
          .font(.headline)
          .foregroundStyle(WidgetPalette.ink)
        Spacer(minLength: 0)
        Link("Open meal plans", destination: WidgetDeepLink.mealPlans)
          .font(.caption.weight(.semibold))
          .foregroundStyle(WidgetPalette.olive)
      }
    }
    .padding()
    .containerBackground(WidgetPalette.paper, for: .widget)
  }
}

private struct MealPlanOverviewWidgetView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var snapshot: SharedKitchenSnapshot

  private var upcomingEntries: [SharedMealPlanEntry] {
    (snapshot.mealPlan?.entries ?? [])
      .filter { !$0.isSkipped && !$0.recipeName.isEmpty && $0.date >= Calendar.current.startOfDay(for: .now) }
      .sorted { $0.date < $1.date }
      .prefix(dynamicTypeSize.isAccessibilitySize ? 2 : 4)
      .map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(snapshot.mealPlan?.title ?? "Meal plan")
        .font(.headline.weight(.semibold))
        .foregroundStyle(WidgetPalette.ink)
        .lineLimit(2)
      if upcomingEntries.isEmpty {
        Text("Create a plan to see your upcoming meals here.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      } else {
        ForEach(upcomingEntries) { entry in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date.formatted(.dateTime.weekday(.abbreviated)))
              .font(.caption.weight(.bold))
              .foregroundStyle(WidgetPalette.olive)
              .frame(width: 34, alignment: .leading)
            Text(entry.recipeName)
              .font(.caption)
              .foregroundStyle(WidgetPalette.ink)
              .lineLimit(2)
            Spacer(minLength: 0)
          }
          .accessibilityElement(children: .combine)
        }
      }
      if let plan = snapshot.mealPlan {
        Link("Open plan", destination: WidgetDeepLink.mealPlan(plan.id))
          .font(.caption.weight(.semibold))
          .foregroundStyle(WidgetPalette.olive)
      }
    }
    .padding()
    .containerBackground(WidgetPalette.paper, for: .widget)
  }
}

private struct GroceryListWidgetView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var snapshot: SharedKitchenSnapshot

  private var uncheckedItems: [SharedGroceryItem] {
    (snapshot.mealPlan?.groceries ?? [])
      .filter { !$0.isChecked }
      .prefix(dynamicTypeSize.isAccessibilitySize ? 3 : 5)
      .map { $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Grocery list", systemImage: "cart.fill")
        .font(.caption.weight(.bold))
        .foregroundStyle(WidgetPalette.olive)
      if uncheckedItems.isEmpty {
        Text("Your grocery list is clear.")
          .font(.headline)
          .foregroundStyle(WidgetPalette.ink)
        Spacer(minLength: 0)
      } else {
        ForEach(uncheckedItems) { item in
          HStack(spacing: 7) {
            Image(systemName: "circle")
              .font(.caption2)
              .foregroundStyle(WidgetPalette.olive)
              .accessibilityHidden(true)
            Text(item.displayText)
              .font(.caption)
              .foregroundStyle(WidgetPalette.ink)
              .lineLimit(2)
            Spacer(minLength: 0)
          }
          .accessibilityElement(children: .combine)
        }
      }
      if let plan = snapshot.mealPlan {
        Link("Open grocery list", destination: WidgetDeepLink.groceries(plan.id))
          .font(.caption.weight(.semibold))
          .foregroundStyle(WidgetPalette.olive)
      }
    }
    .padding()
    .containerBackground(WidgetPalette.paper, for: .widget)
  }
}

private enum WidgetDeepLink {
  static var mealPlans: URL { URL(string: "apronbuddy://mealplans")! }
  static func recipe(_ id: UUID) -> URL { URL(string: "apronbuddy://recipe/\(id.uuidString)")! }
  static func cookbook(_ id: UUID) -> URL { URL(string: "apronbuddy://cookbook/\(id.uuidString)")! }
  static func mealPlan(_ id: UUID) -> URL { URL(string: "apronbuddy://mealplan/\(id.uuidString)")! }
  static func groceries(_ id: UUID) -> URL { URL(string: "apronbuddy://groceries/\(id.uuidString)")! }
}

private enum WidgetPalette {
  static let paper = Color(red: 0.96, green: 0.95, blue: 0.90)
  static let ink = Color(red: 0.16, green: 0.19, blue: 0.15)
  static let olive = Color(red: 0.28, green: 0.39, blue: 0.25)
}
