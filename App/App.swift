import CloudKit
import SwiftUI
import SwiftData

@main
struct AppDefinition: App {
  @State private var modelContainer: ModelContainer?
  @State private var cloudStoreError: String?
  @State private var household = HouseholdLibraryManager()
  @Environment(\.scenePhase) private var scenePhase
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
      Group {
        if let activeContainer = household.isActive ? household.container : modelContainer {
          ContentView()
            .id(household.activeID ?? "personal")
            .modelContainer(activeContainer)
        } else {
          ContentUnavailableView(
            "Apron Buddy couldn’t open the recipe library",
            systemImage: "icloud.slash",
            description: Text(cloudStoreError ?? "Check your iCloud account and try opening Apron Buddy again.")
          )
          .padding(32)
        }
      }
      .environment(\.householdLibrary, household)
      .task {
        household.personalContext = modelContainer?.mainContext
        household.restore()
        if let metadata = CloudKitShareArrival.takePendingHousehold() {
          await household.accept(metadata)
        }
        await ChefTips.listen()
      }
      .task(id: librarySyncKey) {
        guard household.isActive, scenePhase == .active else { return }
        while !Task.isCancelled {
          await household.synchronize()
          try? await Task.sleep(for: .seconds(5))
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .miseCloudKitShareAccepted)) { notification in
        guard let metadata = notification.object as? CKShare.Metadata else { return }
        if HouseholdMembership.matches(metadata) {
          if let accepted = CloudKitShareArrival.takePendingHousehold() {
            Task { await household.accept(accepted) }
          }
        } else if household.isActive, let context = modelContainer?.mainContext {
          Task {
            do {
              if metadata.hierarchicalRootRecordID?.recordName == CloudKitCookbookStore.recipeRootRecordName {
                try await SharedRecipeImporter.accept(metadata, in: context)
              } else {
                try await SharedCookbookImporter.accept(metadata, in: context)
              }
              household.switchLibrary(active: false)
            } catch {
              // This invitation belongs to the personal library.
              household.recordError(error)
            }
          }
        }
      }
    }
#if os(macOS)
    Settings {
      AppSettingsRootView()
        .environment(\.householdLibrary, household)
    }
#endif
  }
  private var librarySyncKey: String {
    "\(household.activeID ?? "personal")-\(scenePhase)"
  }

}
