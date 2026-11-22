import SwiftUI

struct SharedWithMeView: View {
  var recipes: [Recipe]
  var cookbooks: [Cookbook]
  var wrapsNavigationStack = true
  var cloudSyncStatus: String? = nil
  var onCloudSyncAction: (() -> Void)? = nil

  private var sharedRecipes: [Recipe] {
    recipes.filter(\.isSharedRecipeCopy)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private var sharedCookbooks: [Cookbook] {
    cookbooks.filter(\.isSharedCopy)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

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
        if sharedRecipes.isEmpty && sharedCookbooks.isEmpty {
          ContentUnavailableView(
            "Nothing shared with you yet",
            systemImage: "person.2",
            description: Text("Recipes and cookbooks someone shares with your iCloud account will appear here.")
          )
        } else {
          List {
            if !sharedRecipes.isEmpty {
              Section("Recipes") {
                ForEach(sharedRecipes) { recipe in
                  NavigationLink {
                    RecipeDetailView(recipe: recipe)
                  } label: {
                    SharedRecipeRow(recipe: recipe)
                  }
                  .listRowBackground(Color.miseSurface)
                }
              }
            }

            if !sharedCookbooks.isEmpty {
              Section("Cookbooks") {
                ForEach(sharedCookbooks) { cookbook in
                  NavigationLink {
                    CookbookDetailView(cookbook: cookbook, recipes: recipes)
                  } label: {
                    HStack(spacing: 12) {
                      Image(systemName: "books.vertical.fill")
                        .foregroundStyle(Color.miseOlive)
                        .frame(width: 38, height: 38)
                        .background(Color.miseSage, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                      VStack(alignment: .leading, spacing: 3) {
                        Text(cookbook.name)
                          .font(.headline)
                          .foregroundStyle(Color.miseInk)
                        Text("\(recipes.filter { $0.cookbookIDs.contains(cookbook.id) }.count) recipes")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                  .listRowBackground(Color.miseSurface)
                }
              }
            }
          }
          .scrollContentBackground(.hidden)
          .background(Color.misePaper)
        }
      }
      .background(Color.misePaper)
      .navigationTitle("Shared with me")
      .toolbar {
        if let cloudSyncStatus, let onCloudSyncAction {
          CloudStatusToolbar(status: cloudSyncStatus, action: onCloudSyncAction)
        }
      }
  }
}

private struct SharedRecipeRow: View {
  var recipe: Recipe

  var body: some View {
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
      Image(systemName: "person.crop.circle.badge.checkmark")
        .font(.caption)
        .foregroundStyle(Color.miseOlive)
        .accessibilityLabel("Shared with you")
    }
    .padding(.vertical, 3)
  }
}

struct RecipeQuickSearchView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var recipes: [Recipe]
  var onSelect: (Recipe) -> Void

  private var matches: [Recipe] {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return recipes }
    return recipes.filter { recipe in
      recipe.name.localizedCaseInsensitiveContains(query)
        || recipe.category.localizedCaseInsensitiveContains(query)
        || recipe.summary.localizedCaseInsensitiveContains(query)
        || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if matches.isEmpty {
          ContentUnavailableView("No matching recipes", systemImage: "magnifyingglass", description: Text("Try another search."))
        } else {
          ForEach(matches) { recipe in
            Button {
              onSelect(recipe)
              dismiss()
            } label: {
              SharedRecipeRow(recipe: recipe)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.miseSurface)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.misePaper)
      .navigationTitle("Search recipes")
      .searchable(text: $query, prompt: "Recipe name or ingredient")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
