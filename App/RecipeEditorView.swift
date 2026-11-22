import SwiftUI
import PhotosUI

struct RecipeEditorView: View {
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

        Section("Ingredients") {
          ForEach($ingredients) { ingredient in
            EditableIngredientFields(ingredient: ingredient) {
              let id = ingredient.wrappedValue.id
              ingredients.removeAll { $0.id == id }
            }
          }
          Button("Add ingredient", systemImage: "plus") {
            ingredients.append(RecipeIngredient(amount: 1, unit: "", name: ""))
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
      .navigationTitle("Edit recipe")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { saveChanges() }
            .fontWeight(.semibold)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 360, minHeight: 520)
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
        TextField("Amount", value: $ingredient.amount, format: .number)
#if os(iOS)
          .keyboardType(.decimalPad)
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
      Stepper("Timer · \(step.timerMinutes) min", value: $step.timerMinutes, in: 0...1440, step: 5)
      Button("Remove step", systemImage: "trash", role: .destructive, action: onDelete)
        .font(.caption)
        .frame(minHeight: 44, alignment: .leading)
    }
    .padding(.vertical, 5)
  }
}
