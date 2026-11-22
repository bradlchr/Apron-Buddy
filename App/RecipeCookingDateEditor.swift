import SwiftData
import SwiftUI

struct RecipeCookingDateEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var date: Date
  @State private var showsSaveError = false

  var recipe: Recipe

  init(recipe: Recipe) {
    self.recipe = recipe
    _date = State(initialValue: min(.now, recipe.lastCooked ?? .now))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          DatePicker("Date cooked", selection: $date, in: ...Date.now, displayedComponents: .date)
          Button("Use today") { update(.now) }
        } header: {
          Text(recipe.name)
        }
        if recipe.lastCooked != nil {
          Button("Clear last cooked date", role: .destructive) { update(nil) }
        }
      }
      .navigationTitle("Last cooked")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { update(date) }
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 360, minHeight: 240)
    #endif
    .alert("Couldn’t save the last cooked date", isPresented: $showsSaveError) {
      Button("OK", role: .cancel) { }
    }
  }

  private func update(_ date: Date?) {
    do {
      try recipe.saveLastCooked(date, in: modelContext)
      dismiss()
    } catch {
      showsSaveError = true
    }
  }
}
