import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import WatchConnectivity
#endif

struct RecipeDetailView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.householdLibrary) private var householdLibrary
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Query private var cookbooks: [Cookbook]
  @Query private var allRecipes: [Recipe]
  @State private var servings: Int
  @State private var usesMetric = false
  #if !os(iOS)
  @State private var isCooking = false
  #endif
  @State private var isEditing = false
  @State private var pdfDocument: RecipePDFDocument?
  @State private var exportsPDF = false
  @State private var showsPDFError = false
  @State private var isConfirmingDelete = false
  @State private var isDeleteErrorPresented = false
  @State private var deleteErrorTitle = "Couldn't delete recipe"
  @State private var deleteErrorMessage = ""
  @State private var dismissAfterDeleteError = false
  @State private var isShareOptionsPresented = false
  var recipe: Recipe

  init(recipe: Recipe) {
    self.recipe = recipe
    _servings = State(initialValue: recipe.servings)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        RecipeArtwork(
          recipe: recipe,
          height: 350,
          accessibilityDescription: recipe.photoData == nil ? nil : "Finished dish photo for \(recipe.name)"
        )
          .clipShape(RoundedRectangle(cornerRadius: 25))
          .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
              Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Close recipe")
            .buttonStyle(.plain)
            .padding(14)
          }
          .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
              Menu {
                Button("Print…", systemImage: "printer") {
                  showsPDFError = !RecipePrinting.print(recipe)
                }
                Button("Export PDF…", systemImage: "square.and.arrow.up") {
                  guard let data = RecipePrinting.pdf(for: recipe) else {
                    showsPDFError = true
                    return
                  }
                  pdfDocument = RecipePDFDocument(data: data)
                  exportsPDF = true
                }
              } label: {
                Image(systemName: "printer")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(palette.ink)
                  .frame(width: 44, height: 44)
                  .background(.regularMaterial, in: Circle())
              }
              .accessibilityLabel("Print or export recipe")
              .buttonStyle(.plain)

              Button {
                isEditing = true
              } label: {
                Label("Edit", systemImage: "pencil")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(palette.ink)
                  .padding(.horizontal, 14)
                  .padding(.vertical, 10)
                  .frame(minHeight: 44)
                  .background(.regularMaterial, in: Capsule())
              }
              .accessibilityLabel("Edit recipe")
              .buttonStyle(.plain)
              .disabled(recipe.isSharedRecipeCopy && !recipe.canEditSharedRecipe)

              Button(role: .destructive) {
                isConfirmingDelete = true
              } label: {
                Image(systemName: "trash")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(Color.red)
                  .frame(width: 44, height: 44)
                  .background(.regularMaterial, in: Circle())
              }
              .accessibilityLabel("Delete recipe")
              .buttonStyle(.plain)
            }
            .padding(14)
          }

        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Text(recipe.category.uppercased())
              .font(.caption.weight(.bold))
              .tracking(1.2)
              .foregroundStyle(palette.accent)
            Circle().fill(palette.accent.opacity(0.5)).frame(width: 4, height: 4)
            Text(recipe.difficulty)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
          Text(recipe.name)
            .font(.system(.largeTitle, design: .serif, weight: .semibold))
            .foregroundStyle(palette.ink)
          Text(recipe.summary)
            .font(.body)
            .foregroundStyle(.secondary)
          Group {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(alignment: .leading, spacing: 10) {
                Label("\(recipe.prepMinutes) min prep", systemImage: "clock")
                Label("\(recipe.cookMinutes) min cook", systemImage: "flame")
              }
            } else {
              HStack(spacing: 22) {
                Label("\(recipe.prepMinutes) min prep", systemImage: "clock")
                Label("\(recipe.cookMinutes) min cook", systemImage: "flame")
              }
            }
          }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(palette.accent)
          .padding(.top, 4)

          VStack(alignment: .leading, spacing: 10) {
            Text("Your rating")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(palette.ink)
            HStack(spacing: 8) {
              ForEach(1...5, id: \.self) { value in
                Button {
                  recipe.rating = recipe.rating == value ? 0 : value
                  saveRecipeChanges()
                } label: {
                  Image(systemName: value <= recipe.rating ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(value <= recipe.rating ? palette.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(recipe.isSharedRecipeCopy && !recipe.canEditSharedRecipe)
                .accessibilityLabel("Rate \(value) out of 5 stars")
                .accessibilityAddTraits(value == recipe.rating ? .isSelected : [])
              }
              if recipe.rating > 0 {
                Button("Clear") {
                  recipe.rating = 0
                  saveRecipeChanges()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(recipe.isSharedRecipeCopy && !recipe.canEditSharedRecipe)
              }
              Spacer()
              if recipe.isFavorite {
                Label("Favorite", systemImage: "heart.fill")
                  .font(.caption.weight(.medium))
                  .foregroundStyle(palette.warning)
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("Good for")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(palette.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
              ForEach(RecipeGoodFor.allCases) { occasion in
                Button {
                  if recipe.goodFor.contains(occasion) {
                    recipe.goodFor.removeAll { $0 == occasion }
                  } else {
                    recipe.goodFor.append(occasion)
                  }
                  saveRecipeChanges()
                } label: {
                  Label(occasion.title, systemImage: occasion.symbol)
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(recipe.goodFor.contains(occasion) ? Color.white : palette.accent)
                    .background(
                      recipe.goodFor.contains(occasion) ? palette.accent : palette.softAccent.opacity(0.55),
                      in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(recipe.isSharedRecipeCopy && !recipe.canEditSharedRecipe)
                .accessibilityAddTraits(recipe.goodFor.contains(occasion) ? .isSelected : [])
                .accessibilityHint("Double-tap to change whether this recipe is good for \(occasion.title.lowercased()).")
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 18) {
          Group {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(alignment: .leading, spacing: 10) {
                Text("Ingredients")
                  .font(.title2.weight(.semibold))
                  .foregroundStyle(palette.ink)
                Text("Adjusted for your table")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                Picker("Measurement units", selection: $usesMetric) {
                  Text("US").tag(false)
                  Text("Metric").tag(true)
                }
                .pickerStyle(.segmented)
              }
            } else {
              HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                  Text("Ingredients")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.ink)
                  Text("Adjusted for your table")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Measurement units", selection: $usesMetric) {
                  Text("US").tag(false)
                  Text("Metric").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 126)
              }
            }
          }

          HStack(spacing: 14) {
            Text("Servings")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
            Spacer()
            Button { servings = max(1, servings - 1) } label: {
              Image(systemName: "minus")
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
                .background(palette.paper, in: Circle())
            }
            .accessibilityLabel("Decrease servings")
            Text("\(servings)")
              .font(.subheadline.weight(.semibold).monospacedDigit())
              .frame(minWidth: 18)
              .accessibilityLabel("\(servings) servings")
            Button { servings = min(24, servings + 1) } label: {
              Image(systemName: "plus")
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
                .background(palette.paper, in: Circle())
            }
            .accessibilityLabel("Increase servings")
          }
          .buttonStyle(.plain)

          ForEach(RecipeIngredientSection.group(recipe.ingredients)) { section in
            if !section.title.isEmpty {
              Text(section.title)
                .font(.headline)
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)
            }
            ForEach(section.ingredients) { ingredient in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle")
                  .font(.caption2)
                  .foregroundStyle(palette.accent)
                  .accessibilityHidden(true)
                Text(IngredientFormatter.format(ingredient, from: recipe.servings, to: servings, metric: usesMetric))
                  .font(.body)
                  .foregroundStyle(palette.ink)
                Spacer(minLength: 4)
                if !ingredient.note.isEmpty {
                  Text(ingredient.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }
              }
              .accessibilityElement(children: .combine)
              .padding(.vertical, 5)
            }
          }
        }
        .padding(20)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20))

        VStack(alignment: .leading, spacing: 14) {
          Text("Method")
            .font(.title2.weight(.semibold))
            .foregroundStyle(palette.ink)
          ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
            HStack(alignment: .top, spacing: 14) {
              Text(String(format: "%02d", index + 1))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(palette.accent)
                .frame(width: 34, height: 34)
                .background(palette.softAccent, in: Circle())
              VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                  .font(.headline.weight(.semibold))
                  .foregroundStyle(palette.ink)
                Text(step.detail)
                  .font(.body)
                  .foregroundStyle(.secondary)
                if step.timerMinutes > 0 {
                  Label("\(step.timerMinutes) minute timer", systemImage: "timer")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accent)
                    .padding(.top, 3)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Your notes")
            .font(.title2.weight(.semibold))
            .foregroundStyle(palette.ink)
          Text(recipe.userNotes.isEmpty ? "Tap Edit to add your substitutions, adjustments, or reminders." : recipe.userNotes)
            .font(.body)
            .foregroundStyle(recipe.userNotes.isEmpty ? Color.secondary : palette.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))

        if !recipe.sourceURL.isEmpty, let url = URL(string: recipe.sourceURL) {
          Link(destination: url) {
            Label("View original source", systemImage: "arrow.up.right")
              .font(.subheadline.weight(.medium))
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(palette.paper)
    .confirmationDialog("Delete \(recipe.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
      Button("Delete Recipe", role: .destructive, action: deleteRecipe)
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("This removes the recipe from your library and every cookbook.")
    }
    .alert(deleteErrorTitle, isPresented: $isDeleteErrorPresented) {
      Button(dismissAfterDeleteError ? "Done" : "OK") {
        if dismissAfterDeleteError { dismiss() }
        dismissAfterDeleteError = false
      }
    } message: {
      Text(deleteErrorMessage)
    }
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 12) {
        Button {
          recipe.isFavorite.toggle()
          saveRecipeChanges()
        } label: {
          Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
            .font(.title3)
            .foregroundStyle(recipe.isFavorite ? palette.warning : palette.accent)
            .frame(width: 52, height: 52)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityLabel(recipe.isFavorite ? "Remove from favorites" : "Add to favorites")
        .buttonStyle(.plain)
        .disabled(recipe.isSharedRecipeCopy && !recipe.canEditSharedRecipe)

        Button {
          recipe.isCloudSharedRecipe = true
          try? modelContext.save()
          isShareOptionsPresented = true
        } label: {
          Image(systemName: "square.and.arrow.up")
            .font(.title3)
            .foregroundStyle(palette.accent)
            .frame(width: 52, height: 52)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share recipe")

        Button {
          WatchCookingBridge.send(recipe: recipe, servings: servings)
          #if os(iOS)
          CookingSessionStore.shared.start(.init(
            id: UUID(),
            recipeID: recipe.id,
            libraryID: householdLibrary?.activeID,
            recipeName: recipe.name,
            servings: servings,
            steps: recipe.steps.map { .init(title: $0.title, instructions: $0.detail, timerMinutes: $0.timerMinutes) },
            ingredientMeasurements: IngredientFormatter.measurementLines(for: recipe, servings: servings, metric: usesMetric),
            usesMetricMeasurements: usesMetric
          ))
          #else
          isCooking = true
          #endif
        } label: {
          Label("Start cooking", systemImage: "play.fill")
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(recipe.steps.isEmpty)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(.regularMaterial)
    }
    .fileExporter(isPresented: $exportsPDF, document: pdfDocument, contentType: .pdf, defaultFilename: recipe.name) { result in
      if case .failure = result { showsPDFError = true }
      pdfDocument = nil
    }
    .alert("Couldn’t print or export this recipe", isPresented: $showsPDFError) {
      Button("OK", role: .cancel) {}
    }
    .sheet(isPresented: $isEditing) {
      RecipeEditorView(recipe: recipe) {
        saveRecipeChanges()
      }
    }
    #if !os(iOS)
    .sheet(isPresented: $isCooking) {
      CookingModeView(recipe: recipe, servings: servings, usesMetric: usesMetric) {
        try recipe.saveLastCooked(.now, in: modelContext)
      }
        .frame(minWidth: 340, minHeight: 450)
    }
    #endif
    .sheet(isPresented: $isShareOptionsPresented) {
      NavigationStack {
        VStack(spacing: 16) {
          Image(systemName: "person.crop.circle.badge.plus")
            .font(.system(size: 38))
            .foregroundStyle(palette.accent)
            .frame(width: 76, height: 76)
            .background(palette.softAccent, in: RoundedRectangle(cornerRadius: 22))
          Text("Share \(recipe.name)")
            .font(.title2.weight(.semibold))
            .foregroundStyle(palette.ink)
          Text("Invite someone with a private iCloud recipe share, or send a text copy.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

          ShareLink(item: SharedRecipeSnapshot(recipe), preview: SharePreview(recipe.name)) {
            Label("Share privately with iCloud", systemImage: "person.2.crop.circle.badge.plus")
              .frame(maxWidth: 420)
              .frame(height: 48)
          }
          .buttonStyle(.borderedProminent)
          .tint(palette.accent)

          ShareLink(item: shareText) {
            Label("Share as text", systemImage: "text.alignleft")
              .frame(maxWidth: 420)
              .frame(height: 44)
          }
          .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.paper)
        .navigationTitle("Share recipe")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { isShareOptionsPresented = false }
          }
        }
      }
      .frame(minWidth: 340, minHeight: 360)
    }
  }

  private var shareText: String {
    let ingredients = recipe.ingredients.map { "• \(IngredientFormatter.format($0, from: recipe.servings, to: servings, metric: usesMetric))" }.joined(separator: "\n")
    let steps = recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element.title)\n\($0.element.detail)" }.joined(separator: "\n\n")
    let notes = recipe.userNotes.isEmpty ? "" : "\n\nNotes\n\(recipe.userNotes)"
    return "\(recipe.name)\n\n\(recipe.summary)\(notes)\n\nIngredients\n\(ingredients)\n\nMethod\n\(steps)"
  }

  private func saveRecipeChanges() {
    try? modelContext.save()
    if recipe.isCloudSharedRecipe || recipe.isSharedRecipeCopy {
      Task {
        try? await CloudKitCookbookStore.shared.synchronizeRecipe(SharedRecipeSnapshot(recipe), recipe: recipe)
      }
    }
    let sharedBooks = cookbooks.filter { $0.isCloudShared && recipe.cookbookIDs.contains($0.id) }
    guard !sharedBooks.isEmpty else { return }
    Task { @MainActor in
      for cookbook in sharedBooks {
        try? await SharedCookbookImporter.refresh(cookbook, recipes: allRecipes, in: modelContext)
      }
    }
  }

  private func deleteRecipe() {
    if recipe.isSharedRecipeCopy {
      deleteErrorTitle = "Can't delete this recipe"
      deleteErrorMessage = "This recipe belongs to a share owned by someone else. Ask the owner to remove it."
      dismissAfterDeleteError = false
      isDeleteErrorPresented = true
      return
    }
    let assignedCookbooks = cookbooks.filter { recipe.cookbookIDs.contains($0.id) }
    if let readOnlyCookbook = assignedCookbooks.first(where: { $0.isSharedCopy && !$0.canEditSharedCopy }) {
      deleteErrorTitle = "Can't delete this recipe"
      deleteErrorMessage = "This recipe belongs to \(readOnlyCookbook.name), a read-only shared cookbook. Ask the owner to remove it."
      dismissAfterDeleteError = false
      isDeleteErrorPresented = true
      return
    }

    let deletedRecipeID = recipe.id
    let recipeName = recipe.name
    let wasCloudSharedRecipe = recipe.isCloudSharedRecipe
    for cookbook in assignedCookbooks {
      recipe.remove(from: cookbook.id)
    }
    modelContext.delete(recipe)

    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      deleteErrorTitle = "Couldn't delete recipe"
      deleteErrorMessage = "Apron Buddy couldn't save the deletion. Try again."
      dismissAfterDeleteError = false
      isDeleteErrorPresented = true
      return
    }

    Task { @MainActor in
      let remainingRecipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? allRecipes.filter { $0.id != deletedRecipeID }
      var failedCookbooks: [String] = []
      if wasCloudSharedRecipe {
        try? await CloudKitCookbookStore.shared.deleteRecipeShare(id: deletedRecipeID)
      }
      for cookbook in assignedCookbooks where cookbook.isCloudShared {
        do {
          try await SharedCookbookImporter.refresh(cookbook, recipes: remainingRecipes, in: modelContext)
        } catch {
          failedCookbooks.append(cookbook.name)
        }
      }

      guard !failedCookbooks.isEmpty else {
        dismiss()
        return
      }

      deleteErrorTitle = "Deleted on this device"
      deleteErrorMessage = "“\(recipeName)” was deleted here, but Apron Buddy couldn't update \(failedCookbooks.formatted(.list(type: .and))) in iCloud. It will try again after you close this screen."
      dismissAfterDeleteError = true
      isDeleteErrorPresented = true
    }
  }
}

enum IngredientFormatter {
  static func measurementLines(for recipe: Recipe, servings: Int, metric: Bool) -> [String] {
    RecipeIngredientSection.group(recipe.ingredients).flatMap { section in
      let ingredients = section.ingredients.map { format($0, from: recipe.servings, to: servings, metric: metric) }
      return section.title.isEmpty ? ingredients : [section.title + ":"] + ingredients
    }
  }

  static func format(_ ingredient: RecipeIngredient, from originalServings: Int, to servings: Int, metric: Bool) -> String {
    let ingredient = IngredientNormalization.clean(ingredient)
    guard ingredient.amount > 0 else { return ingredient.name }
    var amount = ingredient.amount * Double(servings) / Double(max(1, originalServings))
    var unit = ingredient.unit.lowercased()

    if metric {
      switch unit {
      case "cup", "cups": amount *= 240; unit = "ml"
      case "tbsp", "tablespoon", "tablespoons": amount *= 15; unit = "ml"
      case "tsp", "teaspoon", "teaspoons": amount *= 5; unit = "ml"
      case "oz", "ounce", "ounces": amount *= 28.35; unit = "g"
      case "lb", "lbs", "pound", "pounds": amount *= 453.6; unit = "g"
      default: break
      }
    }

    if unit == "cup" || unit == "cups" { unit = "cup" }
    if unit == "lb" || unit == "lbs" { unit = "lb" }
    let amountText = KitchenQuantity.format(amount)
    let unitText = unit.isEmpty ? "" : " \(KitchenQuantity.unitLabel(unit, amount: amount))"
    return "\(amountText)\(unitText) \(ingredient.name)"
  }
}

#if !os(iOS)
private struct CookingModeView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var currentStep = 0
  @State private var timerEnd: Date?
  @State private var showsIngredients = false
  @State private var measuredInstructions: [String] = []
  @State private var showsCompletionError = false
  var recipe: Recipe
  var servings: Int
  var usesMetric: Bool
  var recordCompletion: () throws -> Void

  private var step: RecipeStep? {
    guard recipe.steps.indices.contains(currentStep) else { return nil }
    return recipe.steps[currentStep]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("COOKING MODE")
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(palette.accent)
          Text(recipe.name)
            .font(.headline.weight(.semibold))
            .foregroundStyle(palette.ink)
            .lineLimit(2)
        }
        Spacer()
        Button("Ingredients", systemImage: "list.bullet") { showsIngredients = true }
          .labelStyle(.iconOnly)
          .popover(isPresented: $showsIngredients) {
            CookingIngredientsPeek(ingredients: IngredientFormatter.measurementLines(for: recipe, servings: servings, metric: usesMetric))
          }
        Button("Done") { dismiss() }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.accent)
          .frame(minWidth: 44, minHeight: 44)
      }

      ProgressView(value: Double(currentStep + 1), total: Double(max(1, recipe.steps.count)))
        .tint(palette.accent)
        .accessibilityHidden(true)
      Text("STEP \(currentStep + 1) OF \(max(1, recipe.steps.count)) · SERVES \(servings)")
        .font(.caption.weight(.bold))
        .tracking(1)
        .foregroundStyle(.secondary)

      if let step {
        VStack(alignment: .leading, spacing: 14) {
          Text(step.title)
            .font(.system(.largeTitle, design: .serif, weight: .semibold))
            .foregroundStyle(palette.ink)
            .accessibilityAddTraits(.isHeader)
          CookingInstructionText(instruction: measuredInstructions.indices.contains(currentStep) ? measuredInstructions[currentStep] : step.detail) { seconds in
            timerEnd = .now.addingTimeInterval(Double(seconds))
          }
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        if defaultTimerSeconds > 0 || timerEnd != nil {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
              timerStatus
              Spacer(minLength: 0)
              timerButton
            }
            VStack(alignment: .leading, spacing: 12) {
              timerStatus
              timerButton
                .frame(maxWidth: .infinity, minHeight: 44)
            }
          }
          .padding(16)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
        }
      }

      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: 12) {
            previousStepButton
            nextStepButton
          }
        } else {
          HStack(spacing: 12) {
            previousStepButton
            nextStepButton
          }
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(palette.accent)
    }
    .padding(24)
    .background(palette.paper)
    .task {
      let instructions = recipe.steps.map(\.detail)
      let ingredients = recipe.ingredients
      measuredInstructions = CookingStepMeasurements.baseline(ingredients: ingredients, steps: instructions, originalServings: recipe.servings, servings: servings, metric: usesMetric)
      if let enhanced = await CookingStepMeasurements.enhanced(ingredients: ingredients, steps: instructions, originalServings: recipe.servings, servings: servings, metric: usesMetric), !Task.isCancelled {
        measuredInstructions = enhanced
      }
    }
    .alert("Couldn’t save the last cooked date", isPresented: $showsCompletionError) {
      Button("OK", role: .cancel) { }
    }
  }

  private var timerStatus: some View {
    HStack(spacing: 14) {
      Image(systemName: "timer")
        .font(.title2)
        .foregroundStyle(palette.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Step timer")
          .font(.subheadline.weight(.semibold))
        if let timerEnd {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(timerEnd.timeIntervalSince(context.date)))
            Text(remaining == 0 ? "Timer finished" : remaining.formattedTime)
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(remaining == 0 ? palette.warning : .secondary)
          }
        } else {
          Text(Duration.seconds(defaultTimerSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var defaultTimerSeconds: Double {
    guard let step else { return 0 }
    return CookingTimeMention.matches(in: step.detail).first.map { Double($0.seconds) } ?? Double(step.timerMinutes) * 60
  }

  private var timerButton: some View {
    Button(timerEnd == nil ? "Start timer" : "Reset timer") {
      timerEnd = .now.addingTimeInterval(defaultTimerSeconds)
    }
    .buttonStyle(.bordered)
    .tint(palette.accent)
    .frame(minHeight: 44)
    .accessibilityHint(timerEnd == nil ? "Starts a timer for this cooking step." : "Starts the step timer over.")
  }

  private var previousStepButton: some View {
    Button {
      currentStep = max(0, currentStep - 1)
      timerEnd = nil
    } label: {
      Label("Previous", systemImage: "arrow.left")
        .frame(maxWidth: .infinity, minHeight: 50)
    }
    .buttonStyle(.bordered)
    .disabled(currentStep == 0)
  }

  private var nextStepButton: some View {
    Button {
      if currentStep + 1 < recipe.steps.count {
        currentStep += 1
        timerEnd = nil
      } else {
        do {
          try recordCompletion()
          dismiss()
        } catch {
          showsCompletionError = true
        }
      }
    } label: {
      Label(currentStep + 1 == recipe.steps.count ? "Finish" : "Next step", systemImage: currentStep + 1 == recipe.steps.count ? "checkmark" : "arrow.right")
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, minHeight: 50)
    }
    .buttonStyle(.borderedProminent)
    .tint(palette.strongAccent)
  }
}

private extension Int {
  var formattedTime: String {
    let minutes = self / 60
    let seconds = self % 60
    return "\(minutes):\(String(format: "%02d", seconds)) remaining"
  }
}

#endif

#if os(iOS)
enum WatchCookingBridge {
  static func activate() {
    guard WCSession.isSupported() else { return }
    WatchSessionActivationHandler.shared.activate()
  }

  static func send(recipe: Recipe, servings: Int) {
    guard WCSession.isSupported() else { return }
    let context: [String: Any] = [
      "recipeName": recipe.name,
      "servings": servings,
      "steps": recipe.steps.map { "\($0.title)\n\($0.detail)" },
      "timers": recipe.steps.map(\.timerMinutes)
    ]
    WatchSessionActivationHandler.shared.send(context)
  }
}

private final class WatchSessionActivationHandler: NSObject, WCSessionDelegate {
  static let shared = WatchSessionActivationHandler()
  private var pendingContext: [String: Any]?

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    if session.activationState != .activated { session.activate() }
  }

  func send(_ context: [String: Any]) {
    activate()
    pendingContext = context
    deliverPendingContextIfReady()
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    deliverPendingContextIfReady()
  }

  #if os(iOS)
  func sessionDidBecomeInactive(_ session: WCSession) { }
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
  #endif

  private func deliverPendingContextIfReady() {
    guard let pendingContext, WCSession.default.activationState == .activated else { return }
    try? WCSession.default.updateApplicationContext(pendingContext)
    self.pendingContext = nil
  }
}
#else
enum WatchCookingBridge {
  static func activate() { }
  static func send(recipe: Recipe, servings: Int) { }
}
#endif
