import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private enum AppDestination: String, CaseIterable, Identifiable {
  case today
  case recipes
  case cookbooks
  case favorites
  case mealPlans
  case sharedWithMe
  case search

  static let sidebarSections = allCases.filter {
    #if os(iOS)
    $0 != .search && $0 != .sharedWithMe
    #else
    $0 != .search
    #endif
  }

  var id: String { rawValue }
  var title: String {
    switch self {
    case .today: "Today"
    case .recipes: "My recipes"
    case .cookbooks: "Cookbooks"
    case .favorites: "Favorites"
    case .mealPlans: "Meal plans"
    case .sharedWithMe: "Shared with me"
    case .search: "Search"
    }
  }
  var symbol: String {
    switch self {
    case .today: "sun.max"
    case .recipes: "book.closed"
    case .cookbooks: "books.vertical"
    case .favorites: "heart"
    case .mealPlans: "calendar"
    case .sharedWithMe: "person.2"
    case .search: "magnifyingglass"
    }
  }
}

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
  @Query(sort: \Cookbook.createdAt, order: .forward) private var cookbooks: [Cookbook]
  @Query(sort: \MealPlan.startDate, order: .reverse) private var mealPlans: [MealPlan]
  @AppStorage("mise.hasSeededSampleRecipes") private var hasSeededSampleRecipes = false
  @State private var destination: AppDestination = .today
  @State private var sidebarSelection: AppDestination? = .today
  @State private var selectedRecipe: Recipe?
  @State private var editsFeaturedCookingDate: Recipe?
  @State private var selectedCookbook: Cookbook?
  @State private var isImportPresented = false
  @State private var pendingImport: SharedImportPayload?
  @State private var openPlanID: UUID?
  @State private var shouldOpenGroceries = false
  #if os(iOS)
  @State private var recipesPath: [AppDestination] = []
  @State private var cooking = CookingSessionStore.shared
  @State private var isCookingPresented = false
  @State private var opensCookingAfterDismissal = false
  @State private var recipeSearchText = ""
  @State private var isRecipeSearchPresented = false
  #endif
  @State private var searchText = ""
  @State private var cloudSyncStatus = "Checking iCloud…"
  @State private var cloudSyncError: String?
  @State private var isCloudStatusPresented = false
  @State private var selectedCategory = "All"
  @State private var selectedGoodFor: RecipeGoodFor?
  @State private var minimumRating = 0
  @State private var favoritesOnly = false

  private func selectDestination(_ requested: AppDestination) {
    #if os(iOS)
    let value: AppDestination = requested == .sharedWithMe ? .recipes : requested
    if requested == .sharedWithMe {
      recipesPath = [.sharedWithMe]
    }
    #else
    let value = requested
    #endif
    if value != .mealPlans || destination == value {
      openPlanID = nil
      shouldOpenGroceries = false
    }
    destination = value
    if value != .search { sidebarSelection = value }
    #if os(iOS)
    isRecipeSearchPresented = value == .search && isPhoneLayout
    #endif
  }

  private var visibleRecipes: [Recipe] {
    var values = switch destination {
    case .today, .recipes: recipes
    case .cookbooks: recipes
    case .favorites: recipes.filter(\.isFavorite)
    case .mealPlans: recipes
    case .sharedWithMe: recipes.filter(\.isSharedRecipeCopy)
    case .search: recipes
    }
    if destination == .recipes {
      if favoritesOnly { values = values.filter(\.isFavorite) }
      if selectedCategory != "All" {
        values = values.filter { $0.category == selectedCategory }
      }
      if let selectedGoodFor {
        values = values.filter { $0.goodFor.contains(selectedGoodFor) }
      }
      if minimumRating > 0 {
        values = values.filter { $0.rating >= minimumRating }
      }
    }
    return isPhoneLayout ? values : matchingRecipes(values, query: searchText)
  }

  private func matchingRecipes(_ recipes: [Recipe], query: String) -> [Recipe] {
    guard !query.isEmpty else { return recipes }
    return recipes.filter { recipe in
      recipe.name.localizedCaseInsensitiveContains(query)
        || recipe.category.localizedCaseInsensitiveContains(query)
        || recipe.summary.localizedCaseInsensitiveContains(query)
        || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }
  }

  private var isPhoneLayout: Bool {
    #if os(iOS)
    horizontalSizeClass == .compact
    #else
    false
    #endif
  }

  #if os(iOS)
  @ViewBuilder
  private var phoneNavigation: some View {
    if #available(iOS 26.1, *) {
      phoneTabs
        .tabViewBottomAccessory(isEnabled: cooking.session != nil) { cookingAccessory }
        .tabBarMinimizeBehavior(.never)
    } else {
      phoneTabs
        .tabViewBottomAccessory { cookingAccessory }
        .tabBarMinimizeBehavior(.never)
    }
  }

  private var phoneTabs: some View {
    TabView(selection: phoneTabSelection) {
      Tab("Today", systemImage: AppDestination.today.symbol, value: .today) {
        NavigationStack {
          todayView
            .toolbar { CloudStatusToolbar(status: cloudSyncStatus, action: checkCloudStatus) }
        }
      }

      Tab("Recipes", systemImage: AppDestination.recipes.symbol, value: .recipes) {
        recipesNavigation
      }

      Tab("Books", systemImage: AppDestination.cookbooks.symbol, value: .cookbooks) {
        CookbooksView(recipes: recipes, cloudSyncStatus: cloudSyncStatus, onCloudSyncAction: checkCloudStatus)
      }

      Tab("Plans", systemImage: AppDestination.mealPlans.symbol, value: .mealPlans) {
        MealPlansView(
          recipes: recipes,
          searchText: "",
          openPlanID: openPlanID,
          openGroceries: shouldOpenGroceries,
          cloudSyncStatus: cloudSyncStatus,
          onCloudSyncAction: checkCloudStatus
        )
      }

      Tab("Search", systemImage: AppDestination.search.symbol, value: .search, role: recipeSearchRole) {
        NavigationStack {
          recipeSearchContent(query: recipeSearchText)
        }
        .searchable(
          text: $recipeSearchText,
          isPresented: $isRecipeSearchPresented,
          placement: .navigationBarDrawer(displayMode: .always),
          prompt: "Recipe name or ingredient"
        )
      }
    }
  }

  @ViewBuilder
  private var cookingAccessory: some View {
    if let session = cooking.session {
      CookingAccessory(session: session, open: cooking.requestPresentation)
    }
  }

  private func openCooking() {
    if selectedRecipe != nil || selectedCookbook != nil {
      opensCookingAfterDismissal = true
      selectedRecipe = nil
      selectedCookbook = nil
    } else {
      isCookingPresented = true
    }
  }
  #endif

  private func presentCookingAfterDismissal() {
    #if os(iOS)
    if opensCookingAfterDismissal {
      opensCookingAfterDismissal = false
      isCookingPresented = cooking.session != nil
    }
    #endif
  }

  #if os(iOS)
  private var recipeSearchRole: TabRole {
    if #available(iOS 27.0, *) {
      return .prominent
    }
    return .search
  }

  private var phoneTabSelection: Binding<AppDestination> {
    Binding(
      get: { destination == .favorites ? .recipes : destination },
      set: { selectDestination($0) }
    )
  }

  private var recipesNavigation: some View {
    NavigationStack(path: $recipesPath) {
      recipeLibrary
        .toolbar {
          if isPhoneLayout {
            CloudStatusToolbar(status: cloudSyncStatus, action: checkCloudStatus)
          }
        }
        .navigationDestination(for: AppDestination.self) { item in
          if item == .sharedWithMe {
            SharedWithMeView(
              recipes: recipes,
              cookbooks: cookbooks,
              wrapsNavigationStack: false,
              cloudSyncStatus: isPhoneLayout ? cloudSyncStatus : nil,
              onCloudSyncAction: checkCloudStatus
            )
          }
        }
    }
  }
  #endif

  private func recipeSearchContent(query: String) -> some View {
    let results = matchingRecipes(recipes, query: query)
    return Group {
      if results.isEmpty {
        ContentUnavailableView(
          query.isEmpty ? "No recipes yet" : "No matching recipes",
          systemImage: "magnifyingglass",
          description: Text(query.isEmpty ? "Import a recipe to start searching your kitchen." : "Try a different recipe name or ingredient.")
        )
      } else {
        List {
          ForEach(results) { recipe in
            Button {
              selectedRecipe = recipe
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "fork.knife")
                  .foregroundStyle(Color.miseOlive)
                  .frame(width: 38, height: 38)
                  .background(Color.miseSage, in: RoundedRectangle(cornerRadius: 11))
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(Color.miseInk)
                  Text(recipe.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if recipe.isFavorite {
                  Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Favorite")
                }
              }
              .padding(.vertical, 3)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.miseSurface)
          }
        }
        .scrollContentBackground(.hidden)
        .background(Color.misePaper)
      }
    }
    .navigationTitle("Search")
    .toolbar { CloudStatusToolbar(status: cloudSyncStatus, action: checkCloudStatus) }
  }

  private func checkCloudStatus() {
    isCloudStatusPresented = true
    Task { await refreshCloudSync() }
  }

  private var recipeCategories: [String] {
    Array(Set(recipes.map(\.category))).sorted()
  }

  private var cloudSyncMessage: String {
    if cloudSyncStatus == "Sign in to iCloud to sync" {
      return "Your recipes stay here until this device is signed in to iCloud."
    }
    if cloudSyncStatus == "iCloud sync is on" {
      return "Recipes and cookbooks sync with your iCloud account."
    }
    return "Open Settings to check your iCloud connection and Siri options."
  }

  private var cloudSyncNotice: some View {
    Button {
      isCloudStatusPresented = true
      Task { await refreshCloudSync() }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: cloudSyncStatus == "iCloud sync is on" ? "checkmark.icloud" : "icloud.slash")
          .font(.title3)
          .foregroundStyle(Color.miseOlive)
          .frame(width: 42, height: 42)
          .background(Color.miseSage, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(cloudSyncStatus)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.miseInk)
          Text(cloudSyncMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .padding(13)
      .background(Color.miseSurface, in: RoundedRectangle(cornerRadius: 16))
      .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Settings and iCloud sync status. \(cloudSyncStatus). \(cloudSyncMessage)")
    .accessibilityHint("Opens Settings with Siri controls and iCloud sync details.")
  }

  var body: some View {
    Group {
      #if os(iOS)
      if isPhoneLayout {
        phoneNavigation
      } else {
        splitNavigation
          .safeAreaInset(edge: .bottom, spacing: 0) {
            if cooking.session != nil {
              cookingAccessory
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
          }
      }
      #else
      splitNavigation
      #endif
    }
    .sheet(isPresented: $isImportPresented, onDismiss: {
      pendingImport = nil
      DispatchQueue.main.async { receiveSharedImports() }
      Task { await refreshCloudSync() }
    }) {
      ImportRecipeView(importItem: pendingImport)
        .frame(minWidth: 360, minHeight: 520)
    }
    .sheet(item: $selectedRecipe, onDismiss: presentCookingAfterDismissal) { recipe in
      RecipeDetailView(recipe: recipe)
    }
    .sheet(item: $editsFeaturedCookingDate) { recipe in
      RecipeCookingDateEditor(recipe: recipe)
    }
    .sheet(item: $selectedCookbook, onDismiss: presentCookingAfterDismissal) { cookbook in
      NavigationStack {
        CookbookDetailView(cookbook: cookbook, recipes: recipes)
      }
    }
    #if os(iOS)
    .sheet(isPresented: $isCookingPresented) {
      CookingSheet(cooking: cooking) { recipeID in
        let fetch = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeID })
        if let recipe = try modelContext.fetch(fetch).first {
          try recipe.saveLastCooked(.now, in: modelContext)
        }
      }
        .presentationDetents([.large])
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
    }
    .onChange(of: cooking.presentationRequest) { openCooking() }
    .task { await cooking.observeTimers() }
    #endif
    .sheet(isPresented: $isCloudStatusPresented) {
      CloudSyncStatusView(status: cloudSyncStatus) {
        Task { await refreshCloudSync() }
      }
    }
    .task {
      if !hasSeededSampleRecipes {
        RecipeSamples.insertIfNeeded(into: modelContext, existing: recipes)
        hasSeededSampleRecipes = true
      }
      try? modelContext.save()
      WatchCookingBridge.activate()
      receiveSharedImports()
      await refreshCloudSync()
    }
    .task(id: WidgetSnapshotPublisher.changeKey(recipes: recipes, cookbooks: cookbooks, plans: mealPlans)) {
      WidgetSnapshotPublisher.publish(recipes: recipes, cookbooks: cookbooks, plans: mealPlans)
    }
    .task(id: RecipeDeduplicator.changeKey(for: recipes)) {
      guard !recipes.isEmpty else { return }
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      RecipeDeduplicator.removeExactDuplicates(in: modelContext)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        receiveSharedImports()
        Task { await refreshCloudSync() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .miseCloudKitShareAccepted)) { notification in
      guard let metadata = notification.object as? CKShare.Metadata else { return }
      Task {
        do {
          if metadata.hierarchicalRootRecordID?.recordName == CloudKitCookbookStore.recipeRootRecordName {
            try await SharedRecipeImporter.accept(metadata, in: modelContext)
            selectDestination(.sharedWithMe)
          } else {
            try await SharedCookbookImporter.accept(metadata, in: modelContext)
            selectDestination(.sharedWithMe)
          }
          cloudSyncError = nil
          await refreshCloudSync()
        } catch {
          cloudSyncError = error.localizedDescription
        }
      }
    }
    .onOpenURL(perform: handleOpenURL)
    .alert("iCloud sharing", isPresented: Binding(
      get: { cloudSyncError != nil },
      set: { if !$0 { cloudSyncError = nil } }
    )) {
      Button("OK", role: .cancel) { cloudSyncError = nil }
    } message: {
      Text(cloudSyncError ?? "Try again when you’re online.")
    }
  }

  private var splitNavigation: some View {
    NavigationSplitView {
      List(selection: Binding<AppDestination?>(
        get: { sidebarSelection },
        set: { newValue in
          sidebarSelection = newValue
          if let newValue { selectDestination(newValue) }
        }
      )) {
        Section("YOUR KITCHEN") {
          ForEach(AppDestination.sidebarSections) { item in
            Label(item.title, systemImage: item.symbol)
              .tag(item)
          }
        }

        Section {
          Button {
            isImportPresented = true
          } label: {
            Label("Import a recipe", systemImage: "arrow.down.document")
          }
          .buttonStyle(.plain)
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Apron Buddy")
    } detail: {
      Group {
        switch destination {
        case .today:
          todayView
        case .recipes:
          #if os(iOS)
          recipesNavigation
          #else
          recipeLibrary
          #endif
        case .cookbooks:
          CookbooksView(recipes: recipes)
        case .mealPlans:
          MealPlansView(recipes: recipes, searchText: searchText, openPlanID: openPlanID, openGroceries: shouldOpenGroceries)
        case .favorites:
          recipeLibrary
        case .sharedWithMe:
          SharedWithMeView(recipes: recipes, cookbooks: cookbooks)
        case .search:
          recipeSearchContent(query: searchText)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.misePaper)
      .searchable(text: $searchText, prompt: destination == .mealPlans ? "Find a meal plan" : "Find a recipe")
    }
    .navigationSplitViewStyle(.balanced)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          isCloudStatusPresented = true
          Task { await refreshCloudSync() }
        } label: {
          Image(systemName: cloudSyncStatus == "iCloud sync is on" ? "checkmark.icloud" : "icloud")
            .foregroundStyle(cloudSyncStatus == "iCloud sync is on" ? Color.miseOlive : Color.secondary)
        }
        .help("Open Settings and view iCloud sync status")
        .accessibilityLabel("Settings and iCloud sync status: \(cloudSyncStatus)")
      }
    }
  }

  private func handleOpenURL(_ url: URL) {
    guard url.scheme == "apronbuddy" else {
      pendingImport = SharedImportPayload(sourceURL: url.absoluteString, title: url.host ?? "Shared link")
      isImportPresented = true
      return
    }
    let identifier = url.pathComponents.dropFirst().first
    switch url.host {
    #if os(iOS)
    case "cooking":
      if identifier.flatMap(UUID.init(uuidString:)) == cooking.session?.id, cooking.session != nil {
        cooking.requestPresentation()
      }
    #endif
    case "recipe":
      guard let identifier, let id = UUID(uuidString: identifier),
            let recipe = recipes.first(where: { $0.id == id }) else { return }
      selectedRecipe = recipe
    case "cookbook":
      guard let identifier, let id = UUID(uuidString: identifier) else { return }
      selectDestination(.cookbooks)
      selectedCookbook = cookbooks.first { $0.id == id }
    case "mealplan", "groceries":
      guard let identifier, let id = UUID(uuidString: identifier) else { return }
      selectDestination(.mealPlans)
      openPlanID = id
      shouldOpenGroceries = url.host == "groceries"
    case "mealplans":
      selectDestination(.mealPlans)
    case "shared":
      selectDestination(.sharedWithMe)
    default:
      pendingImport = SharedImportPayload(sourceURL: url.absoluteString, title: url.host ?? "Shared link")
      isImportPresented = true
    }
  }

  private var todayView: some View {
    let featured = RecipeRotation.ranked(recipes, on: .now).first
    return ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
              .font(.caption.weight(.semibold))
              .tracking(1.3)
              .foregroundStyle(Color.miseOlive)
            Text("A little inspiration")
              .font(.largeTitle.weight(.semibold))
              .foregroundStyle(Color.miseInk)
          }
          Spacer(minLength: 8)
          Button {
            isImportPresented = true
          } label: {
            Label("Import", systemImage: "plus")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 16)
              .padding(.vertical, 11)
              .background(Color.miseOlive, in: Capsule())
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
        }

        if cloudSyncStatus != "iCloud sync is on" {
          cloudSyncNotice
        }

        if let featured {
          Button {
            selectedRecipe = featured
          } label: {
            FeaturedRecipeCard(recipe: featured)
              .accessibilityHidden(true)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Tonight’s pick, \(featured.name), \(featured.prepMinutes + featured.cookMinutes) minutes, \(featured.category)")
          .accessibilityHint("Opens the recipe details.")
          .contextMenu {
            Button("Edit last cooked…", systemImage: "calendar") { editsFeaturedCookingDate = featured }
          }
        }

        VStack(alignment: .leading, spacing: 15) {
          HStack(alignment: .firstTextBaseline) {
            Text("Made for your table")
              .font(.title2.weight(.semibold))
              .foregroundStyle(Color.miseInk)
            Spacer()
            Button("See all") { selectDestination(.recipes) }
              .font(.subheadline.weight(.medium))
              .foregroundStyle(Color.miseOlive)
          }

          LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], alignment: .leading, spacing: 16) {
            ForEach(Array(recipes.lazy.filter { $0.id != featured?.id }.prefix(4))) { recipe in
              RecipeTile(recipe: recipe, cookbooks: cookbooks, allRecipes: recipes) {
                selectedRecipe = recipe
              }
            }
          }
        }

        HStack(spacing: 14) {
          Image(systemName: "sparkles")
            .font(.title3)
            .foregroundStyle(Color.miseOlive)
            .frame(width: 44, height: 44)
            .background(Color.miseSage, in: Circle())
          VStack(alignment: .leading, spacing: 3) {
            Text("Found a recipe you love?")
              .font(.subheadline.weight(.semibold))
            Text("Share a link, PDF, or document and Apron Buddy will tidy it up.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Button { isImportPresented = true } label: {
            Image(systemName: "arrow.right")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.miseOlive)
          }
          .accessibilityLabel("Import a recipe")
        }
        .padding(16)
        .background(Color.miseSurface, in: RoundedRectangle(cornerRadius: 18))
      }
      .padding(.horizontal, 26)
      .padding(.top, 26)
      .padding(.bottom, 36)
      .frame(maxWidth: 1040, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(Color.misePaper)
    .navigationTitle("Today")
  }

  private var recipeLibrary: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 5) {
            Text(destination == .favorites ? "Saved for later" : "Your collection")
              .font(.largeTitle.weight(.semibold))
              .foregroundStyle(Color.miseInk)
            Text("\(visibleRecipes.count) recipes, ready when you are")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button { isImportPresented = true } label: {
            Label("Add recipe", systemImage: "plus")
              .font(.subheadline.weight(.semibold))
          }
          .buttonStyle(.borderedProminent)
          .tint(Color.miseOlive)
        }

        if cloudSyncStatus != "iCloud sync is on" {
          cloudSyncNotice
        }

        if destination == .recipes {
          #if os(iOS)
          NavigationLink(value: AppDestination.sharedWithMe) {
            HStack(spacing: 10) {
              Label("Shared with me", systemImage: AppDestination.sharedWithMe.symbol)
                .font(.subheadline.weight(.semibold))
              Spacer()
              Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            }
            .foregroundStyle(Color.miseOlive)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.miseSurface, in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
          #endif

          HStack {
            Button {
              favoritesOnly.toggle()
            } label: {
              Label(favoritesOnly ? "Favorites" : "All recipes", systemImage: favoritesOnly ? "heart.fill" : "heart")
                .font(.caption.weight(.semibold))
                .foregroundStyle(favoritesOnly ? Color.white : Color.miseOlive)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(favoritesOnly ? Color.miseOlive : Color.miseSage.opacity(0.55), in: Capsule())
            }
            .buttonStyle(.plain)
            RecipeFilterMenu(
              categories: recipeCategories,
              category: $selectedCategory,
              goodFor: $selectedGoodFor,
              minimumRating: $minimumRating
            )
            Spacer()
            Text("\(visibleRecipes.count) shown")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if visibleRecipes.isEmpty {
          if recipes.isEmpty {
            ContentUnavailableView("No recipes yet", systemImage: "book.closed", description: Text("Import a recipe from a link or document to start your collection."))
              .frame(maxWidth: .infinity, minHeight: 320)
          } else {
            ContentUnavailableView("No matching recipes", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try another search or clear one of the filters."))
              .frame(maxWidth: .infinity, minHeight: 320)
          }
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 18)], alignment: .leading, spacing: 18) {
            ForEach(visibleRecipes) { recipe in
              RecipeTile(recipe: recipe, cookbooks: cookbooks, allRecipes: recipes) {
                selectedRecipe = recipe
              }
            }
          }
        }
      }
      .padding(26)
      .frame(maxWidth: 1040, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(Color.misePaper)
    .navigationTitle(destination.title)
  }

  private func receiveSharedImports() {
    guard pendingImport == nil, let next = SharedImportQueue.takeNextPending() else { return }
    pendingImport = next
    isImportPresented = true
  }

  @MainActor
  private func refreshCloudSync() async {
    cloudSyncStatus = await CloudKitCookbookStore.shared.accountStatusMessage()
    guard cloudSyncStatus == "iCloud sync is on" else { return }

    do {
      for cookbook in cookbooks where cookbook.isCloudShared {
        try await SharedCookbookImporter.refresh(cookbook, recipes: recipes, in: modelContext)
      }
      try? modelContext.save()
    } catch {
      cloudSyncStatus = "iCloud sync needs attention"
    }
  }
}

private struct FeaturedRecipeCard: View {
  var recipe: Recipe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      RecipeArtwork(recipe: recipe, height: 235)
      VStack(alignment: .leading, spacing: 9) {
        Text("TONIGHT’S PICK")
          .font(.caption.weight(.bold))
          .tracking(1.2)
          .foregroundStyle(Color.miseOlive)
        Text(recipe.name)
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
          .foregroundStyle(Color.miseInk)
          .fixedSize(horizontal: false, vertical: true)
        Label("\(recipe.category) · \(recipe.prepMinutes + recipe.cookMinutes) min", systemImage: "clock")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.miseInk)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color.miseSurface)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .overlay(alignment: .topTrailing) {
      Image(systemName: "arrow.up.right")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.miseInk)
        .frame(width: 44, height: 44)
        .background(.regularMaterial, in: Circle())
        .padding(17)
    }
  }
}

private struct RecipeTile: View {
  @Environment(\.modelContext) private var modelContext
  @State private var editsLastCooked = false
  var recipe: Recipe
  var cookbooks: [Cookbook]
  var allRecipes: [Recipe]
  var onOpen: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 10) {
          RecipeArtwork(recipe: recipe, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
          VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
              .font(.headline.weight(.semibold))
              .foregroundStyle(Color.miseInk)
              .lineLimit(2)
            Text("\(recipe.category) · \(recipe.prepMinutes + recipe.cookMinutes) min")
              .font(.subheadline)
              .foregroundStyle(Color.miseInk)
            if recipe.rating > 0 {
              Label("\(recipe.rating) out of 5 stars", systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.miseOlive)
            }
            if let lastCooked = recipe.lastCooked {
              Text("Last cooked \(lastCooked.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(Color.miseInk)
            }
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.miseSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(recipe.name), \(recipe.category), \(recipe.prepMinutes + recipe.cookMinutes) minutes\(recipe.isFavorite ? ", favorite" : "")")
      .accessibilityValue(recipe.lastCooked.map { "Last cooked \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
      .accessibilityHint("Opens the recipe ingredients and cooking instructions.")

      HStack(spacing: 8) {
        if recipe.isFavorite {
          Image(systemName: "heart.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.miseCoral)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .accessibilityHidden(true)
        }
        Menu {
          Button("Edit last cooked…", systemImage: "calendar") { editsLastCooked = true }
          if cookbooks.isEmpty {
            Button("Create a cookbook first", systemImage: "books.vertical") { }
              .disabled(true)
          } else {
            Section("Add to cookbook") {
              ForEach(cookbooks) { cookbook in
                let isIncluded = recipe.cookbookIDs.contains(cookbook.id)
                Button {
                  recipe.add(to: cookbook.id)
                  saveAndSync(cookbook)
                } label: {
                  Label(cookbook.name, systemImage: isIncluded ? "checkmark" : "books.vertical")
                }
                .disabled(isIncluded)
              }
            }
            Section("Copy to cookbook") {
              ForEach(cookbooks) { cookbook in
                Button(cookbook.name, systemImage: "document.on.document") {
                  duplicate(recipe, into: cookbook)
                }
              }
            }
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.miseOlive)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .contentShape(Circle())
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .buttonStyle(.plain)
        .accessibilityLabel("Options for \(recipe.name)")
      }
      .padding(9)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .sheet(isPresented: $editsLastCooked) {
      RecipeCookingDateEditor(recipe: recipe)
    }
  }

  private func duplicate(_ source: Recipe, into cookbook: Cookbook) {
    let copy = Recipe(
      name: "\(source.name) (Copy)",
      summary: source.summary,
      userNotes: source.userNotes,
      category: source.category,
      servings: source.servings,
      caloriesPerServing: source.caloriesPerServing,
      prepMinutes: source.prepMinutes,
      cookMinutes: source.cookMinutes,
      difficulty: source.difficulty,
      ingredients: source.ingredients,
      steps: source.steps,
      sourceURL: source.sourceURL,
      sourceName: source.sourceName,
      isFavorite: source.isFavorite,
      photoData: source.photoData,
      cookbookIDs: [cookbook.id],
      goodFor: source.goodFor,
      rating: source.rating
    )
    modelContext.insert(copy)
    saveAndSync(cookbook)
  }

  private func saveAndSync(_ cookbook: Cookbook) {
    try? modelContext.save()
    guard cookbook.isCloudShared else { return }
    let currentRecipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? allRecipes
    Task { @MainActor in
      try? await SharedCookbookImporter.refresh(cookbook, recipes: currentRecipes, in: modelContext)
    }
  }
}

struct RecipeArtwork: View {
  var recipe: Recipe
  var height: CGFloat
  var accessibilityDescription: String? = nil

  private var storedImage: Image? {
    guard let data = recipe.photoData else { return nil }
    #if canImport(UIKit)
    if let image = UIImage(data: data) { return Image(uiImage: image) }
    #elseif canImport(AppKit)
    if let image = NSImage(data: data) { return Image(nsImage: image) }
    #endif
    return nil
  }

  var body: some View {
    GeometryReader { geometry in
      Group {
        if let storedImage {
          storedImage
            .resizable()
            .scaledToFill()
        } else {
          ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
              .fill(.white.opacity(0.2))
              .frame(width: height * 0.9, height: height * 0.9)
              .offset(x: height * 0.34, y: -height * 0.2)
            Circle()
              .stroke(.white.opacity(0.26), lineWidth: 1)
              .frame(width: height * 0.72, height: height * 0.72)
              .offset(x: -height * 0.36, y: height * 0.3)
            Image(systemName: artworkSymbol)
              .font(.system(size: height * 0.38, weight: .light))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.white.opacity(0.88))
              .shadow(color: .black.opacity(0.14), radius: 12, y: 8)
          }
          .clipped()
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipped()
    }
    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    .frame(height: height)
    .clipped()
    .accessibilityLabel(accessibilityDescription ?? "")
    .accessibilityHidden(accessibilityDescription == nil)
  }

  private var artworkSymbol: String {
    switch recipe.category {
    case "Breakfast": "sun.max.fill"
    case "Pasta": "leaf.fill"
    case "Vegetarian": "carrot.fill"
    default: "fork.knife"
    }
  }

  private var gradientColors: [Color] {
    switch recipe.category {
    case "Breakfast": [Color(red: 0.79, green: 0.56, blue: 0.30), Color(red: 0.93, green: 0.72, blue: 0.40)]
    case "Pasta": [Color(red: 0.66, green: 0.27, blue: 0.20), Color(red: 0.85, green: 0.48, blue: 0.29)]
    case "Vegetarian": [Color(red: 0.31, green: 0.43, blue: 0.30), Color(red: 0.61, green: 0.68, blue: 0.44)]
    default: [Color(red: 0.43, green: 0.43, blue: 0.29), Color(red: 0.77, green: 0.58, blue: 0.38)]
    }
  }
}

extension Color {
  static var misePaper: Color { adaptive(light: (0.96, 0.95, 0.91), dark: (0.12, 0.14, 0.12)) }
  static var miseSurface: Color { adaptive(light: (0.99, 0.98, 0.95), dark: (0.18, 0.20, 0.17)) }
  static var miseInk: Color { adaptive(light: (0.16, 0.18, 0.14), dark: (0.92, 0.93, 0.88)) }
  static var miseOlive: Color { adaptive(light: (0.29, 0.38, 0.25), dark: (0.64, 0.74, 0.51)) }
  static var miseSage: Color { adaptive(light: (0.87, 0.90, 0.81), dark: (0.27, 0.32, 0.24)) }
  static var miseCoral: Color { adaptive(light: (0.75, 0.29, 0.21), dark: (0.95, 0.50, 0.38)) }

  private static func adaptive(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat)
  ) -> Color {
    #if canImport(UIKit)
    Color(uiColor: UIColor { traits in
      let values = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
    })
    #elseif canImport(AppKit)
    Color(nsColor: NSColor(name: nil) { appearance in
      let values = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      return NSColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
    })
    #else
    Color(red: light.0, green: light.1, blue: light.2)
    #endif
  }
}
