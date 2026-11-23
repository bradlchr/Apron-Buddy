import SwiftUI

struct PantryFilterView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""

  var options: [String]
  @Binding var selected: Set<String>

  private var visibleOptions: [String] {
    search.isEmpty ? options : options.filter { $0.localizedStandardContains(search) }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(visibleOptions, id: \.self) { ingredient in
            let key = IngredientNormalization.key(ingredient)
            let isSelected = selected.contains(key)
            Button {
              if isSelected { selected.remove(key) } else { selected.insert(key) }
            } label: {
              HStack {
                Text(ingredient)
                Spacer()
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .disabled(!isSelected && selected.count == 3)
          }
        } header: {
          Text("Choose up to 3 ingredients")
        } footer: {
          Text("Recipes must contain every selected ingredient. They may still call for other ingredients.")
        }
      }
      .searchable(text: $search, prompt: "Find an ingredient")
      .scrollContentBackground(.hidden)
      .background(palette.paper)
      .tint(palette.accent)
      .navigationTitle("Cook with what I have")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if !selected.isEmpty { Button("Clear") { selected.removeAll() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 400, minHeight: 430)
    #endif
  }
}
