import SwiftUI
import SwiftData

@main
struct AppDefinition: App {
  @State private var modelContainer: ModelContainer?
  @State private var cloudStoreError: String?
#if os(iOS)
  @UIApplicationDelegateAdaptor(CloudKitShareAppDelegate.self) private var appDelegate
#elseif os(macOS)
  @NSApplicationDelegateAdaptor(CloudKitShareAppDelegate.self) private var appDelegate
#endif

  init() {
    let schema = Schema([Recipe.self, Cookbook.self, MealPlan.self])
    let cloudConfiguration = ModelConfiguration(
      "Mise",
      schema: schema,
      cloudKitDatabase: .private(CloudKitCookbookStore.containerIdentifier)
    )
    do {
      _modelContainer = State(initialValue: try ModelContainer(for: schema, configurations: [cloudConfiguration]))
      _cloudStoreError = State(initialValue: nil)
    } catch {
      _modelContainer = State(initialValue: nil)
      _cloudStoreError = State(initialValue: error.localizedDescription)
    }
  }

  var body: some Scene {
    WindowGroup {
      if let modelContainer {
        ContentView()
          .modelContainer(modelContainer)
      } else {
        ContentUnavailableView(
          "Apron Buddy couldn’t start iCloud storage",
          systemImage: "icloud.slash",
          description: Text(cloudStoreError ?? "Check your iCloud account and try opening Apron Buddy again.")
        )
        .padding(32)
      }
    }
#if os(macOS)
    Settings {
      AppSettingsRootView()
    }
#endif
  }
}
