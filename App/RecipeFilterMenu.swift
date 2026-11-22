import SwiftUI

struct RecipeFilterMenu: View {
  var categories: [String]
  @Binding var category: String
  @Binding var goodFor: RecipeGoodFor?
  @Binding var minimumRating: Int

  private var activeFilterCount: Int {
    (category == "All" ? 0 : 1) + (goodFor == nil ? 0 : 1) + (minimumRating == 0 ? 0 : 1)
  }

  var body: some View {
    Menu {
      Picker("Category", selection: $category) {
        Text("All categories").tag("All")
        ForEach(categories, id: \.self) { value in
          Text(value).tag(value)
        }
      }
      Picker("Good for", selection: $goodFor) {
        Text("Any occasion").tag(RecipeGoodFor?.none)
        ForEach(RecipeGoodFor.allCases) { value in
          Text(value.title).tag(Optional(value))
        }
      }
      Picker("Rating", selection: $minimumRating) {
        Text("Any rating").tag(0)
        ForEach(1...5, id: \.self) { value in
          Text("\(value) stars and up").tag(value)
        }
      }
      if activeFilterCount > 0 {
        Divider()
        Button("Clear filters", systemImage: "line.3.horizontal.decrease") {
          category = "All"
          goodFor = nil
          minimumRating = 0
        }
      }
    } label: {
      Label(activeFilterCount == 0 ? "Filter" : "Filter · \(activeFilterCount)", systemImage: "line.3.horizontal.decrease.circle")
    }
    .accessibilityLabel(activeFilterCount == 0 ? "Filter recipes" : "Filter recipes, \(activeFilterCount) filters active")
  }
}
