import SwiftUI
import PhotosUI

struct RecipeEditorView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  var recipe: Recipe
  var onSave: () -> Void

  @State private var name: String
  @State private var summary: String
  @State private var category: String
  @State private var difficulty: String
  @State private var servings: Int
  @State private var caloriesPerServing: Int
  @State private var prepMinutes: Int
  @State private var cookMinutes: Int
  @State private var ingredients: [RecipeIngredient]
  @State private var steps: [RecipeStep]
  @State private var userNotes: String
  @State private var goodFor: Set<RecipeGoodFor>
  @State private var cleaning = false
  @State private var cleanupMessage: String?
  @State private var addsIngredientSection = false
  @State private var newSectionTitle = ""
  @State private var photoData: Data?
  @State private var selectedPhoto: PhotosPickerItem?
#if os(iOS)
  @State private var isCameraPresented = false
  @State private var isCameraUnavailablePresented = false
#endif

  init(recipe: Recipe, onSave: @escaping () -> Void) {
    self.recipe = recipe
    self.onSave = onSave
    _name = State(initialValue: recipe.name)
    _summary = State(initialValue: recipe.summary)
    _category = State(initialValue: recipe.category)
    _difficulty = State(initialValue: recipe.difficulty)
    _servings = State(initialValue: recipe.servings)
    _caloriesPerServing = State(initialValue: recipe.caloriesPerServing)
    _prepMinutes = State(initialValue: recipe.prepMinutes)
    _cookMinutes = State(initialValue: recipe.cookMinutes)
    _ingredients = State(initialValue: recipe.ingredients)
    _steps = State(initialValue: recipe.steps)
    _userNotes = State(initialValue: recipe.userNotes)
    _goodFor = State(initialValue: Set(recipe.goodFor))
    _photoData = State(initialValue: recipe.photoData)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Recipe") {
          TextField("Name", text: $name)
          TextField("Description", text: $summary, axis: .vertical)
            .lineLimit(2...5)
          TextField("Category", text: $category)
          TextField("Difficulty", text: $difficulty)
        }

        Section("Recipe cleanup") {
          Button("Clean up ingredients and steps", systemImage: "sparkles") {
            Task { await cleanUpDraft() }
          }
          .disabled(cleaning || (ingredients.isEmpty && steps.isEmpty))
          if cleaning { ProgressView("Cleaning up the recipe…") }
          if let cleanupMessage {
            Text(cleanupMessage).font(.footnote).foregroundStyle(.secondary)
          }
          Menu(goodFor.isEmpty ? "Occasion tags" : "\(goodFor.count) occasion tags") {
            ForEach(RecipeGoodFor.allCases) { tag in
              Toggle(tag.title, isOn: Binding(
                get: { goodFor.contains(tag) },
                set: { enabled in
                  if enabled { goodFor.insert(tag) } else { goodFor.remove(tag) }
                }
              ))
            }
          }
        }

        Section("Servings and timing") {
          Stepper("Serves \(servings)", value: $servings, in: 1...100)
          Stepper("Prep time · \(prepMinutes) min", value: $prepMinutes, in: 0...600, step: 5)
          Stepper("Cook time · \(cookMinutes) min", value: $cookMinutes, in: 0...1200, step: 5)
        }

        Section("Nutrition (optional)") {
          TextField("Calories per serving (0 if unknown)", value: $caloriesPerServing, format: .number)
#if os(iOS)
            .keyboardType(.numberPad)
#endif
        }

        Section("Finished dish photo") {
          if let photoData, let image = PlatformImage.data(photoData) {
            GeometryReader { geometry in
              image
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: 190)
                .clipped()
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 14))
              .accessibilityLabel("Finished dish photo")
          } else {
            Label("Add a photo of the finished dish", systemImage: "photo")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, minHeight: 120)
          }

          HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
              Label(photoData == nil ? "Choose photo" : "Change photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)

#if os(iOS)
            Button {
              guard CameraPhotoCaptureView.isAvailable else {
                isCameraUnavailablePresented = true
                return
              }
              isCameraPresented = true
            } label: {
              Label(photoData == nil ? "Take photo" : "Retake photo", systemImage: "camera")
            }
            .buttonStyle(.bordered)
#endif
          }

          if photoData != nil {
            Button("Remove photo", systemImage: "trash", role: .destructive) {
              photoData = nil
              selectedPhoto = nil
            }
          }
        }

        ForEach(RecipeIngredientSection.group(ingredients)) { section in
          Section(section.title.isEmpty ? "Ingredients" : section.title) {
            ForEach(section.ingredients.map(\.id), id: \.self) { id in
              if let index = ingredients.firstIndex(where: { $0.id == id }) {
                EditableIngredientFields(ingredient: $ingredients[index]) {
                  ingredients.removeAll { $0.id == id }
                }
              }
            }
            Button("Add ingredient", systemImage: "plus") {
              ingredients.append(RecipeIngredient(amount: 1, unit: "", name: "", section: section.title.isEmpty ? nil : section.title))
            }
          }
          .listRowBackground(palette.surface)
        }
        Section {
          if ingredients.isEmpty {
            Button("Add ingredient", systemImage: "plus") {
              ingredients.append(RecipeIngredient(amount: 1, unit: "", name: ""))
            }
          }
          Button("Add ingredient section", systemImage: "rectangle.stack.badge.plus") {
            newSectionTitle = ""
            addsIngredientSection = true
          }
        }

        Section("Method") {
          ForEach($steps) { step in
            EditableStepFields(step: step) {
              let id = step.wrappedValue.id
              steps.removeAll { $0.id == id }
            }
          }
          Button("Add step", systemImage: "plus") {
            steps.append(RecipeStep(title: "", detail: "", timerMinutes: 0))
          }
        }

        Section("Your notes") {
          TextEditor(text: $userNotes)
            .frame(minHeight: 120)
            .overlay(alignment: .topLeading) {
              if userNotes.isEmpty {
                Text("Substitutions, adjustments, or reminders…")
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 5)
                  .padding(.vertical, 8)
                  .allowsHitTesting(false)
                  .accessibilityHidden(true)
              }
            }
        }
      }
      .scrollContentBackground(.hidden)
      .background(palette.paper)
      .tint(palette.accent)
      .navigationTitle("Edit recipe")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { saveChanges() }
            .fontWeight(.semibold)
            .disabled(cleaning || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 360, minHeight: 520)
    .alert("Add ingredient section", isPresented: $addsIngredientSection) {
      TextField("Section name", text: $newSectionTitle)
      Button("Cancel", role: .cancel) {}
      Button("Add") {
        let title = newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
          ingredients.append(RecipeIngredient(amount: 1, unit: "", name: "", section: title))
        }
      }
    }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          photoData = data
        }
      }
    }
#if os(iOS)
    .sheet(isPresented: $isCameraPresented) {
      CameraPhotoCaptureView { data in
        selectedPhoto = nil
        photoData = data
        isCameraPresented = false
      } onCancel: {
        isCameraPresented = false
      }
      .ignoresSafeArea()
    }
    .alert("Camera unavailable", isPresented: $isCameraUnavailablePresented) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("This device doesn’t have an available camera. Choose a photo from your library instead.")
    }
#endif
  }

  private func cleanUpDraft() async {
    guard !cleaning else { return }
    cleaning = true
    defer { cleaning = false }

    let sourceIngredients = ingredients
    let sourceSteps = steps
    let sourceName = name
    let sourceCategory = category
    let source = """
      \(sourceName)
      Category: \(sourceCategory)
      Ingredients
      \(sourceIngredients.map { "\($0.displayAmount) \($0.unit) \($0.name) \($0.note)" }.joined(separator: "\n"))
      Instructions
      \(sourceSteps.enumerated().map { "\($0.offset + 1). \($0.element.title). \($0.element.detail)" }.joined(separator: "\n"))
      """
    let draft = try? await OnDeviceRecipeAI.extract(from: String(source.prefix(18_000)))
    guard !Task.isCancelled, ingredients == sourceIngredients, steps == sourceSteps, name == sourceName, category == sourceCategory else { return }

    ingredients = sourceIngredients.map(IngredientNormalization.clean)
    if let draft, draft.ingredients.count == sourceIngredients.count {
      ingredients = zip(sourceIngredients, draft.ingredients).map { original, cleaned in
        var result = cleaned
        result.id = original.id
        result.amount = original.amount
        result.unit = original.unit
        result.section = original.section ?? cleaned.section
        return IngredientNormalization.clean(result)
      }
    }
    let rewroteSteps = draft?.steps.count == sourceSteps.count
    steps = sourceSteps.enumerated().map { index, original in
      var step = original
      if rewroteSteps, let cleaned = draft?.steps[index] {
        step.title = cleaned.title
        step.detail = cleaned.detail
      }
      if let time = CookingTimeMention.matches(in: step.detail).first {
        step.timerMinutes = (time.seconds + 59) / 60
      }
      return step
    }
    category = draft?.category ?? DishCategory.infer(name: name, category: category, ingredients: ingredients).rawValue
    goodFor.formUnion(draft?.goodFor ?? [])
    cleanupMessage = "Review the updated ingredients, steps, and tags before saving."
  }

  private func saveChanges() {
    recipe.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    recipe.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    recipe.category = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Dinner" : category.trimmingCharacters(in: .whitespacesAndNewlines)
    recipe.difficulty = difficulty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Easy" : difficulty.trimmingCharacters(in: .whitespacesAndNewlines)
    recipe.servings = max(1, servings)
    recipe.caloriesPerServing = max(0, caloriesPerServing)
    recipe.prepMinutes = max(0, prepMinutes)
    recipe.cookMinutes = max(0, cookMinutes)
    recipe.ingredients = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    recipe.steps = steps.filter {
      !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !$0.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    recipe.userNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    recipe.goodFor = RecipeGoodFor.allCases.filter { goodFor.contains($0) }
    recipe.photoData = photoData
    onSave()
    dismiss()
  }
}

private struct EditableIngredientFields: View {
  @Binding var ingredient: RecipeIngredient
  var onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        TextField("Amount", value: $ingredient.amount, format: KitchenQuantity.Style())
#if os(iOS)
          .keyboardType(.numbersAndPunctuation)
#endif
          .frame(maxWidth: 110)
        TextField("Unit", text: $ingredient.unit)
          .frame(maxWidth: 130)
      }
      TextField("Ingredient", text: $ingredient.name)
      TextField("Note", text: $ingredient.note)
      Button("Remove ingredient", systemImage: "trash", role: .destructive, action: onDelete)
        .font(.caption)
        .frame(minHeight: 44, alignment: .leading)
    }
    .padding(.vertical, 5)
  }
}

private struct EditableStepFields: View {
  @Binding var step: RecipeStep
  var onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Step title", text: $step.title)
      TextField("Instructions", text: $step.detail, axis: .vertical)
        .lineLimit(2...5)
      StepTimerDurationPicker(duration: $step.timerMinutes)
      Button("Remove step", systemImage: "trash", role: .destructive, action: onDelete)
        .font(.caption)
        .frame(minHeight: 44, alignment: .leading)
    }
    .padding(.vertical, 5)
  }
}
