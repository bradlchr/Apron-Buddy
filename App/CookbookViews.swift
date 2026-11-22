import CloudKit
import SwiftData
import SwiftUI

struct CookbooksView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Cookbook.createdAt, order: .forward) private var cookbooks: [Cookbook]
  var recipes: [Recipe]
  var wrapsNavigationStack = true
  var cloudSyncStatus: String? = nil
  var onCloudSyncAction: (() -> Void)? = nil
  @State private var isCreatingCookbook = false

  var body: some View {
    Group {
      if wrapsNavigationStack {
        NavigationStack { content }
      } else {
        content
      }
    }
  }

  private var content: some View {
      Group {
        if cookbooks.isEmpty {
          ContentUnavailableView {
            Label("Create your first cookbook", systemImage: "books.vertical")
          } description: {
            Text("Organize recipes into collections you can share with family and friends.")
          } actions: {
            Button("New cookbook", systemImage: "plus") { isCreatingCookbook = true }
              .buttonStyle(.borderedProminent)
              .tint(Color.miseOlive)
          }
        } else {
          List {
            ForEach(cookbooks) { cookbook in
              NavigationLink {
                CookbookDetailView(cookbook: cookbook, recipes: recipes)
              } label: {
                CookbookRow(cookbook: cookbook, recipeCount: recipes.filter { $0.cookbookIDs.contains(cookbook.id) }.count)
              }
              .listRowBackground(Color.miseSurface)
            }
            .onDelete(perform: deleteCookbooks)
          }
          .scrollContentBackground(.hidden)
          .background(Color.misePaper)
        }
      }
      .background(Color.misePaper)
      .navigationTitle("Cookbooks")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("New cookbook", systemImage: "plus") { isCreatingCookbook = true }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Create cookbook")
        }
        if let cloudSyncStatus, let onCloudSyncAction {
          CloudStatusToolbar(status: cloudSyncStatus, action: onCloudSyncAction)
        }
      }
      .sheet(isPresented: $isCreatingCookbook) {
        CookbookEditorView()
      }
  }

  private func deleteCookbooks(at offsets: IndexSet) {
    for index in offsets {
      let cookbook = cookbooks[index]
      for recipe in recipes where recipe.cookbookIDs.contains(cookbook.id) {
        recipe.remove(from: cookbook.id)
      }
      modelContext.delete(cookbook)
    }
    try? modelContext.save()
  }
}

private struct CookbookRow: View {
  var cookbook: Cookbook
  var recipeCount: Int

  var body: some View {
    HStack(spacing: 15) {
      ZStack {
        RoundedRectangle(cornerRadius: 13).fill(Color.miseOlive.gradient)
        Image(systemName: cookbook.isCloudShared ? "person.2.fill" : "book.closed.fill")
          .font(.title3.weight(.medium))
          .foregroundStyle(.white)
          .accessibilityHidden(true)
      }
      .frame(width: 52, height: 58)

      VStack(alignment: .leading, spacing: 4) {
        Text(cookbook.name)
          .font(.headline)
          .foregroundStyle(Color.miseInk)
        Text(cookbook.detail.isEmpty ? "\(recipeCount) recipes" : cookbook.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        if cookbook.isCloudShared {
          Label("Shared", systemImage: "person.2")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.miseOlive)
        }
      }
      Spacer()
      Text("\(recipeCount)")
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(recipeCount) recipes")
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

private struct CookbookEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var name = ""
  @State private var detail = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("Cookbook") {
          TextField("Name", text: $name)
          TextField("Description", text: $detail, axis: .vertical)
            .lineLimit(2...4)
        }
      }
      .navigationTitle("New cookbook")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            let cookbook = Cookbook(name: name.trimmingCharacters(in: .whitespacesAndNewlines), detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
            modelContext.insert(cookbook)
            try? modelContext.save()
            dismiss()
          }
          .fontWeight(.semibold)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 340, minHeight: 270)
  }
}

struct CookbookDetailView: View {
  @Environment(\.modelContext) private var modelContext
  var cookbook: Cookbook
  var recipes: [Recipe]
  @State private var isManagingRecipes = false
  @State private var shareSnapshot: CookbookShareSnapshot?

  private var cookbookRecipes: [Recipe] {
    recipes.filter { $0.cookbookIDs.contains(cookbook.id) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  var body: some View {
    List {
      Section {
        if cookbookRecipes.isEmpty {
          ContentUnavailableView("No recipes in this cookbook", systemImage: "book.closed", description: Text("Add existing recipes or make copies for this collection."))
            .listRowBackground(Color.clear)
        } else {
          ForEach(cookbookRecipes) { recipe in
            NavigationLink {
              RecipeDetailView(recipe: recipe)
            } label: {
              CookbookRecipeRow(recipe: recipe)
            }
            .listRowBackground(Color.miseSurface)
            .contextMenu {
              Button("Remove from cookbook", systemImage: "minus.circle") {
                recipe.remove(from: cookbook.id)
                saveAndSync()
              }
              Button("Copy in this cookbook", systemImage: "document.on.document") {
                duplicate(recipe, into: cookbook)
              }
            }
          }
        }
      } header: {
        Text("\(cookbookRecipes.count) recipes")
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.misePaper)
    .navigationTitle(cookbook.name)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button("Add recipes", systemImage: "plus") { isManagingRecipes = true }
          .accessibilityLabel("Add or copy recipes")
        Button("Share cookbook", systemImage: "person.crop.circle.badge.plus") {
          cookbook.isCloudShared = true
          cookbook.cloudZoneName = CloudKitCookbookStore.zoneID(for: cookbook.id).zoneName
          cookbook.cloudOwnerName = CKCurrentUserDefaultName
          try? modelContext.save()
          shareSnapshot = CloudKitCookbookStore.snapshot(cookbook: cookbook, recipes: recipes)
        }
        .accessibilityLabel("Share cookbook with CloudKit")
      }
    }
    .sheet(isPresented: $isManagingRecipes) {
      CookbookRecipePicker(cookbook: cookbook, recipes: recipes)
    }
    .sheet(item: $shareSnapshot) { snapshot in
      NavigationStack {
        VStack(spacing: 18) {
          Image(systemName: "person.2.crop.square.stack")
            .font(.system(size: 42))
            .foregroundStyle(Color.miseOlive)
            .frame(width: 86, height: 86)
            .background(Color.miseSage, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityHidden(true)
          Text("Share \(snapshot.name)")
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color.miseInk)
          Text("Apron Buddy will prepare a private iCloud cookbook. Choose people and whether they can make changes in Apple’s sharing sheet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
          ShareLink(item: snapshot, preview: SharePreview(snapshot.name)) {
            Label("Invite people", systemImage: "person.crop.circle.badge.plus")
              .frame(maxWidth: 360)
              .frame(height: 48)
          }
          .buttonStyle(.borderedProminent)
          .tint(Color.miseOlive)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.misePaper)
        .navigationTitle("Share cookbook")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { shareSnapshot = nil }
          }
        }
      }
      .frame(minWidth: 360, minHeight: 400)
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
    saveAndSync()
  }

  private func saveAndSync() {
    try? modelContext.save()
    guard cookbook.isCloudShared else { return }
    let currentRecipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? recipes
    Task { @MainActor in
      try? await SharedCookbookImporter.refresh(cookbook, recipes: currentRecipes, in: modelContext)
    }
  }
}

private struct CookbookRecipeRow: View {
  var recipe: Recipe

  var body: some View {
    HStack(spacing: 13) {
      RecipeArtwork(recipe: recipe, height: 66)
        .frame(width: 74)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 4) {
        Text(recipe.name)
          .font(.headline)
          .foregroundStyle(Color.miseInk)
          .lineLimit(2)
        Text("\(recipe.category) · \(recipe.prepMinutes + recipe.cookMinutes) min")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if recipe.rating > 0 {
        Label("\(recipe.rating) out of 5 stars", systemImage: "star.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.miseOlive)
          .labelStyle(.titleAndIcon)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct CookbookRecipePicker: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  var cookbook: Cookbook
  var recipes: [Recipe]
  @State private var selectedIDs: Set<UUID> = []
  @State private var searchText = ""
  @State private var categoryFilter = "All"
  @State private var goodForFilter: RecipeGoodFor?
  @State private var minimumRating = 0

  private var categories: [String] {
    Array(Set(recipes.map(\.category))).sorted()
  }

  private var filteredRecipes: [Recipe] {
    recipes.filter { recipe in
      let matchesSearch = searchText.isEmpty
        || recipe.name.localizedCaseInsensitiveContains(searchText)
        || recipe.category.localizedCaseInsensitiveContains(searchText)
        || recipe.summary.localizedCaseInsensitiveContains(searchText)
        || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
      let matchesCategory = categoryFilter == "All" || recipe.category == categoryFilter
      let matchesGoodFor = goodForFilter == nil || recipe.goodFor.contains(goodForFilter!)
      let matchesRating = minimumRating == 0 || recipe.rating >= minimumRating
      return matchesSearch && matchesCategory && matchesGoodFor && matchesRating
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if recipes.isEmpty {
          ContentUnavailableView("No recipes yet", systemImage: "fork.knife", description: Text("Import a recipe before adding it to a cookbook."))
        } else if filteredRecipes.isEmpty {
          ContentUnavailableView("No matching recipes", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try another search or adjust the filters."))
        } else {
          ForEach(filteredRecipes) { recipe in
            Button {
              if selectedIDs.contains(recipe.id) { selectedIDs.remove(recipe.id) }
              else { selectedIDs.insert(recipe.id) }
            } label: {
              HStack(spacing: 12) {
                Image(systemName: selectedIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                  .font(.title3)
                  .foregroundStyle(selectedIDs.contains(recipe.id) ? Color.miseOlive : Color.secondary)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(recipe.name).font(.headline).foregroundStyle(Color.miseInk)
                  Text(recipe.category).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if recipe.cookbookIDs.contains(cookbook.id) {
                  Text("In cookbook").font(.caption).foregroundStyle(.secondary)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(recipe.name), \(recipe.category)")
            .accessibilityAddTraits(selectedIDs.contains(recipe.id) ? .isSelected : [])
            .accessibilityHint("Double-tap to select or deselect this recipe.")
          }
        }
      }
      .navigationTitle("Choose recipes")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .primaryAction) {
          RecipeFilterMenu(
            categories: categories,
            category: $categoryFilter,
            goodFor: $goodForFilter,
            minimumRating: $minimumRating
          )
        }
      }
      .searchable(text: $searchText, prompt: "Find recipes")
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 12) {
          Button("Add selected · \(selectedIDs.count)", systemImage: "plus") { addSelected() }
            .frame(maxWidth: .infinity, minHeight: 46)
            .buttonStyle(.borderedProminent)
            .tint(Color.miseOlive)
            .accessibilityLabel("Add \(selectedIDs.count) selected recipes")
          Button("Copy selected · \(selectedIDs.count)", systemImage: "document.on.document") { copySelected() }
            .frame(maxWidth: .infinity, minHeight: 46)
            .buttonStyle(.bordered)
            .tint(Color.miseOlive)
            .accessibilityLabel("Copy \(selectedIDs.count) selected recipes")
        }
        .padding()
        .background(.regularMaterial)
        .disabled(selectedIDs.isEmpty)
      }
    }
    .frame(minWidth: 360, minHeight: 500)
  }

  private func addSelected() {
    for recipe in recipes where selectedIDs.contains(recipe.id) {
      recipe.add(to: cookbook.id)
    }
    saveAndSync()
    dismiss()
  }

  private func copySelected() {
    for recipe in recipes where selectedIDs.contains(recipe.id) {
      let copy = Recipe(
        name: "\(recipe.name) (Copy)",
        summary: recipe.summary,
        userNotes: recipe.userNotes,
        category: recipe.category,
        servings: recipe.servings,
        caloriesPerServing: recipe.caloriesPerServing,
        prepMinutes: recipe.prepMinutes,
        cookMinutes: recipe.cookMinutes,
        difficulty: recipe.difficulty,
        ingredients: recipe.ingredients,
        steps: recipe.steps,
        sourceURL: recipe.sourceURL,
        sourceName: recipe.sourceName,
        isFavorite: recipe.isFavorite,
        photoData: recipe.photoData,
        cookbookIDs: [cookbook.id],
        goodFor: recipe.goodFor,
        rating: recipe.rating
      )
      modelContext.insert(copy)
    }
    saveAndSync()
    dismiss()
  }

  private func saveAndSync() {
    try? modelContext.save()
    guard cookbook.isCloudShared else { return }
    let currentRecipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? recipes
    Task { @MainActor in
      try? await SharedCookbookImporter.refresh(cookbook, recipes: currentRecipes, in: modelContext)
    }
  }
}
